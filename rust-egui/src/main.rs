mod db;
mod images;
mod seed;

use eframe::egui;
use std::collections::{HashMap, HashSet};

#[derive(Clone)]
struct Ingredient {
    amount: String,
    unit: String,
    name: String,
}

#[derive(Clone)]
struct Recipe {
    // 0 means "not in the database yet"; a real row always has id >= 1.
    id: i64,
    title: String,
    description: String,
    servings: i64,
    image_path: Option<String>,
    ingredients: Vec<Ingredient>,
    steps: Vec<String>,
    notes: String,
}

// The form edits this, not the Recipe in the list. Save converts it
// back to a Recipe (validating the number fields); Cancel discards it.
struct EditDraft {
    id: i64,
    title: String,
    description: String,
    servings_text: String,
    image_path: String,
    ingredients: Vec<Ingredient>,
    steps: Vec<String>,
    notes: String,
}

impl EditDraft {
    fn from_recipe(recipe: &Recipe) -> Self {
        EditDraft {
            id: recipe.id,
            title: recipe.title.clone(),
            description: recipe.description.clone(),
            servings_text: recipe.servings.to_string(),
            image_path: recipe.image_path.clone().unwrap_or_default(),
            ingredients: recipe.ingredients.clone(),
            steps: recipe.steps.clone(),
            notes: recipe.notes.clone(),
        }
    }

    fn empty() -> Self {
        EditDraft {
            id: 0,
            title: String::new(),
            description: String::new(),
            servings_text: String::new(),
            image_path: String::new(),
            ingredients: Vec::new(),
            steps: Vec::new(),
            notes: String::new(),
        }
    }

    // Returns Err(message) instead of a Recipe when validation fails.
    fn to_recipe(&self) -> Result<Recipe, String> {
        let title = self.title.trim();
        if title.is_empty() {
            return Err("Title is required.".to_string());
        }
        let parse_number = |text: &str, field: &str| -> Result<i64, String> {
            text.trim()
                .parse::<i64>()
                .map_err(|_| format!("{} must be a whole number.", field))
        };
        Ok(Recipe {
            id: self.id,
            title: title.to_string(),
            description: self.description.clone(),
            servings: parse_number(&self.servings_text, "Servings")?,
            image_path: {
                let path = self.image_path.trim();
                if path.is_empty() {
                    None
                } else {
                    Some(path.to_string())
                }
            },
            ingredients: self.ingredients.clone(),
            steps: self.steps.clone(),
            notes: self.notes.clone(),
        })
    }
}

enum Mode {
    Viewing,
    Editing { draft: EditDraft, is_new: bool },
}

struct RecipeApp {
    recipes: Vec<Recipe>,
    selected_id: Option<i64>,
    search: String,
    load_error: Option<String>,
    mode: Mode,
    form_error: Option<String>,
    detail_error: Option<String>,
    confirming_delete: bool,
    // Texture cache, keyed by image path. Textures are never evicted
    // in this version; fine for a small test app.
    textures: HashMap<String, egui::TextureHandle>,
    texture_failures: HashSet<String>,
}

// Load and cache a texture for an image file, once. Returns None
// (and remembers the failure, so it is not retried every frame)
// when the file is missing or cannot be decoded.
fn texture_for(
    ui: &mut egui::Ui,
    textures: &mut HashMap<String, egui::TextureHandle>,
    failures: &mut HashSet<String>,
    path: &str,
) -> Option<egui::TextureHandle> {
    if let Some(texture) = textures.get(path) {
        return Some(texture.clone());
    }
    if failures.contains(path) {
        return None;
    }
    let rgba = image::open(path).ok()?.to_rgba8();
    let (width, height) = rgba.dimensions();
    let pixels = rgba.into_raw();
    let color_image = egui::ColorImage::from_rgba_unmultiplied(
        [width as usize, height as usize],
        &pixels,
    );
    let texture = ui
        .ctx()
        .load_texture(path, color_image, egui::TextureOptions::default());
    textures.insert(path.to_string(), texture.clone());
    Some(texture)
}

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([900.0, 600.0]),
        ..Default::default()
    };
    eframe::run_native(
        "Recipe Manager",
        options,
        Box::new(|_cc| {
            let (recipes, load_error) = match db::load_recipes() {
                Ok(recipes) => (recipes, None),
                Err(err) => (Vec::new(), Some(err.to_string())),
            };
            let selected_id = recipes.first().map(|recipe| recipe.id);
            Ok(Box::new(RecipeApp {
                recipes,
                selected_id,
                search: String::new(),
                load_error,
                mode: Mode::Viewing,
                form_error: None,
                detail_error: None,
                confirming_delete: false,
                textures: HashMap::new(),
                texture_failures: HashSet::new(),
            }))
        }),
    )
}

impl RecipeApp {
    fn selected_recipe(&self) -> Option<&Recipe> {
        let id = self.selected_id?;
        self.recipes.iter().find(|recipe| recipe.id == id)
    }
}

impl eframe::App for RecipeApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        // Pre-load textures for every recipe with an image, so the
        // list and detail panes below can use the cache by lookup.
        let image_paths: Vec<String> = self
            .recipes
            .iter()
            .filter_map(|recipe| recipe.image_path.clone())
            .collect();
        for path in image_paths {
            texture_for(ui, &mut self.textures, &mut self.texture_failures, &path);
        }

        let editing = matches!(self.mode, Mode::Editing { .. });
        // Edit a copy of the search text inside the panel to keep
        // the borrow checker happy, then write it back afterwards.
        let mut selected_id = self.selected_id;
        let mut search = self.search.clone();

        egui::Panel::left("recipe_list").show(ui, |ui| {
            ui.heading("Recipes");
            ui.label("Search recipes:");
            ui.add(
                egui::TextEdit::singleline(&mut search)
                    .hint_text("Type to filter recipes…"),
            );
            if ui.button("Add recipe").clicked() && !editing {
                self.mode = Mode::Editing {
                    draft: EditDraft::empty(),
                    is_new: true,
                };
                self.form_error = None;
            }
            ui.separator();
            egui::ScrollArea::vertical().show(ui, |ui| {
                let query = search.to_lowercase();
                for recipe in self.recipes.iter() {
                    if !query.is_empty() && !recipe.title.to_lowercase().contains(&query) {
                        continue;
                    }
                    let thumbnail = recipe
                        .image_path
                        .as_ref()
                        .and_then(|path| self.textures.get(path).cloned());
                    ui.horizontal(|ui| {
                        if let Some(texture) = thumbnail {
                            ui.add(
                                egui::Image::new(&texture)
                                    .fit_to_exact_size(egui::vec2(32.0, 32.0)),
                            );
                        }
                        if editing {
                            // Don't let a list click discard an in-progress edit.
                            ui.label(&recipe.title);
                        } else if ui
                            .selectable_label(selected_id == Some(recipe.id), &recipe.title)
                            .clicked()
                        {
                            selected_id = Some(recipe.id);
                            self.confirming_delete = false;
                            self.detail_error = None;
                        }
                    });
                }
            });
        });

        self.selected_id = selected_id;
        self.search = search;

        egui::CentralPanel::default().show(ui, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| {
                if let Some(error) = &self.load_error {
                    ui.heading("Could not load recipes");
                    ui.label(error);
                    return;
                }

                // Editing mode takes over the whole detail pane.
                // Take the draft out so the form can mutate it without
                // borrowing self.mode at the same time as self.recipes.
                if let Mode::Editing { .. } = self.mode {
                    let (mut draft, is_new) =
                        match std::mem::replace(&mut self.mode, Mode::Viewing) {
                            Mode::Editing { draft, is_new } => (draft, is_new),
                            _ => unreachable!(),
                        };
                    ui.heading(if is_new { "Add recipe" } else { "Edit recipe" });
                    if let Some(error) = &self.form_error {
                        ui.colored_label(egui::Color32::RED, error);
                    }

                    ui.label("Title:");
                    ui.text_edit_singleline(&mut draft.title);
                    ui.label("Description:");
                    ui.text_edit_multiline(&mut draft.description);
                    ui.label("Servings:");
                    ui.text_edit_singleline(&mut draft.servings_text);
                    ui.label("Image path:");
                    ui.horizontal(|ui| {
                        ui.text_edit_singleline(&mut draft.image_path);
                        if ui.button("Choose image…").clicked() {
                            if let Some(path) = rfd::FileDialog::new()
                                .add_filter("Images", &["png", "jpg", "jpeg", "webp", "gif", "bmp"])
                                .pick_file()
                            {
                                match images::import_image(&path) {
                                    Ok(imported) => {
                                        draft.image_path = imported;
                                        self.form_error = None;
                                    }
                                    Err(err) => {
                                        self.form_error = Some(err);
                                    }
                                }
                            }
                        }
                    });
                    ui.separator();

                    ui.heading("Ingredients");
                    let mut remove_ingredient: Option<usize> = None;
                    for (index, ingredient) in draft.ingredients.iter_mut().enumerate() {
                        ui.horizontal(|ui| {
                            ui.add(
                                egui::TextEdit::singleline(&mut ingredient.amount)
                                    .desired_width(50.0),
                            );
                            ui.add(
                                egui::TextEdit::singleline(&mut ingredient.unit)
                                    .desired_width(50.0),
                            );
                            ui.add(
                                egui::TextEdit::singleline(&mut ingredient.name)
                                    .desired_width(200.0),
                            );
                            if ui.button("Remove").clicked() {
                                remove_ingredient = Some(index);
                            }
                        });
                    }
                    if let Some(index) = remove_ingredient {
                        draft.ingredients.remove(index);
                    }
                    if ui.button("Add ingredient").clicked() {
                        draft.ingredients.push(Ingredient {
                            amount: String::new(),
                            unit: String::new(),
                            name: String::new(),
                        });
                    }
                    ui.separator();

                    ui.heading("Steps");
                    let mut remove_step: Option<usize> = None;
                    for (index, step) in draft.steps.iter_mut().enumerate() {
                        ui.horizontal(|ui| {
                            ui.add(
                                egui::TextEdit::singleline(step).desired_width(400.0),
                            );
                            if ui.button("Remove").clicked() {
                                remove_step = Some(index);
                            }
                        });
                    }
                    if let Some(index) = remove_step {
                        draft.steps.remove(index);
                    }
                    if ui.button("Add step").clicked() {
                        draft.steps.push(String::new());
                    }
                    ui.separator();

                    ui.label("Notes:");
                    ui.text_edit_multiline(&mut draft.notes);
                    ui.separator();

                    let mut saved = false;
                    ui.horizontal(|ui| {
                        if ui.button("Save").clicked() {
                            match draft.to_recipe() {
                                Ok(recipe) => {
                                    let result = if is_new {
                                        match db::insert_recipe(&recipe) {
                                            Ok(id) => {
                                                let mut saved_recipe = recipe;
                                                saved_recipe.id = id;
                                                Ok(saved_recipe)
                                            }
                                            Err(err) => Err(err),
                                        }
                                    } else {
                                        db::update_recipe(&recipe).map(|_| recipe)
                                    };
                                    match result {
                                        Ok(recipe) => {
                                            if is_new {
                                                self.recipes.push(recipe.clone());
                                            } else if let Some(existing) = self
                                                .recipes
                                                .iter_mut()
                                                .find(|r| r.id == recipe.id)
                                            {
                                                *existing = recipe.clone();
                                            }
                                            self.selected_id = Some(recipe.id);
                                            self.form_error = None;
                                            saved = true;
                                        }
                                        Err(err) => {
                                            self.form_error = Some(err.to_string());
                                        }
                                    }
                                }
                                Err(message) => {
                                    self.form_error = Some(message);
                                }
                            }
                        }
                        if ui.button("Cancel").clicked() {
                            self.form_error = None;
                            saved = true;
                        }
                    });
                    if !saved {
                        // Still editing: put the draft back.
                        self.mode = Mode::Editing {
                            draft,
                            is_new,
                        };
                    }
                    return;
                }

                if let Some(recipe) = self.selected_recipe().cloned() {
                    ui.heading(&recipe.title);
                    ui.label(&recipe.description);
                    ui.label(format!("Servings: {}", recipe.servings));
                    if let Some(path) = &recipe.image_path {
                        if let Some(texture) = self.textures.get(path).cloned() {
                            ui.add(
                                egui::Image::new(&texture)
                                    .max_width(400.0)
                                    .max_height(300.0),
                            );
                        } else if self.texture_failures.contains(path) {
                            ui.label(format!("[Image could not be loaded: {}]", path));
                        } else {
                            ui.label("[No image yet]");
                        }
                    } else {
                        ui.label("[No image yet]");
                    }
                    ui.horizontal(|ui| {
                        if ui.button("Edit").clicked() {
                            self.mode = Mode::Editing {
                                draft: EditDraft::from_recipe(&recipe),
                                is_new: false,
                            };
                            self.form_error = None;
                            self.confirming_delete = false;
                        }
                        if ui.button("Delete").clicked() {
                            self.confirming_delete = true;
                        }
                    });
                    if let Some(error) = &self.detail_error {
                        ui.colored_label(egui::Color32::RED, error);
                    }
                    if self.confirming_delete {
                        ui.label(format!("Delete \"{}\" for good?", recipe.title));
                        ui.horizontal(|ui| {
                            if ui.button("Confirm delete").clicked() {
                                match db::delete_recipe(recipe.id) {
                                    Ok(()) => {
                                        self.recipes.retain(|r| r.id != recipe.id);
                                        self.selected_id = self
                                            .recipes
                                            .first()
                                            .map(|r| r.id);
                                        self.confirming_delete = false;
                                        self.detail_error = None;
                                    }
                                    Err(err) => {
                                        self.detail_error = Some(err.to_string());
                                        self.confirming_delete = false;
                                    }
                                }
                            }
                            if ui.button("Keep it").clicked() {
                                self.confirming_delete = false;
                            }
                        });
                    }
                    ui.separator();

                    ui.heading("Ingredients");
                    for ingredient in &recipe.ingredients {
                        if ingredient.unit.is_empty() {
                            ui.label(format!("• {} {}", ingredient.amount, ingredient.name));
                        } else {
                            ui.label(format!(
                                "• {} {} {}",
                                ingredient.amount, ingredient.unit, ingredient.name
                            ));
                        }
                    }
                    ui.separator();

                    ui.heading("Steps");
                    for (index, step) in recipe.steps.iter().enumerate() {
                        ui.label(format!("{}. {}", index + 1, step));
                    }
                    ui.separator();

                    ui.heading("Notes");
                    ui.label(&recipe.notes);
                } else {
                    ui.label("No recipe selected.");
                }
            });
        });
    }
}
