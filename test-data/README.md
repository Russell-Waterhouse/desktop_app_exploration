# test-data

Shared fixtures for manually QA-ing network JSON import in every
app in this repo, so all stacks download the same data.

## Files

- `recipes.json` — a collection of 3 recipes, matching the existing
  seed data: Banana Bread, Tomato Basil Pasta, and Chicken Stir Fry
  (19 ingredients and 13 steps in total).

  Shape: `{"recipes": [...]}`. Each recipe has `title`,
  `description`, `servings`, `prep_minutes`, `cook_minutes`,
  `image_path` (null when there is no image), `notes`,
  `ingredients` (array of `amount`, `unit`, `name` objects, in order),
  and `steps` (array of strings, in order). Amounts are strings so
  fractions like `"1/2"` survive as written.

## Running the server

From the repo root, using only the Python standard library
(no server code to maintain):

```
python3 -m http.server 8000 --directory test-data --bind 127.0.0.1
```

Then point an app at:

```
http://localhost:8000/recipes.json
```

Stop it with Ctrl-C when you are done. It serves static files only:
it cannot simulate slow responses, 500 errors, auth, or HTTPS.
