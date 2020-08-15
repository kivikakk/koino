all:
	zig build run

test:
	zig build test

spec:
	zig build
	cd vendor/cmark-gfm/test && python3 spec_tests.py --program=../../../zig-cache/bin/koino
