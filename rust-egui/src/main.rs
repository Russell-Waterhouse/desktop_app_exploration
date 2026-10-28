use eframe::egui;

// Mock data only for now. No disk or network access yet;
// this is a hard-coded stand-in for recipes that will later
// come from SQLite, files, or a network import.
struct Ingredient {
    amount: &'static str,
    unit: &'static str,
    name: &'static str,
}

struct Recipe {
    title: &'static str,
    description: &'static str,
    servings: u32,
    prep_minutes: u32,
    cook_minutes: u32,
    ingredients: Vec<Ingredient>,
    steps: Vec<&'static str>,
    notes: &'static str,
}

fn mock_recipes() -> Vec<Recipe> {
    vec![
        Recipe {
            title: "Banana Bread",
            description: "A classic loaf, best with very ripe bananas.",
            servings: 8,
            prep_minutes: 15,
            cook_minutes: 60,
            ingredients: vec![
                Ingredient { amount: "3", unit: "", name: "ripe bananas, mashed" },
                Ingredient { amount: "1/2", unit: "cup", name: "butter, melted" },
                Ingredient { amount: "3/4", unit: "cup", name: "sugar" },
                Ingredient { amount: "1", unit: "", name: "egg" },
                Ingredient { amount: "1", unit: "tsp", name: "vanilla" },
                Ingredient { amount: "1", unit: "tsp", name: "baking soda" },
                Ingredient { amount: "1 1/2", unit: "cups", name: "flour" },
            ],
            steps: vec![
                "Preheat the oven to 350°F and grease a 9x5 loaf pan.",
                "Mash the bananas, then stir in the melted butter, sugar, egg, and vanilla.",
                "Stir in the baking soda and flour until just combined.",
                "Pour into the pan and bake for 55-65 minutes, until a toothpick comes out clean.",
                "Cool in the pan for 10 minutes, then turn out onto a rack.",
            ],
            notes: "Optional: fold in walnuts or chocolate chips before baking.",
        },
        Recipe {
            title: "Tomato Basil Pasta",
            description: "A quick weeknight pasta with fresh tomatoes and basil.",
            servings: 4,
            prep_minutes: 10,
            cook_minutes: 20,
            ingredients: vec![
                Ingredient { amount: "12", unit: "oz", name: "pasta" },
                Ingredient { amount: "2", unit: "lbs", name: "tomatoes, chopped" },
                Ingredient { amount: "3", unit: "cloves", name: "garlic, sliced" },
                Ingredient { amount: "1/4", unit: "cup", name: "olive oil" },
                Ingredient { amount: "1", unit: "cup", name: "basil leaves" },
                Ingredient { amount: "1/2", unit: "cup", name: "parmesan, grated" },
            ],
            steps: vec![
                "Cook the pasta in salted water until al dente, reserving a cup of pasta water.",
                "Meanwhile, warm the olive oil and garlic until fragrant, about 2 minutes.",
                "Add the tomatoes and cook until they soften, about 8 minutes.",
                "Toss the pasta with the sauce, basil, and parmesan, adding pasta water as needed.",
            ],
            notes: "Serve immediately, with extra parmesan on top.",
        },
        Recipe {
            title: "Chicken Stir Fry",
            description: "Chicken and vegetables in a simple soy-ginger sauce, served with rice.",
            servings: 4,
            prep_minutes: 15,
            cook_minutes: 15,
            ingredients: vec![
                Ingredient { amount: "1 1/2", unit: "lbs", name: "chicken breast, sliced" },
                Ingredient { amount: "2", unit: "", name: "bell peppers, sliced" },
                Ingredient { amount: "2", unit: "cups", name: "broccoli florets" },
                Ingredient { amount: "3", unit: "tbsp", name: "soy sauce" },
                Ingredient { amount: "1", unit: "tbsp", name: "ginger, grated" },
                Ingredient { amount: "2", unit: "cloves", name: "garlic, minced" },
            ],
            steps: vec![
                "Sear the chicken in a hot, oiled pan until cooked through, then set aside.",
                "Stir fry the peppers and broccoli until just tender, about 4 minutes.",
                "Return the chicken to the pan with the soy sauce, ginger, and garlic.",
                "Cook for 2 more minutes, stirring, until the sauce coats everything.",
            ],
            notes: "Serve over rice.",
        },
    ]
}

struct RecipeApp {
    recipes: Vec<Recipe>,
    selected: usize,
    search: String,
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
            Ok(Box::new(RecipeApp {
                recipes: mock_recipes(),
                selected: 0,
                search: String::new(),
            }))
        }),
    )
}

impl eframe::App for RecipeApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        // Edit a copy of the search text inside the panel to keep
        // the borrow checker happy, then write it back afterwards.
        let mut selected = self.selected;
        let mut search = self.search.clone();

        egui::Panel::left("recipe_list").show(ui, |ui| {
            ui.heading("Recipes");
            ui.text_edit_singleline(&mut search);
            ui.separator();
            egui::ScrollArea::vertical().show(ui, |ui| {
                let query = search.to_lowercase();
                for (index, recipe) in self.recipes.iter().enumerate() {
                    if !query.is_empty() && !recipe.title.to_lowercase().contains(&query) {
                        continue;
                    }
                    if ui.selectable_label(selected == index, recipe.title).clicked() {
                        selected = index;
                    }
                }
            });
        });

        self.selected = selected;
        self.search = search;

        egui::CentralPanel::default().show(ui, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| {
                if let Some(recipe) = self.recipes.get(self.selected) {
                    ui.heading(recipe.title);
                    ui.label(recipe.description);
                    ui.label(format!(
                        "Servings: {}  •  Prep: {} min  •  Cook: {} min",
                        recipe.servings, recipe.prep_minutes, recipe.cook_minutes
                    ));
                    ui.separator();
                    ui.label("[No image yet]");
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
                    ui.label(recipe.notes);
                } else {
                    ui.label("No recipe selected.");
                }
            });
        });
    }
}
