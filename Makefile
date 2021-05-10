all:
	zig build run

test:
	zig build test

spec:
	zig build
	temp_file=$$(mktemp); \
	(cd vendor/cmark-gfm/test && python3 spec_tests.py --program=../../../zig-out/bin/koino 2>&1) | tee $$temp_file; \
	printf "::set-output name=specs-succeeded::"; tail -n 1 $$temp_file | perl -pne '/(\d+) passed, (\d+) failed, (\d+) errored, (\d+) skipped/; $$_ = $$1'; \
	printf "\n::set-output name=spec-count::"; tail -n 1 $$temp_file | perl -pne '/(\d+) passed, (\d+) failed, (\d+) errored, (\d+) skipped/; $$_ = $$1 + $$2 + $$3 + $$4'; \
	printf "\n::set-output name=conclusion::"; tail -n 1 $$temp_file | perl -pne '/(\d+) passed, (\d+) failed, (\d+) errored, (\d+) skipped/; $$_ = ($$2 + $$3 > 0) ? "failure" : "success"'; \
	printf "\n"
