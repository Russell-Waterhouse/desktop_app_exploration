# desktop_app_exploration — Plan

## Purpose

This repo is for choosing a desktop application development stack.

## Languages to be considered

- C
- C++
- Rust
- Odin
- Zig

## Frameworks to consider

- Rust:
  - Egui / Eframe
  - Iced
- C / C++:
  - Dear ImGui
  - GTK4
- Odin:
  - Raylib + Raygui
  - microui
- Zig:
  - DVUI
- Backends underneath, not counted as UI frameworks:
  - SDL
  - Sokol
  - Raylib

Excluded: Qt (tried in the past, found buggy on Linux) and Slint (licensing).

## Targets

- Latest Fedora Linux to start
- Windows second
- Mac much later

Mobile is explicitly not considered.

## Reasoning

Most applications today are built as web applications, and we can do better.

## The test

Build the same application in all these languages/tech stacks and see what works well and what doesn't.

## The application

Recipe manager. The same app will be built in each language/tech stack.

### Core features

- Recipe list: thumbnail, title, search by title
- Recipe detail: photo, description, ingredients, numbered steps, notes
- Add, edit, and delete recipes

### How it covers the criteria

- Displaying text: titles, descriptions, ingredients, steps, notes, search
- Displaying images: recipe photos as list thumbnails and detail images, imported from a file or downloaded from a URL
- Buttons: add, edit, delete, import, export, search
- Animations: list/detail transitions, image loading state
- Making a network call: import a recipe as JSON from a URL, and download a recipe image from a URL, both asynchronously with loading and error states and without blocking the UI
- Interacting with disk as raw files: import and export recipes as JSON files (single recipe and collection), import an image file from disk, store recipe images as files on disk
- Interacting with disk through SQLite: all recipe data lives in SQLite — recipes, ingredients, and steps; image files are referenced by path from the database
- Detecting and parsing text in multiple encodings: imported recipe JSON may be UTF-8 (with or without BOM), UTF-16LE or UTF-16BE (with BOM), Windows-1252, or Shift_JIS; the app detects the encoding, parses the JSON, and stores equivalent UTF-8 in SQLite
- Rendering complex text: recipe titles and descriptions in Arabic, emoji, Devanagari, and Simplified Chinese

### Data model

- Recipe: title, description, servings, image path
- Ingredient: recipe, position, amount, unit, name
- Step: recipe, position, text

### Out of scope for this test

- User accounts and cloud sync
- Meal planning and shopping lists
- Recipe parsing from arbitrary web pages (network import is JSON only)
- Audio, video, and timers
