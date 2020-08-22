pub const Options = struct {
    pub const Parse = struct {
        smart: bool = false,
    };
    pub const Render = struct {
        hard_breaks: bool = false,
        unsafe: bool = false,
    };

    parse: Parse = .{},
    render: Render = .{},
};
