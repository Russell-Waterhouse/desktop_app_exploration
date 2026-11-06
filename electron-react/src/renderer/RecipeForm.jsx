import { useState } from 'react'

// Add/edit recipe form, as a modal over the list/detail view
// (like the other stacks' modal form windows). Title is
// required; servings is a 1..100 number; ingredient rows are
// amount/unit/name and step rows are single lines, both
// dynamic with Remove buttons. Description and notes are
// multiline textareas. The form has a "Choose image…" button:
// choosing copies the file into images/ and stores the
// relative path.
//
// Text input behaviour comes from Chromium itself, the same
// engine as a browser text field: multiline editing, drag
// select, Ctrl+C/Ctrl+V, and Ctrl+Z undo / Ctrl+Shift+Z and
// Ctrl+Y redo all work natively in the inputs and textareas
// below (verified in the real app; see the UI tests). There
// is no custom undo code, unlike the GTK stacks, whose
// entries and text views have no built-in undo.

const EMPTY_INGREDIENT = { amount: '', unit: '', name: '' }

export default function RecipeForm({ initial, title, onSave, onCancel }) {
  const [formTitle, setFormTitle] = useState(initial?.title ?? '')
  const [description, setDescription] = useState(initial?.description ?? '')
  const [servings, setServings] = useState(initial?.servings ?? 1)
  const [notes, setNotes] = useState(initial?.notes ?? '')
  const [imagePath, setImagePath] = useState(initial?.image_path ?? '')
  const [ingredients, setIngredients] = useState(
    initial?.ingredients?.length > 0
      ? initial.ingredients.map((i) => ({ ...i }))
      : [{ ...EMPTY_INGREDIENT }],
  )
  const [steps, setSteps] = useState(
    initial?.steps?.length > 0 ? [...initial.steps] : [''],
  )
  const [error, setError] = useState('')
  const [imageError, setImageError] = useState('')

  async function handleChooseImage() {
    const result = await window.recipeAPI.chooseImage()
    if (result.cancelled) {
      return
    }
    if (result.error) {
      setImageError(result.error)
      return
    }
    setImagePath(result.relPath)
    setImageError('')
  }

  async function handleSave() {
    if (formTitle.trim() === '') {
      setError('Title is required.')
      return
    }
    const parsedServings = parseInt(servings, 10)
    const recipe = {
      ...(initial?.id !== undefined ? { id: initial.id } : {}),
      title: formTitle.trim(),
      description: description.trim(),
      servings: Number.isNaN(parsedServings) ? 1 : Math.min(100, Math.max(1, parsedServings)),
      image_path: imagePath,
      notes: notes.trim(),
      ingredients: ingredients
        .map((ing) => ({
          amount: ing.amount.trim(),
          unit: ing.unit.trim(),
          name: ing.name.trim(),
        }))
        .filter((ing) => ing.amount !== '' || ing.unit !== '' || ing.name !== ''),
      steps: steps.map((s) => s.trim()).filter((s) => s !== ''),
    }
    const saveError = await onSave(recipe)
    if (saveError) {
      setError(saveError)
    }
  }

  function updateIngredient(index, field, value) {
    setIngredients((prev) =>
      prev.map((ing, i) => (i === index ? { ...ing, [field]: value } : ing)),
    )
  }

  function removeIngredient(index) {
    setIngredients((prev) => prev.filter((_, i) => i !== index))
  }

  function updateStep(index, value) {
    setSteps((prev) => prev.map((s, i) => (i === index ? value : s)))
  }

  function removeStep(index) {
    setSteps((prev) => prev.filter((_, i) => i !== index))
  }

  return (
    <div className="modal-overlay">
      <div className="modal form-modal" data-testid="recipe-form">
        <h2>{title}</h2>
        <label>
          Title:
          <input
            data-testid="form-title"
            value={formTitle}
            onChange={(e) => setFormTitle(e.target.value)}
          />
        </label>
        <label>
          Description:
          <textarea
            data-testid="form-description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={4}
          />
        </label>
        <label>
          Servings:
          <input
            data-testid="form-servings"
            type="number"
            min={1}
            max={100}
            value={servings}
            onChange={(e) => setServings(e.target.value)}
          />
        </label>
        <label>Ingredients:</label>
        {ingredients.map((ing, i) => (
          <div key={i} className="form-row">
            <input
              data-testid={`form-ingredient-amount-${i}`}
              placeholder="Amount"
              value={ing.amount}
              onChange={(e) => updateIngredient(i, 'amount', e.target.value)}
            />
            <input
              data-testid={`form-ingredient-unit-${i}`}
              placeholder="Unit"
              value={ing.unit}
              onChange={(e) => updateIngredient(i, 'unit', e.target.value)}
            />
            <input
              data-testid={`form-ingredient-name-${i}`}
              placeholder="Name"
              value={ing.name}
              onChange={(e) => updateIngredient(i, 'name', e.target.value)}
            />
            <button type="button" onClick={() => removeIngredient(i)}>
              Remove
            </button>
          </div>
        ))}
        <button
          type="button"
          onClick={() => setIngredients((prev) => [...prev, { ...EMPTY_INGREDIENT }])}
        >
          Add ingredient
        </button>
        <label>Steps:</label>
        {steps.map((step, i) => (
          <div key={i} className="form-row">
            <input
              data-testid={`form-step-${i}`}
              value={step}
              onChange={(e) => updateStep(i, e.target.value)}
            />
            <button type="button" onClick={() => removeStep(i)}>
              Remove
            </button>
          </div>
        ))}
        <button type="button" onClick={() => setSteps((prev) => [...prev, ''])}>
          Add step
        </button>
        <label>
          Notes:
          <textarea
            data-testid="form-notes"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={4}
          />
        </label>
        <button
          type="button"
          data-testid="form-choose-image"
          onClick={handleChooseImage}
        >
          Choose image…
        </button>
        <p data-testid="form-image-label">
          {imagePath ? imagePath.split('/').pop() : 'No image'}
        </p>
        {imageError && <p className="status error">{imageError}</p>}
        {error && (
          <p className="status error" data-testid="form-error">
            {error}
          </p>
        )}
        <div className="modal-buttons">
          <button data-testid="form-save" onClick={handleSave}>
            Save
          </button>
          <button data-testid="form-cancel" onClick={onCancel}>
            Cancel
          </button>
        </div>
      </div>
    </div>
  )
}
