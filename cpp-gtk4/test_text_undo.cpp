// Unit tests for the per-field undo/redo helper (text_undo.h).
//
// Plain checks only: no test framework, no GTK, so this builds
// with plain g++ anywhere the app sources are present:
//   g++ -std=c++17 -Wall -Wextra test_text_undo.cpp -o /tmp/test_text_undo
//   /tmp/test_text_undo
// Exit code is 0 only when every check passes; each failure is
// printed and the run continues so all failures are visible.

#include "text_undo.h"

#include <chrono>
#include <iostream>
#include <string>
#include <thread>

namespace {

int failures = 0;
int checks = 0;

void check(bool condition, const std::string& what) {
    ++checks;
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << what << "\n";
    }
}

void check_snapshot(const std::optional<TextSnapshot>& snapshot,
                    const std::string& text, int cursor,
                    const std::string& what) {
    check(snapshot.has_value(), what + " (expected a snapshot)");
    if (snapshot.has_value()) {
        check(snapshot->text == text, what + " (text)");
        check(snapshot->cursor == cursor, what + " (cursor)");
    }
}

}  // namespace

int main() {
    {
        // A quick typing run is one undo step, not one per key.
        TextUndo undo;
        undo.seed("", 0);
        undo.record("H", 1);
        undo.record("He", 2);
        undo.record("Hel", 3);
        check(undo.can_undo(), "typing run: can undo");
        check_snapshot(undo.undo("Hel", 3), "", 0, "typing run: undo");
        check(!undo.can_undo(), "typing run: one step only");
        check_snapshot(undo.redo("", 0), "Hel", 3, "typing run: redo");
    }
    {
        // Changes separated by more than the coalesce window are
        // separate steps.
        TextUndo undo;
        undo.seed("", 0);
        undo.record("H", 1);
        std::this_thread::sleep_for(
            std::chrono::milliseconds(TextUndo::kCoalesceMs + 100));
        undo.record("He", 2);
        check_snapshot(undo.undo("He", 2), "H", 1, "slow typing: undo 1");
        check_snapshot(undo.undo("H", 1), "", 0, "slow typing: undo 2");
    }
    {
        // Empty stacks report nothing to undo or redo.
        TextUndo undo;
        undo.seed("abc", 3);
        check(!undo.undo("abc", 3).has_value(), "fresh: no undo");
        check(!undo.redo("abc", 3).has_value(), "fresh: no redo");
    }
    {
        // A new edit after an undo clears the redo stack, and the
        // edit itself becomes a fresh undo step.
        TextUndo undo;
        undo.seed("", 0);
        undo.record("a", 1);
        check_snapshot(undo.undo("a", 1), "", 0, "redo-clear: undo");
        check(undo.can_redo(), "redo-clear: redo available");
        undo.record("b", 1);
        check(!undo.can_redo(), "redo-clear: redo cleared by edit");
        check_snapshot(undo.undo("b", 1), "", 0, "redo-clear: undo new edit");
    }
    {
        // Cursor positions ride along with the text.
        TextUndo undo;
        undo.seed("hello", 5);
        undo.record("hell", 4);
        check_snapshot(undo.undo("hell", 4), "hello", 5,
                       "cursor: restored with text");
    }
    {
        // Recording the unchanged text adds no step, and changes
        // applied while applying a snapshot are ignored.
        TextUndo undo;
        undo.seed("x", 1);
        undo.record("x", 1);
        check(!undo.can_undo(), "unchanged: no step");
        undo.set_applying(true);
        undo.record("y", 1);
        undo.set_applying(false);
        check(!undo.can_undo(), "applying: no step");
    }
    {
        // Redo chains back through multiple undos.
        TextUndo undo;
        undo.seed("", 0);
        undo.record("a", 1);
        std::this_thread::sleep_for(
            std::chrono::milliseconds(TextUndo::kCoalesceMs + 100));
        undo.record("ab", 2);
        undo.undo("ab", 2);
        undo.undo("a", 1);
        check_snapshot(undo.redo("", 0), "a", 1, "redo chain: step 1");
        check_snapshot(undo.redo("a", 1), "ab", 2, "redo chain: step 2");
        check(!undo.can_redo(), "redo chain: exhausted");
    }

    if (failures != 0) {
        std::cerr << failures << " of " << checks << " checks failed\n";
        return 1;
    }
    std::cout << "all " << checks << " text-undo checks passed\n";
    return 0;
}
