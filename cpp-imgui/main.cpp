// Dear ImGui recipe view, using SDL2 + OpenGL3 as the backend.
// SDL is the windowing/drawing backend here; Dear ImGui is the UI layer.
//
// Mock data only for now. No disk or network access yet;
// this is a hard-coded stand-in for recipes that will later
// come from SQLite, files, or a network import.
#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#include <SDL.h>
#include <SDL_opengl.h>

#include "imgui.h"
#include "imgui_impl_opengl3.h"
#include "imgui_impl_sdl2.h"

struct Ingredient {
    std::string amount;
    std::string unit;
    std::string name;
};

struct Recipe {
    std::string title;
    std::string description;
    int servings;
    int prep_minutes;
    int cook_minutes;
    std::vector<Ingredient> ingredients;
    std::vector<std::string> steps;
    std::string notes;
};

std::vector<Recipe> mock_recipes() {
    return {
        {
            "Banana Bread",
            "A classic loaf, best with very ripe bananas.",
            8,
            15,
            60,
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
            "Tomato Basil Pasta",
            "A quick weeknight pasta with fresh tomatoes and basil.",
            4,
            10,
            20,
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
            "Chicken Stir Fry",
            "Chicken and vegetables in a simple soy-ginger sauce, served with rice.",
            4,
            15,
            15,
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

std::string to_lower(const std::string& text) {
    std::string lowered = text;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    return lowered;
}

int main(int, char**) {
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        return 1;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

    SDL_Window* window = SDL_CreateWindow(
        "Recipe Manager", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 900, 600,
        SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
    if (window == nullptr) {
        SDL_Quit();
        return 1;
    }

    SDL_GLContext gl_context = SDL_GL_CreateContext(window);
    SDL_GL_MakeCurrent(window, gl_context);
    SDL_GL_SetSwapInterval(1);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::StyleColorsDark();
    ImGui_ImplSDL2_InitForOpenGL(window, gl_context);
    ImGui_ImplOpenGL3_Init("#version 130");

    std::vector<Recipe> recipes = mock_recipes();
    int selected = 0;
    char search_buf[256] = "";

    bool running = true;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            ImGui_ImplSDL2_ProcessEvent(&event);
            if (event.type == SDL_QUIT) {
                running = false;
            }
        }

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplSDL2_NewFrame();
        ImGui::NewFrame();

        ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
        ImGui::SetNextWindowSize(ImGui::GetIO().DisplaySize, ImGuiCond_Always);
        ImGui::Begin("Recipe Manager", nullptr,
                     ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoCollapse);

        ImGui::BeginChild("RecipeList", ImVec2(250, 0), true);
        ImGui::Text("Recipes");
        ImGui::Text("Search recipes:");
        ImGui::InputTextWithHint("##search", "Type to filter recipes...", search_buf,
                               sizeof(search_buf));
        ImGui::Separator();
        std::string query = to_lower(search_buf);
        for (int i = 0; i < static_cast<int>(recipes.size()); ++i) {
            const Recipe& recipe = recipes[i];
            if (!query.empty() && to_lower(recipe.title).find(query) == std::string::npos) {
                continue;
            }
            if (ImGui::Selectable(recipe.title.c_str(), selected == i)) {
                selected = i;
            }
        }
        ImGui::EndChild();

        ImGui::SameLine();

        ImGui::BeginChild("RecipeDetail", ImVec2(0, 0), true);
        if (selected >= 0 && selected < static_cast<int>(recipes.size())) {
            const Recipe& recipe = recipes[selected];
            ImGui::Text("%s", recipe.title.c_str());
            ImGui::TextWrapped("%s", recipe.description.c_str());
            ImGui::Text("Servings: %d  |  Prep: %d min  |  Cook: %d min",
                        recipe.servings, recipe.prep_minutes, recipe.cook_minutes);
            ImGui::Separator();
            ImGui::Text("[No image yet]");
            ImGui::Separator();

            ImGui::Text("Ingredients");
            for (const Ingredient& ingredient : recipe.ingredients) {
                if (ingredient.unit.empty()) {
                    ImGui::BulletText("%s %s", ingredient.amount.c_str(),
                                      ingredient.name.c_str());
                } else {
                    ImGui::BulletText("%s %s %s", ingredient.amount.c_str(),
                                      ingredient.unit.c_str(), ingredient.name.c_str());
                }
            }
            ImGui::Separator();

            ImGui::Text("Steps");
            for (int i = 0; i < static_cast<int>(recipe.steps.size()); ++i) {
                ImGui::Text("%d. %s", i + 1, recipe.steps[i].c_str());
            }
            ImGui::Separator();

            ImGui::Text("Notes");
            ImGui::TextWrapped("%s", recipe.notes.c_str());
        } else {
            ImGui::Text("No recipe selected.");
        }
        ImGui::EndChild();

        ImGui::End();

        ImGui::Render();
        glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        SDL_GL_SwapWindow(window);
    }

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    ImGui::DestroyContext();
    SDL_GL_DeleteContext(gl_context);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
