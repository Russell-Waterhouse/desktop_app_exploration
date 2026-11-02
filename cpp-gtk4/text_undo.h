// Per-field undo/redo for the add/edit form's text widgets.
//
// GTK4's GtkEntry and GtkTextView have no built-in undo, so the
// form keeps one TextUndo per text widget. This class knows
// nothing about GTK: the form records the widget's text after
// each change and applies the snapshot undo() or redo() returns.
//
// A snapshot holds the text plus the cursor as a CHARACTER
// offset, not a byte offset: that is what GtkEditable positions
// and GtkTextIter offsets count, so the GTK glue passes the
// values straight through for both widget kinds.
//
// Typing runs coalesce: changes less than kCoalesceMs apart do
// not add a new undo step, so one Ctrl+Z undoes a run of typing
// instead of a single character. A change after an undo clears
// the redo stack, as usual. While the form is applying an
// undo/redo snapshot, it sets applying so the change signal
// that fires does not record the application as a new edit.

#pragma once

#include <chrono>
#include <optional>
#include <string>
#include <vector>

struct TextSnapshot {
    std::string text;
    int cursor = 0;  // Character offset, not bytes.
};

class TextUndo {
  public:
    // Longest gap between two changes that still counts as one
    // typing run for undo purposes.
    static constexpr int kCoalesceMs = 1000;

    // The widget's initial contents. Clears both stacks.
    void seed(const std::string& text, int cursor) {
        last_ = TextSnapshot{text, cursor};
        undo_stack_.clear();
        redo_stack_.clear();
        can_coalesce_ = false;
        applying_ = false;
    }

    // Record the widget's text after a change. Cursor-only moves
    // never reach this (the change signal fires on text changes),
    // but a record with unchanged text still refreshes the cursor.
    void record(const std::string& text, int cursor) {
        if (applying_) {
            return;
        }
        if (text == last_.text) {
            last_.cursor = cursor;
            return;
        }
        const auto now = clock::now();
        const bool coalesce =
            can_coalesce_ &&
            std::chrono::duration_cast<std::chrono::milliseconds>(now -
                                                                  last_time_)
                    .count() < kCoalesceMs;
        if (!coalesce) {
            undo_stack_.push_back(last_);
        }
        // When coalescing, the stack top already holds the state
        // from before the typing run; leave it alone.
        redo_stack_.clear();
        last_ = TextSnapshot{text, cursor};
        last_time_ = now;
        can_coalesce_ = true;
    }

    // The snapshot to restore, or nothing when there is no step.
    // Takes the widget's current contents so redo can return to
    // them. Also refreshes the last-recorded state, so a later
    // record is a new step rather than a continuation of the
    // undone run.
    std::optional<TextSnapshot> undo(const std::string& text, int cursor) {
        if (undo_stack_.empty()) {
            return std::nullopt;
        }
        redo_stack_.push_back(TextSnapshot{text, cursor});
        TextSnapshot snapshot = undo_stack_.back();
        undo_stack_.pop_back();
        last_ = snapshot;
        last_time_ = clock::now();
        can_coalesce_ = false;
        return snapshot;
    }

    std::optional<TextSnapshot> redo(const std::string& text, int cursor) {
        if (redo_stack_.empty()) {
            return std::nullopt;
        }
        undo_stack_.push_back(TextSnapshot{text, cursor});
        TextSnapshot snapshot = redo_stack_.back();
        redo_stack_.pop_back();
        last_ = snapshot;
        last_time_ = clock::now();
        can_coalesce_ = false;
        return snapshot;
    }

    // Set while the form applies a snapshot, so the resulting
    // change signal is not recorded as a new edit.
    void set_applying(bool applying) { applying_ = applying; }

    bool can_undo() const { return !undo_stack_.empty(); }
    bool can_redo() const { return !redo_stack_.empty(); }

  private:
    using clock = std::chrono::steady_clock;

    TextSnapshot last_;
    std::vector<TextSnapshot> undo_stack_;
    std::vector<TextSnapshot> redo_stack_;
    clock::time_point last_time_ = clock::now();
    bool can_coalesce_ = false;
    bool applying_ = false;
};
