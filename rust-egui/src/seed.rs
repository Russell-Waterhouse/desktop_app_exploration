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
        // Complex-text recipes: one per script family the todo item
        // names, kept as seed data to exercise egui's default fonts
        // in the list and detail panes.
        Recipe {
            id: 0,
            title: "كبسة الدجاج".to_string(),
            description: "طبق أرز تقليدي مع الدجاج والبهارات المشكلة.".to_string(),
            servings: 4,
            image_path: None,
            ingredients: vec![
                Ingredient { amount: "1".to_string(), unit: "".to_string(), name: "دجاج".to_string() },
                Ingredient { amount: "2".to_string(), unit: "كوب".to_string(), name: "أرز بسمتي".to_string() },
            ],
            steps: vec![
                "يُتبل الدجاج بالبهارات ويُحمر.".to_string(),
                "يُضاف الأرز والمرق ويُطهى حتى ينضج.".to_string(),
            ],
            notes: "تُقدم مع السلطة.".to_string(),
        },
        Recipe {
            id: 0,
            title: "पालक पनीर".to_string(),
            description: "पालक और पनीर से बना एक लोकप्रिय उत्तर भारतीय व्यंजन।".to_string(),
            servings: 4,
            image_path: None,
            ingredients: vec![
                Ingredient { amount: "500".to_string(), unit: "ग्राम".to_string(), name: "पालक".to_string() },
                Ingredient { amount: "200".to_string(), unit: "ग्राम".to_string(), name: "पनीर".to_string() },
            ],
            steps: vec![
                "पालक को उबालकर पीस लें।".to_string(),
                "पनीर डालकर धीमी आंच पर पकाएं।".to_string(),
            ],
            notes: "रोटी या चावल के साथ परोसें।".to_string(),
        },
        Recipe {
            id: 0,
            title: "番茄炒蛋".to_string(),
            description: "一道简单快捷的家常菜，酸甜可口，老少皆宜。".to_string(),
            servings: 2,
            image_path: None,
            ingredients: vec![
                Ingredient { amount: "2".to_string(), unit: "个".to_string(), name: "番茄".to_string() },
                Ingredient { amount: "3".to_string(), unit: "个".to_string(), name: "鸡蛋".to_string() },
            ],
            steps: vec![
                "鸡蛋打散，入锅炒熟盛出。".to_string(),
                "番茄炒软后加入鸡蛋，调味出锅。".to_string(),
            ],
            notes: "配米饭食用最佳。".to_string(),
        },
        Recipe {
            id: 0,
            title: "🥞 Blueberry Pancakes 🫐".to_string(),
            description: "Fluffy pancakes with 🫐 blueberries, served with 🍁 maple syrup.".to_string(),
            servings: 4,
            image_path: None,
            ingredients: vec![
                Ingredient { amount: "2".to_string(), unit: "cups".to_string(), name: "flour".to_string() },
                Ingredient { amount: "1".to_string(), unit: "cup".to_string(), name: "🫐 blueberries".to_string() },
            ],
            steps: vec![
                "Mix the batter and fold in the 🫐 blueberries.".to_string(),
                "Cook on a hot griddle until golden, then serve with 🍁 syrup.".to_string(),
            ],
            notes: "Extra 🫐 on top never hurts.".to_string(),
        },
    ]
}
