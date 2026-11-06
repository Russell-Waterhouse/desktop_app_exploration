import { describe, expect, it } from 'vitest'
import { titleMatchesSearch, filterRecipes } from '../../src/shared/search.js'
import { SEED_RECIPES } from '../../src/shared/seed.js'

describe('titleMatchesSearch', () => {
  it('empty query matches everything', () => {
    expect(titleMatchesSearch('Banana Bread', '')).toBe(true)
  })

  it('matches a case-insensitive substring of the title', () => {
    expect(titleMatchesSearch('Banana Bread', 'banana')).toBe(true)
    expect(titleMatchesSearch('Banana Bread', 'BANANA')).toBe(true)
    expect(titleMatchesSearch('Banana Bread', 'nan')).toBe(true)
  })

  it('does not match text outside the title', () => {
    expect(titleMatchesSearch('Banana Bread', 'ripe')).toBe(false)
  })

  it('does not match when there is no substring', () => {
    expect(titleMatchesSearch('Banana Bread', 'pasta')).toBe(false)
  })

  it('does not trim the query', () => {
    expect(titleMatchesSearch('Banana Bread', ' banana')).toBe(false)
  })
})

describe('filterRecipes', () => {
  it('empty query returns all recipes', () => {
    expect(filterRecipes(SEED_RECIPES, '')).toHaveLength(7)
  })

  it('filters by title substring', () => {
    expect(filterRecipes(SEED_RECIPES, 'pasta').map((r) => r.title)).toEqual([
      'Tomato Basil Pasta',
    ])
  })

  it('a query with no match returns an empty list', () => {
    expect(filterRecipes(SEED_RECIPES, 'zzz')).toHaveLength(0)
  })
})
