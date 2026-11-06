// Recipe JSON parsing and serialisation, mirroring
// odin-gtk/src/json_import.odin and json_export.odin (which
// mirror rust-egui's json_import.rs). Pure functions: no
// Electron, no filesystem, so unit tests import this directly.
//
// Accepted document shapes:
//   - a single recipe object: {"title": ..., ...}
//   - a bare array of recipe objects: [{...}, {...}]
//   - a collection object: {"recipes": [...]}
// A recipe's fields follow test-data/recipes.json: title,
// description, servings, image_path, notes, ingredients
// (amount, unit, name objects, in order), and steps (strings,
// in order). Missing description, notes, ingredients, or
// steps default to empty; missing image_path defaults to ""
// (stored as NULL in SQLite); missing servings defaults to 0.
// A recipe with no usable title is an error, not a recipe
// with an empty title in the list.
//
// Export shapes: a single recipe as a pretty-printed bare
// object, a collection as a pretty-printed {"recipes": [...]}
// object (the shape test-data/recipes.json uses). Field order
// is title, description, servings, image_path, notes,
// ingredients, steps; image_path "" writes as null; empty
// arrays write on one line ("ingredients": []). JSON.stringify
// with 2-space indent produces exactly that, matching
// serde_json::to_string_pretty.

export const PARSE_ERROR = 'Could not parse recipe JSON: '
export const SHAPE_ERROR =
  'JSON must be a single recipe, an array of recipes, or an object with a "recipes" array.'

function stringField(obj, name) {
  if (!(name in obj)) {
    return { value: '', present: false }
  }
  const raw = obj[name]
  if (raw === null || raw === undefined) {
    return { value: '', present: true }
  }
  if (typeof raw !== 'string') {
    throw new Error(`${PARSE_ERROR}${name} has the wrong type.`)
  }
  return { value: raw, present: true }
}

function parseRecipeObject(obj) {
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
    throw new Error(`${PARSE_ERROR}recipe must be an object.`)
  }
  const title = stringField(obj, 'title')
  if (!title.present || title.value.trim() === '') {
    throw new Error('Imported recipe is missing a title.')
  }
  const recipe = { title: title.value }
  recipe.description = stringField(obj, 'description').value
  if ('servings' in obj && obj.servings !== null && obj.servings !== undefined) {
    if (!Number.isInteger(obj.servings)) {
      throw new Error(`${PARSE_ERROR}servings has the wrong type.`)
    }
    recipe.servings = obj.servings
  } else {
    recipe.servings = 0
  }
  recipe.image_path = stringField(obj, 'image_path').value
  recipe.notes = stringField(obj, 'notes').value
  recipe.ingredients = []
  if ('ingredients' in obj && obj.ingredients !== null && obj.ingredients !== undefined) {
    if (!Array.isArray(obj.ingredients)) {
      throw new Error(`${PARSE_ERROR}ingredients has the wrong type.`)
    }
    for (const item of obj.ingredients) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        throw new Error(`${PARSE_ERROR}ingredients must be objects.`)
      }
      recipe.ingredients.push({
        amount: stringField(item, 'amount').value,
        unit: stringField(item, 'unit').value,
        name: stringField(item, 'name').value,
      })
    }
  }
  recipe.steps = []
  if ('steps' in obj && obj.steps !== null && obj.steps !== undefined) {
    if (!Array.isArray(obj.steps)) {
      throw new Error(`${PARSE_ERROR}steps has the wrong type.`)
    }
    for (const step of obj.steps) {
      if (typeof step !== 'string') {
        throw new Error(`${PARSE_ERROR}steps must be strings.`)
      }
      recipe.steps.push(step)
    }
  }
  return recipe
}

// Parse a whole document in any of the three accepted shapes.
// Throws an Error with the importer's message on failure.
export function parseRecipes(text) {
  let value
  try {
    value = JSON.parse(text)
  } catch (e) {
    throw new Error(`${PARSE_ERROR}${e.message}.`)
  }
  if (Array.isArray(value)) {
    return value.map((item) => parseRecipeObject(item))
  }
  if (value !== null && typeof value === 'object') {
    if ('recipes' in value) {
      if (!Array.isArray(value.recipes)) {
        throw new Error('The "recipes" field must be an array of recipes.')
      }
      return value.recipes.map((item) => parseRecipeObject(item))
    }
    if ('title' in value) {
      return [parseRecipeObject(value)]
    }
    throw new Error(SHAPE_ERROR)
  }
  throw new Error(SHAPE_ERROR)
}

// One recipe as a plain object in export field order, for
// JSON.stringify. image_path "" writes as null.
export function recipeToJsonObject(recipe) {
  return {
    title: recipe.title,
    description: recipe.description ?? '',
    servings: recipe.servings ?? 0,
    image_path: recipe.image_path ? recipe.image_path : null,
    notes: recipe.notes ?? '',
    ingredients: (recipe.ingredients ?? []).map((ing) => ({
      amount: ing.amount ?? '',
      unit: ing.unit ?? '',
      name: ing.name ?? '',
    })),
    steps: recipe.steps ?? [],
  }
}

export function exportSingle(recipe) {
  return JSON.stringify(recipeToJsonObject(recipe), null, 2)
}

export function exportCollection(recipes) {
  return JSON.stringify(
    { recipes: recipes.map((r) => recipeToJsonObject(r)) },
    null,
    2,
  )
}

// A file name derived from a recipe title, safe to offer as
// the single-recipe export field's default: characters that
// are not letters, digits, spaces, hyphens, or underscores
// become underscores, so a title like "Fish & Chips" does
// not become a strange file name, and a title containing
// "/" cannot escape the chosen directory. The result is
// trimmed, and an empty result falls back to "recipe.json".
export function defaultFileName(title) {
  const sanitized = title.replace(/[^\p{L}\p{N} _-]/gu, '_').trim()
  if (sanitized === '') {
    return 'recipe.json'
  }
  return `${sanitized}.json`
}
