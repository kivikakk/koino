pub fn isLineEndChar(ch: u8) bool {
    return switch (ch) {
        10, 13 => true,
        else => false,
    };
}
