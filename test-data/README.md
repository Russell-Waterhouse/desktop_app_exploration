# test-data

Shared fixtures for manually QA-ing network JSON import in every
app in this repo, so all stacks download the same data.

## Files

- `recipes.json` — a collection of 3 recipes, deliberately different
  from the apps' seed data (Banana Bread, Tomato Basil Pasta, Chicken
  Stir Fry), so an import is easy to spot: Fried Chicken, Lasagna,
  and Butter Tarts (28 ingredients and 15 steps in total).

  Shape: `{"recipes": [...]}`. Each recipe has `title`,
  `description`, `servings`, `image_path` (null when there is no image), `notes`,
  `ingredients` (array of `amount`, `unit`, `name` objects, in order),
  and `steps` (array of strings, in order). Amounts are strings so
  fractions like `"1/2"` survive as written.

- `run_server.sh` — starts a local server for this directory in the
  background (Python standard library only, no server code to
  maintain). It records the server's PID in `.server.pid` and its
  output in `server.log`, both ignored by git.
- `kill_server.sh` — stops the server started by `run_server.sh`,
  using only that PID file, so it does not kill any other server.

## Running the server

From this directory:

```
./run_server.sh
./kill_server.sh
```

If the executable bit was lost on checkout, use `bash run_server.sh`
and `bash kill_server.sh` instead, or `chmod +x run_server.sh
kill_server.sh` first.

The server listens only on localhost, port 8000 by default
(`./run_server.sh 8080` or `PORT=8080 ./run_server.sh` to change it).
Then point an app at:

```
http://localhost:8000/recipes.json
```

Or run the server directly, without the scripts:

```
python3 -m http.server 8000 --directory test-data --bind 127.0.0.1
```

It serves static files only: it cannot simulate slow responses,
500 errors, auth, or HTTPS.
