// Dear ImGui recipe view, using SDL2 + OpenGL3 as the backend.
// SDL is the windowing/drawing backend here; Dear ImGui is the UI layer.
//
// Recipes are loaded from SQLite (recipes.db in the current
// working directory), seeded on first run. See db.h / db.cpp.
#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#include <SDL.h>
#include <SDL_opengl.h>

#include "db.h"
#include "imgui.h"
#include "imgui_impl_opengl3.h"
#include "imgui_impl_sdl2.h"

std::string to_lower(const std::string& text) {
    std::string lowered = text;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    return lowered;
}

int main(int, char**) {
    // Load from SQLite first. On failure the app still opens and
    // shows the error in the detail pane instead of crashing.
    std::vector<Recipe> recipes;
    std::string db_error;
    sqlite3* db = nullptr;
    if (!open_database("recipes.db", &db, db_error) ||
        !init_and_seed(db, db_error) || !load_recipes(db, recipes, db_error)) {
        if (db != nullptr) {
            sqlite3_close(db);
            db = nullptr;
        }
    }

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        if (db != nullptr) {
            sqlite3_close(db);
        }
        return 1;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

    SDL_Window* window = SDL_CreateWindow(
        "Recipe Manager", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 900, 600,
        SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
    if (window == nullptr) {
        if (db != nullptr) {
            sqlite3_close(db);
        }
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
        if (!db_error.empty()) {
            ImGui::Text("Database error:");
            ImGui::TextWrapped("%s", db_error.c_str());
        } else if (selected >= 0 && selected < static_cast<int>(recipes.size())) {
            const Recipe& recipe = recipes[selected];
            ImGui::Text("%s", recipe.title.c_str());
            ImGui::TextWrapped("%s", recipe.description.c_str());
            ImGui::Text("Servings: %d", recipe.servings);
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
    if (db != nullptr) {
        sqlite3_close(db);
    }
    return 0;
}
