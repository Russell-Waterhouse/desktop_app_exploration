import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import db from '../../electron/db.cjs'
import { SEED_RECIPES } from '../../src/shared/seed.js'

let dir
let database

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'electron-react-db-test-'))
  database = db.openDatabase(join(dir, 'recipes.db'))
  db.ensureSchemaAndSeed(database, SEED_RECIPES)
})

afterEach(() => {
  db.closeDatabase(database)
  rmSync(dir, { recursive: true, force: true })
})

describe('SQLite layer', () => {
  it('seeds 7 recipes, 27 ingredients, 21 steps on first run', () => {
    const recipes = db.loadRecipes(database)
    expect(recipes).toHaveLength(7)
    expect(recipes.reduce((n, r) => n + r.ingredients.length, 0)).toBe(27)
    expect(recipes.reduce((n, r) => n + r.steps.length, 0)).toBe(21)
  })

  it('does not re-seed when the table is not empty', () => {
    db.ensureSchemaAndSeed(database, SEED_RECIPES)
    expect(db.loadRecipes(database)).toHaveLength(7)
  })

  it('inserts, updates, and deletes a recipe with its children', () => {
    const id = db.insertRecipe(database, {
      title: 'Test Soup',
      description: 'd',
      servings: 2,
      image_path: '',
      notes: 'n',
      ingredients: [{ amount: '1', unit: 'cup', name: 'water' }],
      steps: ['Boil.'],
    })
    expect(db.loadRecipes(database)).toHaveLength(8)
    db.updateRecipe(database, {
      id,
      title: 'Test Soup 2',
      description: 'd',
      servings: 3,
      image_path: '',
      notes: 'n',
      ingredients: [],
      steps: [],
    })
    const updated = db.loadRecipes(database).find((r) => r.id === id)
    expect(updated.title).toBe('Test Soup 2')
    expect(updated.ingredients).toEqual([])
    db.deleteRecipe(database, id)
    expect(db.loadRecipes(database)).toHaveLength(7)
  })

  it('stores an empty image_path as NULL and loads it back as ""', () => {
    const recipes = db.loadRecipes(database)
    expect(recipes[0].image_path).toBe('')
  })
})
