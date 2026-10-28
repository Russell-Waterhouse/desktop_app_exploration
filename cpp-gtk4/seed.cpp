#include "seed.h"

// Seed data: the same 3 recipes the other stacks use (7 + 6 + 6
// ingredients, 5 + 4 + 4 steps: 19 ingredients, 13 steps total).
std::vector<Recipe> seed_recipes() {
    return {
        {
            0,
            "Banana Bread",
            "A classic loaf, best with very ripe bananas.",
            8,
            "",
            {
                {"3", "", "ripe bananas, mashed"},
                {"1/2", "cup", "butter, melted"},
                {"3/4", "cup", "sugar"},
                {"1", "", "egg"},
                {"1", "tsp", "vanilla"},
                {"1", "tsp", "baking soda"},
                {"1 1/2", "cups", "flour"},
            },
            {
                "Preheat the oven to 350°F and grease a 9x5 loaf pan.",
                "Mash the bananas, then stir in the melted butter, sugar, egg, and vanilla.",
                "Stir in the baking soda and flour until just combined.",
                "Pour into the pan and bake for 55-65 minutes, until a toothpick comes out clean.",
                "Cool in the pan for 10 minutes, then turn out onto a rack.",
            },
            "Optional: fold in walnuts or chocolate chips before baking.",
        },
        {
            0,
            "Tomato Basil Pasta",
            "A quick weeknight pasta with fresh tomatoes and basil.",
            4,
            "",
            {
                {"12", "oz", "pasta"},
                {"2", "lbs", "tomatoes, chopped"},
                {"3", "cloves", "garlic, sliced"},
                {"1/4", "cup", "olive oil"},
                {"1", "cup", "basil leaves"},
                {"1/2", "cup", "parmesan, grated"},
            },
            {
                "Cook the pasta in salted water until al dente, reserving a cup of pasta water.",
                "Meanwhile, warm the olive oil and garlic until fragrant, about 2 minutes.",
                "Add the tomatoes and cook until they soften, about 8 minutes.",
                "Toss the pasta with the sauce, basil, and parmesan, adding pasta water as needed.",
            },
            "Serve immediately, with extra parmesan on top.",
        },
        {
            0,
            "Chicken Stir Fry",
            "Chicken and vegetables in a simple soy-ginger sauce, served with rice.",
            4,
            "",
            {
                {"1 1/2", "lbs", "chicken breast, sliced"},
                {"2", "", "bell peppers, sliced"},
                {"2", "cups", "broccoli florets"},
                {"3", "tbsp", "soy sauce"},
                {"1", "tbsp", "ginger, grated"},
                {"2", "cloves", "garlic, minced"},
            },
            {
                "Sear the chicken in a hot, oiled pan until cooked through, then set aside.",
                "Stir fry the peppers and broccoli until just tender, about 4 minutes.",
                "Return the chicken to the pan with the soy sauce, ginger, and garlic.",
                "Cook for 2 more minutes, stirring, until the sauce coats everything.",
            },
            "Serve over rice.",
        },
    };
}
