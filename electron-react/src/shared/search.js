// List filter, mirroring odin-gtk's title_matches_search:
// case-insensitive substring match on the recipe TITLE only;
// an empty query matches everything; the query is NOT trimmed.

export function titleMatchesSearch(title, query) {
  if (query === '') {
    return true
  }
  return title.toLowerCase().includes(query.toLowerCase())
}

export function filterRecipes(recipes, query) {
  return recipes.filter((r) => titleMatchesSearch(r.title, query))
}
