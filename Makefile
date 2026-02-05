all:
	zig build run

test:
	zig build test

spec:
	zig build
	cd vendor/cmark-gfm/test && python3 spec_tests.py --program=../../../zig-out/bin/koino

fetch-clap:
	zig fetch --save https://github.com/Hejsil/zig-clap/archive/refs/tags/0.11.0.tar.gz

fetch-htmlentities:
	zig fetch --save git+https://nossa.ee/~talya/htmlentities.zig

fetch-libpcre:
	zig fetch --save git+https://nossa.ee/~talya/libpcre.zig

fetch-zunicode:
	zig fetch --save git+https://github.com/mishieck/zunicode

example:
	zig build example
