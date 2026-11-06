import { useCallback, useEffect, useState } from 'react'
import { filterRecipes } from '../shared/search.js'
import RecipeForm from './RecipeForm.jsx'

const DEFAULT_IMPORT_URL = 'http://localhost:8000/recipes.json'

function formatIngredient(ing) {
  if (ing.unit) {
    return `${ing.amount} ${ing.unit} ${ing.name}`
  }
  return `${ing.amount} ${ing.name}`
}

export default function App() {
  const [recipes, setRecipes] = useState([])
  const [selectedId, setSelectedId] = useState(-1)
  const [query, setQuery] = useState('')
  const [url, setUrl] = useState(DEFAULT_IMPORT_URL)
  const [importing, setImporting] = useState(false)
  const [status, setStatus] = useState({ text: '', isError: false })
  const [form, setForm] = useState(null) // null | { mode: 'add' } | { mode: 'edit', recipe }
  const [deleteTarget, setDeleteTarget] = useState(null)
  const [imageState, setImageState] = useState({ kind: 'none' }) // none | loading | ready | error
  const [thumbState, setThumbState] = useState({}) // recipe id -> { kind, dataUrl }

  const filtered = filterRecipes(recipes, query)
  const selected = recipes.find((r) => r.id === selectedId) ?? null

  const load = useCallback(async (selectId) => {
    const result = await window.recipeAPI.list()
    if (result.error) {
      setStatus({ text: result.error, isError: true })
      return []
    }
    setRecipes(result.recipes)
    if (selectId !== undefined) {
      setSelectedId(selectId)
    }
    return result.recipes
  }, [])

  useEffect(() => {
    load().then((loaded) => {
      if (loaded.length > 0) {
        setSelectedId(loaded[0].id)
      }
    })
  }, [load])

  // When the search filter changes, select the first match
  // (or clear the detail when nothing matches), like the
  // other stacks.
  useEffect(() => {
    if (filtered.length > 0) {
      setSelectedId(filtered[0].id)
    } else {
      setSelectedId(-1)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query])

  // Detail image: show a spinner while the main process
  // reads and decodes it, the photo when ready, and a status
  // line when it fails. No image path means no image area.
  useEffect(() => {
    if (!selected || !selected.image_path) {
      setImageState({ kind: 'none' })
      return
    }
    let cancelled = false
    setImageState({ kind: 'loading' })
    window.recipeAPI.readImage(selected.image_path).then((result) => {
      if (cancelled) {
        return
      }
      if (result.ok) {
        setImageState({ kind: 'ready', dataUrl: result.dataUrl })
      } else {
        setImageState({ kind: 'error', text: result.error })
      }
    })
    return () => {
      cancelled = true
    }
  }, [selected?.id, selected?.image_path])

  // List thumbnails load the same way, per row, lazily.
  useEffect(() => {
    for (const recipe of filtered) {
      if (!recipe.image_path || thumbState[recipe.id]) {
        continue
      }
      setThumbState((prev) => ({ ...prev, [recipe.id]: { kind: 'loading' } }))
      window.recipeAPI.readImage(recipe.image_path).then((result) => {
        setThumbState((prev) => ({
          ...prev,
          [recipe.id]: result.ok
            ? { kind: 'ready', dataUrl: result.dataUrl }
            : { kind: 'error' },
        }))
      })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtered])

  async function handleImportUrl() {
    setImporting(true)
    setStatus({ text: 'Importing…', isError: false })
    const result = await window.recipeAPI.importUrl(url)
    setImporting(false)
    if (result.error) {
      setStatus({ text: result.error, isError: true })
      return
    }
    const loaded = await load(result.firstId >= 0 ? result.firstId : undefined)
    if (loaded.length > 0 && result.firstId < 0) {
      setSelectedId(loaded[0].id)
    }
    setStatus({ text: result.message, isError: false })
  }

  async function handleImportFile() {
    setImporting(true)
    setStatus({ text: 'Importing…', isError: false })
    const result = await window.recipeAPI.importFile()
    setImporting(false)
    if (result.cancelled) {
      setStatus({ text: '', isError: false })
      return
    }
    if (result.error) {
      setStatus({ text: result.error, isError: true })
      return
    }
    const loaded = await load(result.firstId >= 0 ? result.firstId : undefined)
    if (loaded.length > 0 && result.firstId < 0) {
      setSelectedId(loaded[0].id)
    }
    setStatus({ text: result.message, isError: false })
  }

  async function handleExportSingle() {
    if (!selected) {
      setStatus({ text: 'No recipe selected.', isError: true })
      return
    }
    const result = await window.recipeAPI.exportSingle(selected.id)
    if (result.cancelled) {
      return
    }
    if (result.error) {
      setStatus({ text: result.error, isError: true })
      return
    }
    setStatus({ text: result.message, isError: false })
  }

  async function handleExportAll() {
    const result = await window.recipeAPI.exportAll()
    if (result.cancelled) {
      return
    }
    if (result.error) {
      setStatus({ text: result.error, isError: true })
      return
    }
    setStatus({ text: result.message, isError: false })
  }

  async function handleFormSave(recipe) {
    if (form.mode === 'add') {
      const result = await window.recipeAPI.add(recipe)
      if (result.error) {
        return result.error
      }
      await load(result.id)
      setForm(null)
      return ''
    }
    const result = await window.recipeAPI.update(recipe)
    if (result.error) {
      return result.error
    }
    await load(recipe.id)
    setForm(null)
    return ''
  }

  async function handleDeleteConfirm() {
    const result = await window.recipeAPI.delete(deleteTarget.id)
    setDeleteTarget(null)
    if (result.error) {
      setStatus({ text: result.error, isError: true })
      return
    }
    const loaded = await load()
    if (loaded.length > 0) {
      setSelectedId(loaded[0].id)
    } else {
      setSelectedId(-1)
    }
  }

  return (
    <div className="root">
      <div className="left">
        <input
          data-testid="search"
          className="search"
          type="search"
          placeholder="Type to filter recipes…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <button data-testid="add-button" onClick={() => setForm({ mode: 'add' })}>
          Add recipe
        </button>
        <div className="list" data-testid="recipe-list">
          {filtered.map((recipe) => (
            <div
              key={recipe.id}
              data-testid={`recipe-row-${recipe.id}`}
              className={`row${recipe.id === selectedId ? ' selected' : ''}`}
              onClick={() => setSelectedId(recipe.id)}
            >
              <span className="thumb">
                {recipe.image_path && thumbState[recipe.id]?.kind === 'ready' ? (
                  <img src={thumbState[recipe.id].dataUrl} alt="" />
                ) : recipe.image_path &&
                  thumbState[recipe.id]?.kind === 'loading' ? (
                  <span className="spinner small" aria-label="Loading image…" />
                ) : (
                  <span className="thumb-blank" />
                )}
              </span>
              <span className="row-title">{recipe.title}</span>
            </div>
          ))}
        </div>
        <input
          data-testid="url-entry"
          className="url-entry"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
        />
        <button
          data-testid="import-url-button"
          onClick={handleImportUrl}
          disabled={importing}
        >
          Import from URL
        </button>
        <button
          data-testid="import-file-button"
          onClick={handleImportFile}
          disabled={importing}
        >
          Import from file…
        </button>
        <div className="export-row">
          <button data-testid="export-single-button" onClick={handleExportSingle}>
            Export recipe…
          </button>
          <button data-testid="export-all-button" onClick={handleExportAll}>
            Export all…
          </button>
        </div>
        {importing && (
          <div className="importing">
            <span className="spinner" aria-label="Importing…" /> Importing…
          </div>
        )}
        <div
          data-testid="status"
          className={`status${status.isError ? ' error' : ''}`}
        >
          {status.text}
        </div>
      </div>
      <div className="detail-scroll">
        {selected ? (
          <div className="detail" key={selected.id} data-testid="detail">
            {imageState.kind === 'loading' && (
              <div className="image-loading">
                <span className="spinner" aria-label="Loading image…" /> Loading image…
              </div>
            )}
            {imageState.kind === 'error' && (
              <div className="status error">{imageState.text}</div>
            )}
            {imageState.kind === 'ready' && (
              <img
                className="detail-photo"
                src={imageState.dataUrl}
                alt={selected.title}
                data-testid="detail-photo"
              />
            )}
            <h1 className="detail-title" data-testid="detail-title">
              {selected.title}
            </h1>
            <p className="detail-description" data-testid="detail-description">
              {selected.description}
            </p>
            <p className="detail-servings" data-testid="detail-servings">
              Servings: {selected.servings}
            </p>
            <h2>Ingredients</h2>
            <ul className="detail-ingredients">
              {selected.ingredients.map((ing, i) => (
                <li key={i}>{formatIngredient(ing)}</li>
              ))}
            </ul>
            <h2>Steps</h2>
            <ol className="detail-steps">
              {selected.steps.map((step, i) => (
                <li key={i}>{step}</li>
              ))}
            </ol>
            <p className="detail-notes" data-testid="detail-notes">
              {selected.notes}
            </p>
            <button
              data-testid="edit-button"
              onClick={() => setForm({ mode: 'edit', recipe: selected })}
            >
              Edit recipe
            </button>
            <button
              data-testid="delete-button"
              onClick={() => setDeleteTarget(selected)}
            >
              Delete recipe
            </button>
          </div>
        ) : (
          <div className="detail empty" data-testid="detail">
            {recipes.length === 0 ? 'No recipes yet.' : ''}
          </div>
        )}
      </div>
      {form && (
        <RecipeForm
          initial={form.mode === 'edit' ? form.recipe : null}
          title={form.mode === 'edit' ? 'Edit Recipe' : 'Add Recipe'}
          onSave={handleFormSave}
          onCancel={() => setForm(null)}
        />
      )}
      {deleteTarget && (
        <div className="modal-overlay">
          <div className="modal" data-testid="delete-dialog">
            <p>
              Delete &ldquo;{deleteTarget.title}&rdquo;? This cannot be undone.
            </p>
            <div className="modal-buttons">
              <button data-testid="delete-confirm" onClick={handleDeleteConfirm}>
                Delete
              </button>
              <button onClick={() => setDeleteTarget(null)}>Cancel</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
