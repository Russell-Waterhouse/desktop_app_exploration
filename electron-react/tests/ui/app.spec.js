// UI tests for electron-react, driven through Playwright's
// Electron support: they launch the real built app (npm run
// build first) and drive its real window. Each test runs the
// app in its own temporary working directory, so it seeds a
// fresh recipes.db there; the real recipes.db in the working
// directory is never opened.
//
// Run from electron-react/ after building:
//   DISPLAY=:99 npx playwright test
// (Xvfb provides the display; the app also needs
// --no-sandbox when running as root in this VM.)
// The URL-import test needs the test-data server running:
//   ../test-data/run_server.sh   (serves localhost:8000)

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { _electron, test, expect } from '@playwright/test'

const APP_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..')

let electronApp
let window
let workDir

test.beforeEach(async () => {
  workDir = mkdtempSync(join(tmpdir(), 'electron-react-ui-test-'))
  electronApp = await _electron.launch({
    args: [APP_DIR, '--no-sandbox', '--disable-gpu'],
    cwd: workDir,
  })
  window = await electronApp.firstWindow()
  await window.waitForSelector('[data-testid="recipe-list"]')
  await expect(window.getByTestId('detail-title')).toHaveText('Banana Bread')
})

test.afterEach(async () => {
  await electronApp.close()
  rmSync(workDir, { recursive: true, force: true })
})

test('list click shows detail', async () => {
  await window.getByText('Tomato Basil Pasta').click()
  await expect(window.getByTestId('detail-title')).toHaveText('Tomato Basil Pasta')
  await expect(window.getByTestId('detail-description')).toHaveText(
    'A quick weeknight pasta with fresh tomatoes and basil.',
  )
  await expect(window.getByTestId('detail-servings')).toHaveText('Servings: 4')
})

test('search filters list', async () => {
  await window.getByTestId('search').fill('pasta')
  await expect(window.getByTestId('recipe-list')).toContainText('Tomato Basil Pasta')
  await expect(window.getByTestId('recipe-list')).not.toContainText('Banana Bread')
  await expect(window.getByTestId('detail-title')).toHaveText('Tomato Basil Pasta')
})

test('search with no match clears detail', async () => {
  await window.getByTestId('search').fill('zzz-no-such-recipe')
  await expect(window.getByTestId('recipe-list')).not.toContainText('Banana Bread')
  await expect(window.getByTestId('detail')).toBeEmpty()
})

test('add via form', async () => {
  await window.getByTestId('add-button').click()
  await window.getByTestId('form-title').fill('Test Soup')
  await window.getByTestId('form-description').fill('A test soup.\nSecond line.')
  await window.getByTestId('form-servings').fill('2')
  await window.getByTestId('form-ingredient-amount-0').fill('1')
  await window.getByTestId('form-ingredient-unit-0').fill('cup')
  await window.getByTestId('form-ingredient-name-0').fill('water')
  await window.getByTestId('form-step-0').fill('Boil the water.')
  await window.getByTestId('form-notes').fill('Test notes.')
  await window.getByTestId('form-save').click()
  await expect(window.getByTestId('recipe-list')).toContainText('Test Soup')
  await expect(window.getByTestId('detail-title')).toHaveText('Test Soup')
  await expect(window.getByTestId('detail-description')).toHaveText(
    'A test soup.\nSecond line.',
  )
})

test('add rejects empty title', async () => {
  await window.getByTestId('add-button').click()
  await window.getByTestId('form-save').click()
  await expect(window.getByTestId('form-error')).toHaveText('Title is required.')
  await expect(window.getByTestId('recipe-form')).toBeVisible()
})

test('edit changes title', async () => {
  await window.getByTestId('edit-button').click()
  await window.getByTestId('form-title').fill('Banana Bread Deluxe')
  await window.getByTestId('form-save').click()
  await expect(window.getByTestId('recipe-list')).toContainText('Banana Bread Deluxe')
  await expect(window.getByTestId('detail-title')).toHaveText('Banana Bread Deluxe')
})

test('delete removes it', async () => {
  await window.getByTestId('delete-button').click()
  await expect(window.getByTestId('delete-dialog')).toContainText('Banana Bread')
  await window.getByTestId('delete-confirm').click()
  await expect(window.getByTestId('recipe-list')).not.toContainText('Banana Bread')
  await expect(window.getByTestId('detail-title')).toHaveText('Tomato Basil Pasta')
})

test('complex-text input in Arabic, Devanagari, Simplified Chinese, and emoji', async () => {
  await window.getByTestId('add-button').click()
  await window.getByTestId('form-title').fill('شوربة العدس 🍲')
  await window.getByTestId('form-description').fill('दाल का सूप और 番茄炒蛋 🥞')
  await window.getByTestId('form-step-0').fill('Mix everything 🫐.')
  await window.getByTestId('form-save').click()
  await expect(window.getByTestId('recipe-list')).toContainText('شوربة العدس 🍲')
  await expect(window.getByTestId('detail-title')).toHaveText('شوربة العدس 🍲')
  await expect(window.getByTestId('detail-description')).toHaveText(
    'दाल का सूप और 番茄炒蛋 🥞',
  )
})

test('import from URL', async () => {
  await window.getByTestId('import-url-button').click()
  await expect(window.getByTestId('status')).toHaveText('Imported 3 recipes.')
  await expect(window.getByTestId('recipe-list')).toContainText('Fried Chicken')
  await expect(window.getByTestId('detail-title')).toHaveText('Fried Chicken')
})

test('import from file', async () => {
  const singlePath = join(APP_DIR, '..', 'test-data', 'recipe-single.json')
  await electronApp.evaluate(async ({ dialog }, filePath) => {
    dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [filePath] })
  }, singlePath)
  await window.getByTestId('import-file-button').click()
  await expect(window.getByTestId('status')).toHaveText('Imported 1 recipe.')
  await expect(window.getByTestId('recipe-list')).toContainText('Mushroom Risotto')
  await expect(window.getByTestId('detail-title')).toHaveText('Mushroom Risotto')
})

test('export all writes a {"recipes": [...]} file', async () => {
  const outPath = join(workDir, 'recipes.json')
  await electronApp.evaluate(async ({ dialog }, filePath) => {
    dialog.showSaveDialog = async () => ({ canceled: false, filePath })
  }, outPath)
  await window.getByTestId('export-all-button').click()
  await expect(window.getByTestId('status')).toContainText('Exported all recipes to')
  const parsed = JSON.parse(readFileSync(outPath, 'utf-8'))
  expect(parsed.recipes).toHaveLength(7)
  expect(parsed.recipes[0].title).toBe('Banana Bread')
})

test('choose image in the form shows the photo', async () => {
  const png = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    'base64',
  )
  const imgPath = join(workDir, 'photo.png')
  writeFileSync(imgPath, png)
  await electronApp.evaluate(async ({ dialog }, filePath) => {
    dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [filePath] })
  }, imgPath)
  await window.getByTestId('add-button').click()
  await window.getByTestId('form-title').fill('Photo Recipe')
  await window.getByTestId('form-choose-image').click()
  await expect(window.getByTestId('form-image-label')).toHaveText('photo.png')
  await window.getByTestId('form-save').click()
  await expect(window.getByTestId('detail-photo')).toBeVisible()
})

test('text input undo/redo in the form (Chromium native)', async () => {
  await window.getByTestId('add-button').click()
  const title = window.getByTestId('form-title')
  await title.fill('Hello')
  await title.press('Control+Z')
  await expect(title).toHaveValue('')
  await title.press('Control+Shift+Z')
  await expect(title).toHaveValue('Hello')
  await window.getByTestId('form-cancel').click()
})
