package main

import "core:os"
import "core:strings"
import "core:testing"

// copy_image_file: copies into images/, suffixes on
// collision, and reports a missing source as an error.
@(test)
test_copy_image_file_and_collision_suffix :: proc(t: ^testing.T) {
	dir := "/tmp/odin-gtk-test-images"
	os.remove_all(dir)
	defer os.remove_all(dir)
	if err := os.make_directory(dir); err != nil {
		testing.fail_now(t)
	}
	src := "/tmp/odin-gtk-test-images-src.png"
	defer os.remove(src)
	if err := os.write_entire_file(src, []byte{0x89, 'P', 'N', 'G'}); err != nil {
		testing.fail_now(t)
	}
	dest := "/tmp/odin-gtk-test-images/images"
	rel, cerr := copy_image_file(src, dest)
	testing.expect(t, cerr == "", cerr)
	testing.expect_value(t, rel, "/tmp/odin-gtk-test-images/images/odin-gtk-test-images-src.png")
	data, rerr := os.read_entire_file("/tmp/odin-gtk-test-images/images/odin-gtk-test-images-src.png", context.allocator)
	testing.expect(t, rerr == nil)
	testing.expect_value(t, len(data), 4)
	// Second copy of the same name gets _1.
	rel2, cerr2 := copy_image_file(src, dest)
	testing.expect(t, cerr2 == "", cerr2)
	testing.expect_value(t, rel2, "/tmp/odin-gtk-test-images/images/odin-gtk-test-images-src_1.png")
	// Missing source is an error, not a copy.
	_, cerr3 := copy_image_file("/tmp/odin-gtk-test-images-nope.png", dest)
	testing.expect(t, cerr3 != "")
	_ = strings.contains
}
