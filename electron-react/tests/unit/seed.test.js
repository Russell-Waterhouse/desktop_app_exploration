import { describe, expect, it } from 'vitest'
import { SEED_RECIPES } from '../../src/shared/seed.js'

describe('seed data', () => {
  it('has 7 recipes, 27 ingredients, 21 steps', () => {
    expect(SEED_RECIPES).toHaveLength(7)
    expect(SEED_RECIPES.reduce((n, r) => n + r.ingredients.length, 0)).toBe(27)
    expect(SEED_RECIPES.reduce((n, r) => n + r.steps.length, 0)).toBe(21)
  })

  it('starts with the same 3 recipes in the same order', () => {
    expect(SEED_RECIPES.slice(0, 3).map((r) => r.title)).toEqual([
      'Banana Bread',
      'Tomato Basil Pasta',
      'Chicken Stir Fry',
    ])
    expect(SEED_RECIPES[0].servings).toBe(8)
    expect(SEED_RECIPES[0].ingredients).toHaveLength(7)
    expect(SEED_RECIPES[0].steps).toHaveLength(5)
    expect(SEED_RECIPES[1].servings).toBe(4)
    expect(SEED_RECIPES[2].servings).toBe(4)
  })

  it('includes the 4 complex-text probe recipes', () => {
    expect(SEED_RECIPES.slice(3).map((r) => r.title)).toEqual([
      'كبسة الدجاج',
      'पालक पनीर',
      '番茄炒蛋',
      '🥞 Blueberry Pancakes 🫐',
    ])
  })

  it('has no image paths in the seed', () => {
    for (const recipe of SEED_RECIPES) {
      expect(recipe.image_path).toBe('')
    }
  })
})
