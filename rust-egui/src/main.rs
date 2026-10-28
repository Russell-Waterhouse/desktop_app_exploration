use eframe::egui;
use rusqlite::{params, Connection};

// SQLite storage for the recipe manager.
// The database file, recipes.db, is created in the current working
// directory on first run. The three recipes below are seed data only:
// they are inserted once, when the recipes table is empty, and after
// that the app loads from the database, not from this code.
struct Ingredient {
    amount: String,
    unit: String,
    name: String,
}

struct Recipe {
    title: String,
    description: String,
    servings: i64,
    prep_minutes: i64,
    cook_minutes: i64,
    ingredients: Vec<Ingredient>,
    steps: Vec<String>,
    notes: String,
}

fn seed_recipes() -> Vec<Recipe> {
    vec![
        Recipe {
            title: "Banana Bread".to_string(),
            description: "A classic loaf, best with very ripe bananas.".to_string(),
            servings: 8,
            prep_minutes: 15,
            cook_minutes: 60,
            ingredients: vec![
                Ingredient { amount: "3".to_string(), unit: "".to_string(), name: "ripe bananas, mashed".to_string() },
                Ingredient { amount: "1/2".to_string(), unit: "cup".to_string(), name: "butter, melted".to_string() },
                Ingredient { amount: "3/4".to_string(), unit: "cup".to_string(), name: "sugar".to_string() },
                Ingredient { amount: "1".to_string(), unit: "".to_string(), name: "egg".to_string() },
                Ingredient { amount: "1".to_string(), unit: "tsp".to_string(), name: "vanilla".to_string() },
                Ingredient { amount: "1".to_string(), unit: "tsp".to_string(), name: "baking soda".to_string() },
                Ingredient { amount: "1 1/2".to_string(), unit: "cups".to_string(), name: "flour".to_string() },
            ],
            steps: vec![
                "Preheat the oven to 350°F and grease a 9x5 loaf pan.".to_string(),
                "Mash the bananas, then stir in the melted butter, sugar, egg, and vanilla.".to_string(),
                "Stir in the baking soda and flour until just combined.".to_string(),
                "Pour into the pan and bake for 55-65 minutes, until a toothpick comes out clean.".to_string(),
                "Cool in the pan for 10 minutes, then turn out onto a rack.".to_string(),
            ],
            notes: "Optional: fold in walnuts or chocolate chips before baking.".to_string(),
        },
        Recipe {
            title: "Tomato Basil Pasta".to_string(),
            description: "A quick weeknight pasta with fresh tomatoes and basil.".to_string(),
            servings: 4,
            prep_minutes: 10,
            cook_minutes: 20,
            ingredients: vec![
                Ingredient { amount: "12".to_string(), unit: "oz".to_string(), name: "pasta".to_string() },
                Ingredient { amount: "2".to_string(), unit: "lbs".to_string(), name: "tomatoes, chopped".to_string() },
                Ingredient { amount: "3".to_string(), unit: "cloves".to_string(), name: "garlic, sliced".to_string() },
                Ingredient { amount: "1/4".to_string(), unit: "cup".to_string(), name: "olive oil".to_string() },
                Ingredient { amount: "1".to_string(), unit: "cup".to_string(), name: "basil leaves".to_string() },
                Ingredient { amount: "1/2".to_string(), unit: "cup".to_string(), name: "parmesan, grated".to_string() },
            ],
            steps: vec![
                "Cook the pasta in salted water until al dente, reserving a cup of pasta water.".to_string(),
                "Meanwhile, warm the olive oil and garlic until fragrant, about 2 minutes.".to_string(),
                "Add the tomatoes and cook until they soften, about 8 minutes.".to_string(),
                "Toss the pasta with the sauce, basil, and parmesan, adding pasta water as needed.".to_string(),
            ],
            notes: "Serve immediately, with extra parmesan on top.".to_string(),
        },
        Recipe {
            title: "Chicken Stir Fry".to_string(),
            description: "Chicken and vegetables in a simple soy-ginger sauce, served with rice.".to_string(),
            servings: 4,
            prep_minutes: 15,
            cook_minutes: 15,
            ingredients: vec![
                Ingredient { amount: "1 1/2".to_string(), unit: "lbs".to_string(), name: "chicken breast, sliced".to_string() },
                Ingredient { amount: "2".to_string(), unit: "".to_string(), name: "bell peppers, sliced".to_string() },
                Ingredient { amount: "2".to_string(), unit: "cups".to_string(), name: "broccoli florets".to_string() },
                Ingredient { amount: "3".to_string(), unit: "tbsp".to_string(), name: "soy sauce".to_string() },
                Ingredient { amount: "1".to_string(), unit: "tbsp".to_string(), name: "ginger, grated".to_string() },
                Ingredient { amount: "2".to_string(), unit: "cloves".to_string(), name: "garlic, minced".to_string() },
            ],
            steps: vec![
                "Sear the chicken in a hot, oiled pan until cooked through, then set aside.".to_string(),
                "Stir fry the peppers and broccoli until just tender, about 4 minutes.".to_string(),
                "Return the chicken to the pan with the soy sauce, ginger, and garlic.".to_string(),
                "Cook for 2 more minutes, stirring, until the sauce coats everything.".to_string(),
            ],
            notes: "Serve over rice.".to_string(),
        },
    ]
}

fn load_recipes() -> rusqlite::Result<Vec<Recipe>> {
    let mut conn = Connection::open("recipes.db")?;
    conn.execute_batch(
        "PRAGMA foreign_keys = ON;
         CREATE TABLE IF NOT EXISTS recipes (
             id INTEGER PRIMARY KEY,
             title TEXT NOT NULL,
             description TEXT NOT NULL,
             servings INTEGER NOT NULL,
             prep_minutes INTEGER NOT NULL,
             cook_minutes INTEGER NOT NULL,
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
    )?;

    let count: i64 = conn.query_row("SELECT COUNT(*) FROM recipes", [], |row| row.get(0))?;
    if count == 0 {
        let tx = conn.transaction()?;
        for recipe in seed_recipes() {
            tx.execute(
                "INSERT INTO recipes (title, description, servings, prep_minutes, cook_minutes, image_path, notes)
                 VALUES (?1, ?2, ?3, ?4, ?5, NULL, ?6)",
                params![
                    recipe.title,
                    recipe.description,
                    recipe.servings,
                    recipe.prep_minutes,
                    recipe.cook_minutes,
                    recipe.notes
                ],
            )?;
            let recipe_id = tx.last_insert_rowid();
            for (position, ingredient) in recipe.ingredients.iter().enumerate() {
                tx.execute(
                    "INSERT INTO ingredients (recipe_id, position, amount, unit, name)
                     VALUES (?1, ?2, ?3, ?4, ?5)",
                    params![recipe_id, position as i64, ingredient.amount, ingredient.unit, ingredient.name],
                )?;
            }
            for (position, step) in recipe.steps.iter().enumerate() {
                tx.execute(
                    "INSERT INTO steps (recipe_id, position, text) VALUES (?1, ?2, ?3)",
                    params![recipe_id, position as i64, step],
                )?;
            }
        }
        tx.commit()?;
    }

    // Collect recipe metadata first, so the statement is dropped
    // before querying ingredients and steps for each recipe.
    let mut meta: Vec<(i64, String, String, i64, i64, i64, String)> = Vec::new();
    {
        let mut stmt = conn.prepare(
            "SELECT id, title, description, servings, prep_minutes, cook_minutes, notes
             FROM recipes ORDER BY id",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, i64>(4)?,
                row.get::<_, i64>(5)?,
                row.get::<_, String>(6)?,
            ))
        })?;
        for row in rows {
            meta.push(row?);
        }
    }

    let mut recipes = Vec::new();
    for (id, title, description, servings, prep_minutes, cook_minutes, notes) in meta {
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
            title,
            description,
            servings,
            prep_minutes,
            cook_minutes,
            ingredients,
            steps,
            notes,
        });
    }
    Ok(recipes)
}

struct RecipeApp {
    recipes: Vec<Recipe>,
    selected: usize,
    search: String,
    load_error: Option<String>,
}

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([900.0, 600.0]),
        ..Default::default()
    };
    eframe::run_native(
        "Recipe Manager",
        options,
        Box::new(|_cc| {
            let (recipes, load_error) = match load_recipes() {
                Ok(recipes) => (recipes, None),
                Err(err) => (Vec::new(), Some(err.to_string())),
            };
            Ok(Box::new(RecipeApp {
                recipes,
                selected: 0,
                search: String::new(),
                load_error,
            }))
        }),
    )
}

impl eframe::App for RecipeApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        // Edit a copy of the search text inside the panel to keep
        // the borrow checker happy, then write it back afterwards.
        let mut selected = self.selected;
        let mut search = self.search.clone();

        egui::Panel::left("recipe_list").show(ui, |ui| {
            ui.heading("Recipes");
            ui.label("Search recipes:");
            ui.add(
                egui::TextEdit::singleline(&mut search)
                    .hint_text("Type to filter recipes…"),
            );
            ui.separator();
            egui::ScrollArea::vertical().show(ui, |ui| {
                let query = search.to_lowercase();
                for (index, recipe) in self.recipes.iter().enumerate() {
                    if !query.is_empty() && !recipe.title.to_lowercase().contains(&query) {
                        continue;
                    }
                    if ui.selectable_label(selected == index, &recipe.title).clicked() {
                        selected = index;
                    }
                }
            });
        });

        self.selected = selected;
        self.search = search;

        egui::CentralPanel::default().show(ui, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| {
                if let Some(error) = &self.load_error {
                    ui.heading("Could not load recipes");
                    ui.label(error);
                } else if let Some(recipe) = self.recipes.get(self.selected) {
                    ui.heading(&recipe.title);
                    ui.label(&recipe.description);
                    ui.label(format!(
                        "Servings: {}  •  Prep: {} min  •  Cook: {} min",
                        recipe.servings, recipe.prep_minutes, recipe.cook_minutes
                    ));
                    ui.separator();
                    ui.label("[No image yet]");
                    ui.separator();

                    ui.heading("Ingredients");
                    for ingredient in &recipe.ingredients {
                        if ingredient.unit.is_empty() {
                            ui.label(format!("• {} {}", ingredient.amount, ingredient.name));
                        } else {
                            ui.label(format!(
                                "• {} {} {}",
                                ingredient.amount, ingredient.unit, ingredient.name
                            ));
                        }
                    }
                    ui.separator();

                    ui.heading("Steps");
                    for (index, step) in recipe.steps.iter().enumerate() {
                        ui.label(format!("{}. {}", index + 1, step));
                    }
                    ui.separator();

                    ui.heading("Notes");
                    ui.label(&recipe.notes);
                } else {
                    ui.label("No recipe selected.");
                }
            });
        });
    }
}
