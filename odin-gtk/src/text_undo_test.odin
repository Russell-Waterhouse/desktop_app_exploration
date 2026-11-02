package main

import "core:testing"
import "core:time"

// Undo/redo semantics under test (src/text_undo.odin):
// quick typing runs coalesce into one step, slow changes are
// separate steps, a new edit after an undo clears redo,
// cursors ride along with the text, and unchanged text or
// changes applied while applying add no step.

@(test)
test_undo_typing_run_is_one_step :: proc(t: ^testing.T) {
	u: TextUndo
	defer text_undo_destroy(&u)
	text_undo_seed(&u, "", 0)
	text_undo_record(&u, "H", 1)
	text_undo_record(&u, "He", 2)
	text_undo_record(&u, "Hel", 3)
	testing.expect(t, text_undo_can_undo(&u))
	snap, ok := text_undo_undo(&u, "Hel", 3)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect_value(t, snap.text, "")
	testing.expect_value(t, snap.cursor, 0)
	testing.expect(t, !text_undo_can_undo(&u))
	snap, ok = text_undo_redo(&u, "", 0)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect_value(t, snap.text, "Hel")
	testing.expect_value(t, snap.cursor, 3)
}

@(test)
test_undo_slow_typing_is_separate_steps :: proc(t: ^testing.T) {
	u: TextUndo
	defer text_undo_destroy(&u)
	text_undo_seed(&u, "", 0)
	text_undo_record(&u, "H", 1)
	time.sleep((TEXT_UNDO_COALESCE_MS + 100) * time.Millisecond)
	text_undo_record(&u, "He", 2)
	snap, ok := text_undo_undo(&u, "He", 2)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect_value(t, snap.text, "H")
	testing.expect_value(t, snap.cursor, 1)
	snap, ok = text_undo_undo(&u, "H", 1)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect_value(t, snap.text, "")
	testing.expect_value(t, snap.cursor, 0)
}

@(test)
test_undo_fresh_has_no_steps :: proc(t: ^testing.T) {
	u: TextUndo
	defer text_undo_destroy(&u)
	text_undo_seed(&u, "abc", 3)
	_, ok := text_undo_undo(&u, "abc", 3)
	testing.expect(t, !ok)
	_, ok = text_undo_redo(&u, "abc", 3)
	testing.expect(t, !ok)
}

@(test)
test_undo_edit_after_undo_clears_redo :: proc(t: ^testing.T) {
	u: TextUndo
	defer text_undo_destroy(&u)
	text_undo_seed(&u, "", 0)
	text_undo_record(&u, "a", 1)
	snap, ok := text_undo_undo(&u, "a", 1)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect(t, text_undo_can_redo(&u))
	text_undo_record(&u, "b", 1)
	testing.expect(t, !text_undo_can_redo(&u))
	snap, ok = text_undo_undo(&u, "b", 1)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect_value(t, snap.text, "")
}

@(test)
test_undo_cursor_restored_with_text :: proc(t: ^testing.T) {
	u: TextUndo
	defer text_undo_destroy(&u)
	text_undo_seed(&u, "hello", 5)
	text_undo_record(&u, "hell", 4)
	snap, ok := text_undo_undo(&u, "hell", 4)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect_value(t, snap.text, "hello")
	testing.expect_value(t, snap.cursor, 5)
}

@(test)
test_undo_unchanged_and_applying_add_no_step :: proc(t: ^testing.T) {
	u: TextUndo
	defer text_undo_destroy(&u)
	text_undo_seed(&u, "x", 1)
	text_undo_record(&u, "x", 1)
	testing.expect(t, !text_undo_can_undo(&u))
	text_undo_set_applying(&u, true)
	text_undo_record(&u, "y", 1)
	text_undo_set_applying(&u, false)
	testing.expect(t, !text_undo_can_undo(&u))
}

@(test)
test_undo_redo_chains_back :: proc(t: ^testing.T) {
	u: TextUndo
	defer text_undo_destroy(&u)
	text_undo_seed(&u, "", 0)
	text_undo_record(&u, "a", 1)
	time.sleep((TEXT_UNDO_COALESCE_MS + 100) * time.Millisecond)
	text_undo_record(&u, "ab", 2)
	snap, ok := text_undo_undo(&u, "ab", 2)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	snap, ok = text_undo_undo(&u, "a", 1)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	snap, ok = text_undo_redo(&u, "", 0)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect_value(t, snap.text, "a")
	testing.expect_value(t, snap.cursor, 1)
	snap, ok = text_undo_redo(&u, "a", 1)
	defer snapshot_delete(snap)
	testing.expect(t, ok)
	testing.expect_value(t, snap.text, "ab")
	testing.expect_value(t, snap.cursor, 2)
	testing.expect(t, !text_undo_can_redo(&u))
}
