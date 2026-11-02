package main

import "core:strings"
import "core:time"

// Per-field undo/redo for the add/edit form's text widgets.
//
// GTK4's GtkEntry and GtkTextView have no built-in undo, so the
// form keeps one TextUndo per text widget. This file knows
// nothing about GTK: the form records the widget's text after
// each change and applies the snapshot undo() or redo()
// returns.
//
// A snapshot holds the text plus the cursor as a CHARACTER
// offset, not a byte offset: that is what GtkEditable
// positions and GtkTextIter offsets count, so the GTK glue
// passes the values straight through for both widget kinds.
//
// Typing runs coalesce: changes less than
// TEXT_UNDO_COALESCE_MS apart do not add a new undo step, so
// one Ctrl+Z undoes a run of typing instead of a single
// character. A change after an undo clears the redo stack, as
// usual. While the form is applying an undo/redo snapshot, it
// sets applying so the change signal that fires does not
// record the application as a new edit.
//
// Ownership: every string the struct holds is a clone, and
// undo()/redo() return a fresh clone the caller owns (free
// it after applying). The struct's own copies are freed by
// text_undo_destroy or replaced by seed()/record().

TextSnapshot :: struct {
	text:   string,
	cursor: int, // Character offset, not bytes.
}

// Longest gap between two changes that still counts as one
// typing run for undo purposes, in milliseconds.
TEXT_UNDO_COALESCE_MS :: 1000

TextUndo :: struct {
	last:         TextSnapshot,
	undo_stack:   [dynamic]TextSnapshot,
	redo_stack:   [dynamic]TextSnapshot,
	last_time:    time.Time,
	can_coalesce: bool,
	applying:     bool,
}

snapshot_clone :: proc(s: TextSnapshot) -> TextSnapshot {
	return TextSnapshot{text = strings.clone(s.text), cursor = s.cursor}
}

// Empty strings are never heap-backed here (zero values and
// clones of "" both have nil data), and deleting one is a bad
// free under the tracking allocator, so only non-empty
// strings are freed. Every non-empty string the struct holds
// is a clone, so freeing it is always valid.
snapshot_delete :: proc(s: TextSnapshot) {
	if len(s.text) > 0 {
		delete(s.text)
	}
}

clear_snapshots :: proc(stack: ^[dynamic]TextSnapshot) {
	for s in stack {
		snapshot_delete(s)
	}
	clear(stack)
}

// The widget's initial contents. Clears both stacks.
text_undo_seed :: proc(u: ^TextUndo, text: string, cursor: int) {
	clear_snapshots(&u.undo_stack)
	clear_snapshots(&u.redo_stack)
	snapshot_delete(u.last)
	u.last = TextSnapshot{text = strings.clone(text), cursor = cursor}
	u.can_coalesce = false
	u.applying = false
}

// Record the widget's text after a change. A record with
// unchanged text still refreshes the cursor.
text_undo_record :: proc(u: ^TextUndo, text: string, cursor: int) {
	if u.applying {
		return
	}
	if text == u.last.text {
		u.last.cursor = cursor
		return
	}
	now := time.now()
	coalesce := u.can_coalesce &&
		time.diff(u.last_time, now) < TEXT_UNDO_COALESCE_MS * time.Millisecond
	if !coalesce {
		append(&u.undo_stack, snapshot_clone(u.last))
	}
	// When coalescing, the stack top already holds the state
	// from before the typing run; leave it alone.
	clear_snapshots(&u.redo_stack)
	snapshot_delete(u.last)
	u.last = TextSnapshot{text = strings.clone(text), cursor = cursor}
	u.last_time = now
	u.can_coalesce = true
}

// The snapshot to restore, or ok=false when there is no
// step. Takes the widget's current contents so redo can
// return to them. Also refreshes the last-recorded state, so
// a later record is a new step rather than a continuation of
// the undone run.
text_undo_undo :: proc(
	u: ^TextUndo,
	text: string,
	cursor: int,
) -> (
	snapshot: TextSnapshot,
	ok: bool,
) {
	if len(u.undo_stack) == 0 {
		return {}, false
	}
	append(
		&u.redo_stack,
		TextSnapshot{text = strings.clone(text), cursor = cursor},
	)
	popped := pop(&u.undo_stack)
	snapshot_delete(u.last)
	u.last = popped
	u.last_time = time.now()
	u.can_coalesce = false
	return snapshot_clone(popped), true
}

text_undo_redo :: proc(
	u: ^TextUndo,
	text: string,
	cursor: int,
) -> (
	snapshot: TextSnapshot,
	ok: bool,
) {
	if len(u.redo_stack) == 0 {
		return {}, false
	}
	append(
		&u.undo_stack,
		TextSnapshot{text = strings.clone(text), cursor = cursor},
	)
	popped := pop(&u.redo_stack)
	snapshot_delete(u.last)
	u.last = popped
	u.last_time = time.now()
	u.can_coalesce = false
	return snapshot_clone(popped), true
}

// Set while the form applies a snapshot, so the resulting
// change signal is not recorded as a new edit.
text_undo_set_applying :: proc(u: ^TextUndo, applying: bool) {
	u.applying = applying
}

text_undo_can_undo :: proc(u: ^TextUndo) -> bool {
	return len(u.undo_stack) > 0
}

text_undo_can_redo :: proc(u: ^TextUndo) -> bool {
	return len(u.redo_stack) > 0
}

text_undo_destroy :: proc(u: ^TextUndo) {
	clear_snapshots(&u.undo_stack)
	clear_snapshots(&u.redo_stack)
	snapshot_delete(u.last)
	u^ = TextUndo{}
}
