// Seed data only: inserted once, when the recipes table is empty.
// After that the app loads from the database, not from this file.
use crate::{Ingredient, Recipe};

pub(crate) fn seed_recipes() -> Vec<Recipe> {
    vec![
        Recipe {
            id: 0,
            title: "Banana Bread".to_string(),
            description: "A classic loaf, best with very ripe bananas.".to_string(),
            servings: 8,
            image_path: None,
            ingredients: vec![
                Ingredient { amount: "3".to_string(), unit: "".to_string(), name: "ripe bananas, mashed".to_string() },
                Ingredient { amount: "1/2".to_string(), unit: "cup".to_string(), name: "butter, melted".to_string() },
                Ingredient { amount: "3/4".to_string(), unit: "cup".to_string(), name: "sugar".to_string() },
                Ingredient { amount: "1".to_string(), unit: "".to_string(), name: "egg".to_string() },
                Ingredient { amount: "1".to_string(), unit: "tsp".to_string(), name: "vanilla".to_string() },
                Ingredient { amount: "1".to_string(), unit: "tsp".to_string(), name: "baking soda".to_string() },
                Ingredient { amount: "1 1/2".to_string(), unit: "cups".to_string(), name: "flour".to_string() },
            ],
            steps: vec![
                "Preheat the oven to 350°F and grease a 9x5 loaf pan.".to_string(),
                "Mash the bananas, then stir in the melted butter, sugar, egg, and vanilla.".to_string(),
                "Stir in the baking soda and flour until just combined.".to_string(),
                "Pour into the pan and bake for 55-65 minutes, until a toothpick comes out clean.".to_string(),
                "Cool in the pan for 10 minutes, then turn out onto a rack.".to_string(),
            ],
            notes: "Optional: fold in walnuts or chocolate chips before baking.".to_string(),
        },
        Recipe {
            id: 0,
            title: "Tomato Basil Pasta".to_string(),
            description: "A quick weeknight pasta with fresh tomatoes and basil.".to_string(),
            servings: 4,
            image_path: None,
            ingredients: vec![
                Ingredient { amount: "12".to_string(), unit: "oz".to_string(), name: "pasta".to_string() },
                Ingredient { amount: "2".to_string(), unit: "lbs".to_string(), name: "tomatoes, chopped".to_string() },
                Ingredient { amount: "3".to_string(), unit: "cloves".to_string(), name: "garlic, sliced".to_string() },
                Ingredient { amount: "1/4".to_string(), unit: "cup".to_string(), name: "olive oil".to_string() },
                Ingredient { amount: "1".to_string(), unit: "cup".to_string(), name: "basil leaves".to_string() },
                Ingredient { amount: "1/2".to_string(), unit: "cup".to_string(), name: "parmesan, grated".to_string() },
            ],
            steps: vec![
                "Cook the pasta in salted water until al dente, reserving a cup of pasta water.".to_string(),
                "Meanwhile, warm the olive oil and garlic until fragrant, about 2 minutes.".to_string(),
                "Add the tomatoes and cook until they soften, about 8 minutes.".to_string(),
                "Toss the pasta with the sauce, basil, and parmesan, adding pasta water as needed.".to_string(),
            ],
            notes: "Serve immediately, with extra parmesan on top.".to_string(),
        },
        Recipe {
            id: 0,
            title: "Chicken Stir Fry".to_string(),
            description: "Chicken and vegetables in a simple soy-ginger sauce, served with rice.".to_string(),
            servings: 4,
            image_path: None,
            ingredients: vec![
                Ingredient { amount: "1 1/2".to_string(), unit: "lbs".to_string(), name: "chicken breast, sliced".to_string() },
                Ingredient { amount: "2".to_string(), unit: "".to_string(), name: "bell peppers, sliced".to_string() },
                Ingredient { amount: "2".to_string(), unit: "cups".to_string(), name: "broccoli florets".to_string() },
                Ingredient { amount: "3".to_string(), unit: "tbsp".to_string(), name: "soy sauce".to_string() },
                Ingredient { amount: "1".to_string(), unit: "tbsp".to_string(), name: "ginger, grated".to_string() },
                Ingredient { amount: "2".to_string(), unit: "cloves".to_string(), name: "garlic, minced".to_string() },
            ],
            steps: vec![
                "Sear the chicken in a hot, oiled pan until cooked through, then set aside.".to_string(),
                "Stir fry the peppers and broccoli until just tender, about 4 minutes.".to_string(),
                "Return the chicken to the pan with the soy sauce, ginger, and garlic.".to_string(),
                "Cook for 2 more minutes, stirring, until the sauce coats everything.".to_string(),
            ],
            notes: "Serve over rice.".to_string(),
        },
    ]
}
