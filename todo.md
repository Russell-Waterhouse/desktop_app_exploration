# todo

The same recipe-manager test app in each stack, from `README.md` and
`plan.md`. A checked box means that item is done in that project;
an unchecked box means it is still to do in that project.

The checklist is the same for every project so the stacks can be
compared like for like. The shared network-import fixture
(`test-data/recipes.json`) already exists, but no app imports it yet.

Every stack now has a Fedora install script, but none of them
has been tested on Fedora yet.

## Rust Egui (`rust-egui/`)

- [X] install script for Ubuntu
- [X] install script for Fedora
- [X] hello world, open window
- [X] recipe view with hard-coded data
- [X] recipe view with SQLite integration
- [X] add recipe
- [X] edit recipe
- [X] delete recipe
- [X] recipe list: title, search by title
- [X] recipe detail: description, servings, ingredients, numbered steps, notes
- [X] display images (list thumbnails and detail photo)
- [X] import image from a file and store image files on disk
- [X] display animations: list/detail transitions
- [X] display animations: image loading state
- [ ] network request import: recipe JSON from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] network request import: recipe image from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] raw-file import: recipes as JSON, single recipe
- [ ] raw-file import: recipes as JSON, collection
- [ ] raw-file export: recipes as JSON, single recipe
- [ ] raw-file export: recipes as JSON, collection
- [ ] CPU profiling
- [ ] memory profiling
- [ ] compile time profiling
- [ ] Windows build
- [ ] macOS build

## Rust Iced (`rust-iced/`)

- [X] install script for Ubuntu
- [X] install script for Fedora
- [X] hello world, open window
- [X] recipe view with hard-coded data
- [X] recipe view with SQLite integration
- [X] add recipe
- [X] edit recipe
- [X] delete recipe
- [X] recipe list: title, search by title
- [X] recipe detail: description, servings, ingredients, numbered steps, notes
- [X] display images (list thumbnails and detail photo)
- [X] import image from a file and store image files on disk
- [X] display animations: list/detail transitions
- [X] display animations: image loading state
- [ ] network request import: recipe JSON from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] network request import: recipe image from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] raw-file import: recipes as JSON, single recipe
- [ ] raw-file import: recipes as JSON, collection
- [ ] raw-file export: recipes as JSON, single recipe
- [ ] raw-file export: recipes as JSON, collection
- [ ] CPU profiling
- [ ] memory profiling
- [ ] compile time profiling
- [ ] Windows build
- [ ] macOS build

## C/C++ Dear ImGui (`cpp-imgui/`)

- [X] install script for Ubuntu
- [X] install script for Fedora
- [X] hello world, open window
- [X] recipe view with hard-coded data
- [X] recipe view with SQLite integration
- [X] add recipe
- [X] edit recipe
- [X] delete recipe
- [X] recipe list: title, search by title
- [X] recipe detail: description, servings, ingredients, numbered steps, notes
- [X] display images (list thumbnails and detail photo)
- [X] import image from a file and store image files on disk
- [X] display animations: list/detail transitions
- [X] display animations: image loading state
- [ ] network request import: recipe JSON from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] network request import: recipe image from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] raw-file import: recipes as JSON, single recipe
- [ ] raw-file import: recipes as JSON, collection
- [ ] raw-file export: recipes as JSON, single recipe
- [ ] raw-file export: recipes as JSON, collection
- [ ] CPU profiling
- [ ] memory profiling
- [ ] compile time profiling
- [ ] Windows build
- [ ] macOS build

## C/C++ GTK4 (`cpp-gtk4/`)

- [X] install script for Ubuntu
- [X] install script for Fedora
- [X] hello world, open window
- [X] recipe view with hard-coded data
- [X] recipe view with SQLite integration
- [X] add recipe
- [X] edit recipe
- [X] delete recipe
- [X] recipe list: title, search by title
- [X] recipe detail: description, servings, ingredients, numbered steps, notes
- [X] display images (list thumbnails and detail photo)
- [X] import image from a file and store image files on disk
- [X] display animations: list/detail transitions
- [X] display animations: image loading state
- [ ] network request import: recipe JSON from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] network request import: recipe image from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] raw-file import: recipes as JSON, single recipe
- [ ] raw-file import: recipes as JSON, collection
- [ ] raw-file export: recipes as JSON, single recipe
- [ ] raw-file export: recipes as JSON, collection
- [ ] CPU profiling
- [ ] memory profiling
- [ ] compile time profiling
- [ ] Windows build
- [ ] macOS build

## Odin Raylib + Raygui (`odin-raygui/`)

- [X] install script for Ubuntu
- [X] install script for Fedora
- [X] hello world, open window
- [X] recipe view with hard-coded data
- [X] recipe view with SQLite integration
- [X] add recipe
- [X] edit recipe
- [X] delete recipe
- [X] recipe list: title, search by title
- [X] recipe detail: description, servings, ingredients, numbered steps, notes
- [X] display images (list thumbnails and detail photo)
- [X] import image from a file and store image files on disk
- [X] display animations: list/detail transitions
- [X] display animations: image loading state
- [ ] network request import: recipe JSON from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] network request import: recipe image from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] raw-file import: recipes as JSON, single recipe
- [ ] raw-file import: recipes as JSON, collection
- [ ] raw-file export: recipes as JSON, single recipe
- [ ] raw-file export: recipes as JSON, collection
- [ ] CPU profiling
- [ ] memory profiling
- [ ] compile time profiling
- [ ] Windows build
- [ ] macOS build

## Odin microui (`odin-microui/`)

- [X] install script for Ubuntu
- [X] install script for Fedora
- [X] hello world, open window
- [X] recipe view with hard-coded data
- [X] recipe view with SQLite integration
- [X] add recipe
- [X] edit recipe
- [X] delete recipe
- [X] recipe list: title, search by title
- [X] recipe detail: description, servings, ingredients, numbered steps, notes
- [X] display images (list thumbnails and detail photo)
- [X] import image from a file and store image files on disk
- [X] display animations: list/detail transitions
- [X] display animations: image loading state
- [ ] network request import: recipe JSON from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] network request import: recipe image from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] raw-file import: recipes as JSON, single recipe
- [ ] raw-file import: recipes as JSON, collection
- [ ] raw-file export: recipes as JSON, single recipe
- [ ] raw-file export: recipes as JSON, collection
- [ ] CPU profiling
- [ ] memory profiling
- [ ] compile time profiling
- [ ] Windows build
- [ ] macOS build

## Zig DVUI (`zig-dvui/`)

- [X] install script for Ubuntu
- [X] install script for Fedora
- [X] hello world, open window
- [X] recipe view with hard-coded data
- [X] recipe view with SQLite integration
- [X] add recipe
- [X] edit recipe
- [X] delete recipe
- [X] recipe list: title, search by title
- [X] recipe detail: description, servings, ingredients, numbered steps, notes
- [X] display images (list thumbnails and detail photo)
- [X] import image from a file and store image files on disk
- [X] display animations: list/detail transitions
- [X] display animations: image loading state
- [ ] network request import: recipe JSON from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] network request import: recipe image from a URL, asynchronously, with loading and error states, without blocking the UI
- [ ] raw-file import: recipes as JSON, single recipe
- [ ] raw-file import: recipes as JSON, collection
- [ ] raw-file export: recipes as JSON, single recipe
- [ ] raw-file export: recipes as JSON, collection
- [ ] CPU profiling
- [ ] memory profiling
- [ ] compile time profiling
- [ ] Windows build
- [ ] macOS build
