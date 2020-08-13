pub fn isLineEndChar(ch: u8) bool {
    return switch (ch) {
        '\n', '\r' => true,
        else => false,
    };
}

pub fn isSpaceOrTab(ch: u8) bool {
    return switch (ch) {
        ' ', '\t' => true,
        else => false,
    };
}
