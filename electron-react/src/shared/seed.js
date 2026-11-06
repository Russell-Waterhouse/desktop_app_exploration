// Seed data for the SQLite database, matching the seed data used
// by the other stacks (odin-gtk/src/recipes.odin, rust-egui
// src/seed.rs): the same three recipes, in the same order, with
// the same ingredients and steps, plus the four complex-text
// probe recipes (Arabic, Devanagari, Simplified Chinese, emoji).
// At runtime the app loads from recipes.db, not from here; this
// is only inserted once, when the recipes table is empty.
// image_path is "" (stored as NULL) until the image step sets it.

export const SEED_RECIPES = [
  {
    title: 'Banana Bread',
    description: 'A classic loaf, best with very ripe bananas.',
    servings: 8,
    image_path: '',
    notes: 'Optional: fold in walnuts or chocolate chips before baking.',
    ingredients: [
      { amount: '3', unit: '', name: 'ripe bananas, mashed' },
      { amount: '1/2', unit: 'cup', name: 'butter, melted' },
      { amount: '3/4', unit: 'cup', name: 'sugar' },
      { amount: '1', unit: '', name: 'egg' },
      { amount: '1', unit: 'tsp', name: 'vanilla' },
      { amount: '1', unit: 'tsp', name: 'baking soda' },
      { amount: '1 1/2', unit: 'cups', name: 'flour' },
    ],
    steps: [
      'Preheat the oven to 350°F and grease a 9x5 loaf pan.',
      'Mash the bananas, then stir in the melted butter, sugar, egg, and vanilla.',
      'Stir in the baking soda and flour until just combined.',
      'Pour into the pan and bake for 55-65 minutes, until a toothpick comes out clean.',
      'Cool in the pan for 10 minutes, then turn out onto a rack.',
    ],
  },
  {
    title: 'Tomato Basil Pasta',
    description: 'A quick weeknight pasta with fresh tomatoes and basil.',
    servings: 4,
    image_path: '',
    notes: 'Serve immediately, with extra parmesan on top.',
    ingredients: [
      { amount: '12', unit: 'oz', name: 'pasta' },
      { amount: '2', unit: 'lbs', name: 'tomatoes, chopped' },
      { amount: '3', unit: 'cloves', name: 'garlic, sliced' },
      { amount: '1/4', unit: 'cup', name: 'olive oil' },
      { amount: '1', unit: 'cup', name: 'basil leaves' },
      { amount: '1/2', unit: 'cup', name: 'parmesan, grated' },
    ],
    steps: [
      'Cook the pasta in salted water until al dente, reserving a cup of pasta water.',
      'Meanwhile, warm the olive oil and garlic until fragrant, about 2 minutes.',
      'Add the tomatoes and cook until they soften, about 8 minutes.',
      'Toss the pasta with the sauce, basil, and parmesan, adding pasta water as needed.',
    ],
  },
  {
    title: 'Chicken Stir Fry',
    description: 'Chicken and vegetables in a simple soy-ginger sauce, served with rice.',
    servings: 4,
    image_path: '',
    notes: 'Serve over rice.',
    ingredients: [
      { amount: '1 1/2', unit: 'lbs', name: 'chicken breast, sliced' },
      { amount: '2', unit: '', name: 'bell peppers, sliced' },
      { amount: '2', unit: 'cups', name: 'broccoli florets' },
      { amount: '3', unit: 'tbsp', name: 'soy sauce' },
      { amount: '1', unit: 'tbsp', name: 'ginger, grated' },
      { amount: '2', unit: 'cloves', name: 'garlic, minced' },
    ],
    steps: [
      'Sear the chicken in a hot, oiled pan until cooked through, then set aside.',
      'Stir fry the peppers and broccoli until just tender, about 4 minutes.',
      'Return the chicken to the pan with the soy sauce, ginger, and garlic.',
      'Cook for 2 more minutes, stirring, until the sauce coats everything.',
    ],
  },
  {
    title: 'كبسة الدجاج',
    description: 'طبق أرز تقليدي مع الدجاج والبهارات المشكلة.',
    servings: 4,
    image_path: '',
    notes: 'تُقدم مع السلطة.',
    ingredients: [
      { amount: '1', unit: '', name: 'دجاج' },
      { amount: '2', unit: 'كوب', name: 'أرز بسمتي' },
    ],
    steps: ['يُتبل الدجاج بالبهارات ويُحمر.', 'يُضاف الأرز والمرق ويُطهى حتى ينضج.'],
  },
  {
    title: 'पालक पनीर',
    description: 'पालक और पनीर से बना एक लोकप्रिय उत्तर भारतीय व्यंजन।',
    servings: 4,
    image_path: '',
    notes: 'रोटी या चावल के साथ परोसें।',
    ingredients: [
      { amount: '500', unit: 'ग्राम', name: 'पालक' },
      { amount: '200', unit: 'ग्राम', name: 'पनीर' },
    ],
    steps: ['पालक को उबालकर पीस लें।', 'पनीर डालकर धीमी आंच पर पकाएं।'],
  },
  {
    title: '番茄炒蛋',
    description: '一道简单快捷的家常菜，酸甜可口，老少皆宜。',
    servings: 2,
    image_path: '',
    notes: '配米饭食用最佳。',
    ingredients: [
      { amount: '2', unit: '个', name: '番茄' },
      { amount: '3', unit: '个', name: '鸡蛋' },
    ],
    steps: ['鸡蛋打散，入锅炒熟盛出。', '番茄炒软后加入鸡蛋，调味出锅。'],
  },
  {
    title: '🥞 Blueberry Pancakes 🫐',
    description: 'Fluffy pancakes with 🫐 blueberries, served with 🍁 maple syrup.',
    servings: 4,
    image_path: '',
    notes: 'Extra 🫐 on top never hurts.',
    ingredients: [
      { amount: '2', unit: 'cups', name: 'flour' },
      { amount: '1', unit: 'cup', name: '🫐 blueberries' },
    ],
    steps: [
      'Mix the batter and fold in the 🫐 blueberries.',
      'Cook on a hot griddle until golden, then serve with 🍁 syrup.',
    ],
  },
]
