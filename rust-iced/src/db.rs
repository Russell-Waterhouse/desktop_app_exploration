// SQLite access for the recipe manager.
// Each function opens its own connection, so the app never holds
// a connection open across UI frames. Single-user app, so this
// keeps borrowing simple and is fast enough for this data size.
// The database file, recipes.db, is created in the current working
// directory on first run.
use crate::{seed, Ingredient, Recipe};
use rusqlite::{params, Connection};

fn ensure_schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "PRAGMA foreign_keys = ON;
         CREATE TABLE IF NOT EXISTS recipes (
             id INTEGER PRIMARY KEY,
             title TEXT NOT NULL,
             description TEXT NOT NULL,
             servings INTEGER NOT NULL,
             image_path TEXT,
             notes TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS ingredients (
             id INTEGER PRIMARY KEY,
             recipe_id INTEGER NOT NULL REFERENCES recipes(id),
             position INTEGER NOT NULL,
             amount TEXT NOT NULL,
             unit TEXT NOT NULL,
             name TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS steps (
             id INTEGER PRIMARY KEY,
             recipe_id INTEGER NOT NULL REFERENCES recipes(id),
             position INTEGER NOT NULL,
             text TEXT NOT NULL
         );",
    )
}

fn insert_children(
    tx: &rusqlite::Transaction,
    recipe_id: i64,
    recipe: &Recipe,
) -> rusqlite::Result<()> {
    for (position, ingredient) in recipe.ingredients.iter().enumerate() {
        tx.execute(
            "INSERT INTO ingredients (recipe_id, position, amount, unit, name)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                recipe_id,
                position as i64,
                ingredient.amount,
                ingredient.unit,
                ingredient.name
            ],
        )?;
    }
    for (position, step) in recipe.steps.iter().enumerate() {
        tx.execute(
            "INSERT INTO steps (recipe_id, position, text) VALUES (?1, ?2, ?3)",
            params![recipe_id, position as i64, step],
        )?;
    }
    Ok(())
}

pub(crate) fn load_recipes() -> rusqlite::Result<Vec<Recipe>> {
    let mut conn = Connection::open("recipes.db")?;
    ensure_schema(&conn)?;

    let count: i64 = conn.query_row("SELECT COUNT(*) FROM recipes", [], |row| row.get(0))?;
    if count == 0 {
        let tx = conn.transaction()?;
        for recipe in seed::seed_recipes() {
            tx.execute(
                "INSERT INTO recipes (title, description, servings, image_path, notes)
                 VALUES (?1, ?2, ?3, NULL, ?4)",
                params![
                    recipe.title,
                    recipe.description,
                    recipe.servings,
                    recipe.notes
                ],
            )?;
            let recipe_id = tx.last_insert_rowid();
            insert_children(&tx, recipe_id, &recipe)?;
        }
        tx.commit()?;
    }

    // Collect recipe metadata first, so the statement is dropped
    // before querying ingredients and steps for each recipe.
    let mut meta: Vec<(i64, String, String, i64, Option<String>, String)> = Vec::new();
    {
        let mut stmt = conn.prepare(
            "SELECT id, title, description, servings, image_path, notes
             FROM recipes ORDER BY id",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, Option<String>>(4)?,
                row.get::<_, String>(5)?,
            ))
        })?;
        for row in rows {
            meta.push(row?);
        }
    }

    let mut recipes = Vec::new();
    for (id, title, description, servings, image_path, notes) in meta {
        let mut ingredients = Vec::new();
        {
            let mut stmt = conn.prepare(
                "SELECT amount, unit, name FROM ingredients
                 WHERE recipe_id = ?1 ORDER BY position",
            )?;
            let rows = stmt.query_map(params![id], |row| {
                Ok(Ingredient {
                    amount: row.get(0)?,
                    unit: row.get(1)?,
                    name: row.get(2)?,
                })
            })?;
            for row in rows {
                ingredients.push(row?);
            }
        }
        let mut steps = Vec::new();
        {
            let mut stmt = conn.prepare(
                "SELECT text FROM steps WHERE recipe_id = ?1 ORDER BY position",
            )?;
            let rows = stmt.query_map(params![id], |row| row.get::<_, String>(0))?;
            for row in rows {
                steps.push(row?);
            }
        }
        recipes.push(Recipe {
            id,
            title,
            description,
            servings,
            image_path,
            ingredients,
            steps,
            notes,
        });
    }
    Ok(recipes)
}

pub(crate) fn insert_recipe(recipe: &Recipe) -> rusqlite::Result<i64> {
    let mut conn = Connection::open("recipes.db")?;
    ensure_schema(&conn)?;
    let tx = conn.transaction()?;
    tx.execute(
        "INSERT INTO recipes (title, description, servings, image_path, notes)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![
            recipe.title,
            recipe.description,
            recipe.servings,
            recipe.image_path,
            recipe.notes
        ],
    )?;
    let recipe_id = tx.last_insert_rowid();
    insert_children(&tx, recipe_id, recipe)?;
    tx.commit()?;
    Ok(recipe_id)
}

pub(crate) fn update_recipe(recipe: &Recipe) -> rusqlite::Result<()> {
    let mut conn = Connection::open("recipes.db")?;
    ensure_schema(&conn)?;
    let tx = conn.transaction()?;
    tx.execute(
        "UPDATE recipes SET title = ?1, description = ?2, servings = ?3,
         image_path = ?4, notes = ?5
         WHERE id = ?6",
        params![
            recipe.title,
            recipe.description,
            recipe.servings,
            recipe.image_path,
            recipe.notes,
            recipe.id
        ],
    )?;
    tx.execute("DELETE FROM ingredients WHERE recipe_id = ?1", params![recipe.id])?;
    tx.execute("DELETE FROM steps WHERE recipe_id = ?1", params![recipe.id])?;
    insert_children(&tx, recipe.id, recipe)?;
    tx.commit()?;
    Ok(())
}

pub(crate) fn delete_recipe(id: i64) -> rusqlite::Result<()> {
    let mut conn = Connection::open("recipes.db")?;
    ensure_schema(&conn)?;
    let tx = conn.transaction()?;
    // Explicit child deletes, not ON DELETE CASCADE: databases created
    // before this feature do not have cascade on these foreign keys,
    // so relying on it would leave orphan rows there.
    tx.execute("DELETE FROM ingredients WHERE recipe_id = ?1", params![id])?;
    tx.execute("DELETE FROM steps WHERE recipe_id = ?1", params![id])?;
    tx.execute("DELETE FROM recipes WHERE id = ?1", params![id])?;
    tx.commit()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn insert_update_delete_round_trip() {
        let tmp = env::temp_dir().join(format!("recipe-test-{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        let original = env::current_dir().unwrap();
        env::set_current_dir(&tmp).unwrap();

        let recipes = load_recipes().unwrap();
        assert_eq!(recipes.len(), 3);

        let mut new = Recipe {
            id: 0,
            title: "Test Soup".to_string(),
            description: "Test".to_string(),
            servings: 2,
            image_path: None,
            ingredients: vec![Ingredient {
                amount: "1".to_string(),
                unit: "cup".to_string(),
                name: "water".to_string(),
            }],
            steps: vec!["Boil.".to_string()],
            notes: String::new(),
        };
        let id = insert_recipe(&new).unwrap();
        new.id = id;
        let recipes = load_recipes().unwrap();
        assert_eq!(recipes.len(), 4);
        assert!(recipes.iter().any(|r| r.title == "Test Soup"));

        new.title = "Test Soup Edited".to_string();
        update_recipe(&new).unwrap();
        let recipes = load_recipes().unwrap();
        assert!(recipes.iter().any(|r| r.title == "Test Soup Edited"));

        delete_recipe(id).unwrap();
        let recipes = load_recipes().unwrap();
        assert_eq!(recipes.len(), 3);
        assert!(!recipes.iter().any(|r| r.title == "Test Soup Edited"));

        env::set_current_dir(original).unwrap();
        let _ = std::fs::remove_dir_all(&tmp);
    }
}
