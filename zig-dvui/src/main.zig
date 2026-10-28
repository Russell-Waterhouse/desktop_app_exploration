const std = @import("std");
const dvui = @import("dvui");
const db = @import("db.zig");

// Recipe manager test app, recipe view only.
// Recipes now load from SQLite (db.zig) in the current working
// directory, seeded once from the seed data below — the same
// seed the Rust and Odin versions use (Banana Bread, Tomato
// Basil Pasta, Chicken Stir Fry; 19 ingredients, 13 steps).
// No network yet.
//
// Layout, like the Rust version:
//   - left pane: "Recipes", a title search box, one button per
//     matching recipe, selected recipe marked with "> "
//   - right pane: detail for the selected recipe — description,
//     servings, "[No image yet]", ingredients,
//     numbered steps, notes
// The search filters the list only; the detail keeps showing
// the selected recipe even if it no longer matches the filter,
// as in the Rust and Odin versions.

pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 900.0, .h = 600.0 },
            .title = "Recipe Manager",
            .org = "example",
            .app = "recipe-manager",
        },
    },
    .frameFn = appFrame,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

// Seed data, used only when recipes.db is empty on first run;
// later runs load from the database and do not re-seed.
const seed_recipes: [3]db.Recipe = .{
    .{
        .title = "Banana Bread",
        .description = "A classic loaf, best with very ripe bananas.",
        .servings = 8,
        .ingredients = &.{
            .{ .amount = "3", .unit = "", .name = "ripe bananas, mashed" },
            .{ .amount = "1/2", .unit = "cup", .name = "butter, melted" },
            .{ .amount = "3/4", .unit = "cup", .name = "sugar" },
            .{ .amount = "1", .unit = "", .name = "egg" },
            .{ .amount = "1", .unit = "tsp", .name = "vanilla" },
            .{ .amount = "1", .unit = "tsp", .name = "baking soda" },
            .{ .amount = "1 1/2", .unit = "cups", .name = "flour" },
        },
        .steps = &.{
            "Preheat the oven to 350°F and grease a 9x5 loaf pan.",
            "Mash the bananas, then stir in the melted butter, sugar, egg, and vanilla.",
            "Stir in the baking soda and flour until just combined.",
            "Pour into the pan and bake for 55-65 minutes, until a toothpick comes out clean.",
            "Cool in the pan for 10 minutes, then turn out onto a rack.",
        },
        .notes = "Optional: fold in walnuts or chocolate chips before baking.",
    },
    .{
        .title = "Tomato Basil Pasta",
        .description = "A quick weeknight pasta with fresh tomatoes and basil.",
        .servings = 4,
        .ingredients = &.{
            .{ .amount = "12", .unit = "oz", .name = "pasta" },
            .{ .amount = "2", .unit = "lbs", .name = "tomatoes, chopped" },
            .{ .amount = "3", .unit = "cloves", .name = "garlic, sliced" },
            .{ .amount = "1/4", .unit = "cup", .name = "olive oil" },
            .{ .amount = "1", .unit = "cup", .name = "basil leaves" },
            .{ .amount = "1/2", .unit = "cup", .name = "parmesan, grated" },
        },
        .steps = &.{
            "Cook the pasta in salted water until al dente, reserving a cup of pasta water.",
            "Meanwhile, warm the olive oil and garlic until fragrant, about 2 minutes.",
            "Add the tomatoes and cook until they soften, about 8 minutes.",
            "Toss the pasta with the sauce, basil, and parmesan, adding pasta water as needed.",
        },
        .notes = "Serve immediately, with extra parmesan on top.",
    },
    .{
        .title = "Chicken Stir Fry",
        .description = "Chicken and vegetables in a simple soy-ginger sauce, served with rice.",
        .servings = 4,
        .ingredients = &.{
            .{ .amount = "1 1/2", .unit = "lbs", .name = "chicken breast, sliced" },
            .{ .amount = "2", .unit = "", .name = "bell peppers, sliced" },
            .{ .amount = "2", .unit = "cups", .name = "broccoli florets" },
            .{ .amount = "3", .unit = "tbsp", .name = "soy sauce" },
            .{ .amount = "1", .unit = "tbsp", .name = "ginger, grated" },
            .{ .amount = "2", .unit = "cloves", .name = "garlic, minced" },
        },
        .steps = &.{
            "Sear the chicken in a hot, oiled pan until cooked through, then set aside.",
            "Stir fry the peppers and broccoli until just tender, about 4 minutes.",
            "Return the chicken to the pan with the soy sauce, ginger, and garlic.",
            "Cook for 2 more minutes, stirring, until the sauce coats everything.",
        },
        .notes = "Serve over rice.",
    },
};

// Frame-persistent UI state. The search text lives in a fixed
// buffer that the text entry widget owns between frames.
var selected_recipe: usize = 0;
var search_buffer: [128]u8 = @splat(0);

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    for (0..haystack.len - needle.len + 1) |i| {
        var matches = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}

pub fn appFrame() !dvui.App.Result {
    // Load from SQLite on the first frame; a no-op after that.
    // On failure db.recipes stays empty and db.load_error is
    // set, shown in the detail pane below instead of crashing.
    db.ensureLoaded(&seed_recipes);
    const recipes = db.recipes;

    var root = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .background = true });
    defer root.deinit();

    // Left pane: list + search.
    {
        var left = dvui.box(@src(), .{ .dir = .vertical }, .{
            .min_size_content = .{ .w = 260.0 },
            .expand = .vertical,
            .background = true,
            .padding = .all(8),
        });
        defer left.deinit();

        dvui.label(@src(), "Recipes", .{}, .{ .font = .theme(.title) });
        dvui.label(@src(), "Search recipes:", .{}, .{});

        // The text entry returns its current text; deinit after
        // reading it, as in DVUI's own examples.
        var search_entry = dvui.textEntry(@src(), .{ .text = .{ .buffer = &search_buffer } }, .{ .expand = .horizontal });
        const filter = search_entry.textGet();
        search_entry.deinit();

        for (recipes, 0..) |recipe, i| {
            if (!containsIgnoreCase(recipe.title, filter)) continue;
            // Buttons are identified by @src() plus id_extra, so
            // each recipe in the loop gets its own widget id.
            var label_buf: [64]u8 = undefined;
            const button_label = if (i == selected_recipe)
                std.fmt.bufPrint(&label_buf, "> {s}", .{recipe.title}) catch recipe.title
            else
                recipe.title;
            if (dvui.button(@src(), button_label, .{}, .{ .id_extra = i, .expand = .horizontal })) {
                selected_recipe = i;
            }
        }
    }

    // Right pane: detail for the selected recipe, scrollable.
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();

        var detail = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .horizontal,
            .padding = .all(8),
        });
        defer detail.deinit();

        if (db.load_error) |err| {
            dvui.label(@src(), "Failed to load recipes:", .{}, .{ .font = .theme(.title) });
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
            defer tl.deinit();
            tl.addText(err, .{});
            return .ok;
        }
        if (recipes.len == 0) {
            dvui.label(@src(), "No recipes found.", .{}, .{ .font = .theme(.title) });
            return .ok;
        }

        // Clamp the selection if the loaded list is shorter
        // than the previously selected index.
        const recipe = recipes[@min(selected_recipe, recipes.len - 1)];

        dvui.label(@src(), "{s}", .{recipe.title}, .{ .font = .theme(.title) });

        {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
            defer tl.deinit();
            tl.addText(recipe.description, .{});
        }

        dvui.label(@src(), "Servings: {d}", .{recipe.servings}, .{});
        dvui.label(@src(), "[No image yet]", .{}, .{});

        dvui.label(@src(), "Ingredients", .{}, .{ .font = .theme(.title) });
        for (recipe.ingredients, 0..) |ing, i| {
            // One label per ingredient, each with its own id.
            if (ing.unit.len == 0) {
                dvui.label(@src(), "- {s} {s}", .{ ing.amount, ing.name }, .{ .id_extra = i });
            } else {
                dvui.label(@src(), "- {s} {s} {s}", .{ ing.amount, ing.unit, ing.name }, .{ .id_extra = i });
            }
        }

        dvui.label(@src(), "Steps", .{}, .{ .font = .theme(.title) });
        for (recipe.steps, 0..) |step, i| {
            var tl = dvui.textLayout(@src(), .{}, .{ .id_extra = i, .expand = .horizontal });
            defer tl.deinit();
            tl.format("{d}. {s}", .{ i + 1, step }, .{});
        }

        dvui.label(@src(), "Notes", .{}, .{ .font = .theme(.title) });
        {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
            defer tl.deinit();
            tl.addText(recipe.notes, .{});
        }
    }

    return .ok;
}
