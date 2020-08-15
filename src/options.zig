pub const Options = struct {
    pub const Render = struct {
        hard_breaks: bool = false,
    };

    render: Render = .{},
};
