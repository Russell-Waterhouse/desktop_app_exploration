// SQLite access for the recipe manager, using Node 24's
// built-in node:sqlite (DatabaseSync). Verified to work
// under Electron 45's bundled Node 24.22.2, so no native
// dependency (no better-sqlite3) is needed.
//
// Schema matches the other stacks (odin-gtk/src/db.odin,
// rust-egui/src/db.rs): recipes (id, title, description,
// servings, image_path, notes), ingredients (id, recipe_id,
// position, amount, unit, name), steps (id, recipe_id,
// position, text), with foreign keys on. The database file,
// recipes.db, is created in the current working directory
// on first run and is git-ignored, not pushed.
//
// The connection is held open for the app's lifetime
// (single-user app) and closed when the app quits. All
// methods are synchronous, like the other stacks' SQLite
// calls; the UI stays responsive because the work is small
// and the network fetch runs async before the inserts.

const { DatabaseSync } = require('node:sqlite')

function openDatabase(path) {
  const db = new DatabaseSync(path)
  db.exec('PRAGMA foreign_keys = ON')
  return db
}

function closeDatabase(db) {
  if (db) {
    db.close()
  }
}

function ensureSchemaAndSeed(db, seed) {
  db.exec(`
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
    );
  `)
  // Seed once, only when the recipes table is empty.
  const count = db.prepare('SELECT COUNT(*) AS n FROM recipes').get().n
  if (count !== 0) {
    return
  }
  db.exec('BEGIN')
  try {
    for (const recipe of seed) {
      insertRecipeInTransaction(db, recipe)
    }
    db.exec('COMMIT')
  } catch (e) {
    db.exec('ROLLBACK')
    throw e
  }
}

function insertChildren(db, recipeId, recipe) {
  const insertIng = db.prepare(
    'INSERT INTO ingredients (recipe_id, position, amount, unit, name) VALUES (?, ?, ?, ?, ?)',
  )
  ;(recipe.ingredients ?? []).forEach((ing, i) => {
    insertIng.run(recipeId, i, ing.amount ?? '', ing.unit ?? '', ing.name ?? '')
  })
  const insertStep = db.prepare(
    'INSERT INTO steps (recipe_id, position, text) VALUES (?, ?, ?)',
  )
  ;(recipe.steps ?? []).forEach((step, i) => {
    insertStep.run(recipeId, i, step)
  })
}

function insertRecipeInTransaction(db, recipe) {
  const result = db
    .prepare(
      'INSERT INTO recipes (title, description, servings, image_path, notes) VALUES (?, ?, ?, ?, ?)',
    )
    .run(
      recipe.title,
      recipe.description ?? '',
      recipe.servings ?? 0,
      recipe.image_path ? recipe.image_path : null,
      recipe.notes ?? '',
    )
  const id = Number(result.lastInsertRowid)
  insertChildren(db, id, recipe)
  return id
}

// Insert a new recipe (and its ingredients and steps) in one
// transaction. Returns the new row id. An empty image_path
// is stored as NULL.
function insertRecipe(db, recipe) {
  db.exec('BEGIN')
  try {
    const id = insertRecipeInTransaction(db, recipe)
    db.exec('COMMIT')
    return id
  } catch (e) {
    db.exec('ROLLBACK')
    throw e
  }
}

// Update a recipe and replace its ingredients and steps, in
// one transaction.
function updateRecipe(db, recipe) {
  db.exec('BEGIN')
  try {
    db.prepare(
      'UPDATE recipes SET title = ?, description = ?, servings = ?, image_path = ?, notes = ? WHERE id = ?',
    ).run(
      recipe.title,
      recipe.description ?? '',
      recipe.servings ?? 0,
      recipe.image_path ? recipe.image_path : null,
      recipe.notes ?? '',
      recipe.id,
    )
    db.prepare('DELETE FROM ingredients WHERE recipe_id = ?').run(recipe.id)
    db.prepare('DELETE FROM steps WHERE recipe_id = ?').run(recipe.id)
    insertChildren(db, recipe.id, recipe)
    db.exec('COMMIT')
  } catch (e) {
    db.exec('ROLLBACK')
    throw e
  }
}

// Delete a recipe and its ingredients and steps, in one
// transaction. The schema has no ON DELETE CASCADE, so the
// children are deleted explicitly, before the recipe row.
function deleteRecipe(db, id) {
  db.exec('BEGIN')
  try {
    db.prepare('DELETE FROM ingredients WHERE recipe_id = ?').run(id)
    db.prepare('DELETE FROM steps WHERE recipe_id = ?').run(id)
    db.prepare('DELETE FROM recipes WHERE id = ?').run(id)
    db.exec('COMMIT')
  } catch (e) {
    db.exec('ROLLBACK')
    throw e
  }
}

function loadRecipes(db) {
  const rows = db
    .prepare(
      'SELECT id, title, description, servings, image_path, notes FROM recipes ORDER BY id',
    )
    .all()
  return rows.map((row) => {
    const ingredients = db
      .prepare(
        'SELECT amount, unit, name FROM ingredients WHERE recipe_id = ? ORDER BY position',
      )
      .all(row.id)
    const steps = db
      .prepare('SELECT text FROM steps WHERE recipe_id = ? ORDER BY position')
      .all(row.id)
      .map((s) => s.text)
    return {
      id: row.id,
      title: row.title,
      description: row.description,
      servings: row.servings,
      image_path: row.image_path ?? '',
      notes: row.notes,
      ingredients,
      steps,
    }
  })
}

module.exports = {
  openDatabase,
  closeDatabase,
  ensureSchemaAndSeed,
  loadRecipes,
  insertRecipe,
  updateRecipe,
  deleteRecipe,
}
