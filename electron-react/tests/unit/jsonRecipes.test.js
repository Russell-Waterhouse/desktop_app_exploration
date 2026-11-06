import { describe, expect, it } from 'vitest'
import {
  parseRecipes,
  exportSingle,
  exportCollection,
  defaultFileName,
} from '../../src/shared/jsonRecipes.js'

describe('parseRecipes', () => {
  it('parses a single recipe object', () => {
    const recipes = parseRecipes(JSON.stringify({ title: 'Soup', servings: 2 }))
    expect(recipes).toHaveLength(1)
    expect(recipes[0].title).toBe('Soup')
    expect(recipes[0].servings).toBe(2)
    expect(recipes[0].description).toBe('')
    expect(recipes[0].ingredients).toEqual([])
    expect(recipes[0].steps).toEqual([])
    expect(recipes[0].image_path).toBe('')
  })

  it('parses a bare array and a {"recipes": [...]} collection', () => {
    const one = { title: 'A' }
    const two = { title: 'B' }
    expect(parseRecipes(JSON.stringify([one, two]))).toHaveLength(2)
    expect(parseRecipes(JSON.stringify({ recipes: [one, two] })).map((r) => r.title)).toEqual([
      'A',
      'B',
    ])
  })

  it('rejects a document that is neither shape', () => {
    expect(() => parseRecipes(JSON.stringify({ foo: 1 }))).toThrow(
      'JSON must be a single recipe',
    )
    expect(() => parseRecipes('42')).toThrow('JSON must be a single recipe')
  })

  it('rejects a recipe with no usable title', () => {
    expect(() => parseRecipes(JSON.stringify({ title: '  ' }))).toThrow(
      'Imported recipe is missing a title.',
    )
    // An object with no title key at all is not a recipe
    // shape (like odin: SHAPE_ERROR), while a present but
    // blank title is a missing-title error.
    expect(() => parseRecipes(JSON.stringify({ description: 'x' }))).toThrow(
      'JSON must be a single recipe',
    )
  })

  it('rejects wrong field types', () => {
    expect(() => parseRecipes(JSON.stringify({ title: 5 }))).toThrow(
      'Could not parse recipe JSON: title has the wrong type.',
    )
    expect(() =>
      parseRecipes(JSON.stringify({ title: 'T', servings: 'four' })),
    ).toThrow('Could not parse recipe JSON: servings has the wrong type.')
  })

  it('rejects malformed JSON', () => {
    expect(() => parseRecipes('{not json')).toThrow('Could not parse recipe JSON: ')
  })

  it('keeps ingredient and step order', () => {
    const recipes = parseRecipes(
      JSON.stringify({
        title: 'T',
        ingredients: [
          { amount: '1', unit: 'cup', name: 'a' },
          { amount: '2', unit: '', name: 'b' },
        ],
        steps: ['First.', 'Second.'],
      }),
    )
    expect(recipes[0].ingredients.map((i) => i.name)).toEqual(['a', 'b'])
    expect(recipes[0].steps).toEqual(['First.', 'Second.'])
  })
})

describe('exportSingle / exportCollection', () => {
  const recipe = {
    title: 'Fish & Chips',
    description: 'Crisp.',
    servings: 2,
    image_path: '',
    notes: 'Serve hot.',
    ingredients: [{ amount: '1', unit: 'lb', name: 'fish' }],
    steps: ['Fry.'],
  }

  it('exports a single recipe as a pretty bare object', () => {
    const text = exportSingle(recipe)
    expect(text).toBe(JSON.stringify(JSON.parse(text), null, 2))
    const parsed = JSON.parse(text)
    expect(Object.keys(parsed)).toEqual([
      'title',
      'description',
      'servings',
      'image_path',
      'notes',
      'ingredients',
      'steps',
    ])
    expect(parsed.image_path).toBeNull()
  })

  it('exports a collection as {"recipes": [...]}', () => {
    const parsed = JSON.parse(exportCollection([recipe, recipe]))
    expect(Object.keys(parsed)).toEqual(['recipes'])
    expect(parsed.recipes).toHaveLength(2)
  })

  it('round-trips through parseRecipes', () => {
    const back = parseRecipes(exportSingle(recipe))
    expect(back[0].title).toBe('Fish & Chips')
    expect(back[0].image_path).toBe('')
    const backAll = parseRecipes(exportCollection([recipe]))
    expect(backAll).toHaveLength(1)
  })

  it('writes empty arrays on one line', () => {
    const text = exportSingle({ ...recipe, ingredients: [], steps: [] })
    expect(text).toContain('"ingredients": []')
    expect(text).toContain('"steps": []')
  })
})

describe('defaultFileName', () => {
  it('sanitises unsafe characters and adds .json', () => {
    expect(defaultFileName('Fish & Chips')).toBe('Fish _ Chips.json')
    expect(defaultFileName('a/b')).toBe('a_b.json')
  })

  it('falls back to recipe.json for an empty result', () => {
    expect(defaultFileName('')).toBe('recipe.json')
    expect(defaultFileName('   ')).toBe('recipe.json')
  })

  it('sanitises punctuation to underscores (not empty)', () => {
    expect(defaultFileName('!!!')).toBe('___.json')
  })
})
