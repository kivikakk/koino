pub const Options = struct {
    pub const Extensions = struct {
        table: bool = false,
        strikethrough: bool = false,
        autolink: bool = false,
        tagfilter: bool = false,
    };
    pub const Parse = struct {
        smart: bool = false,
    };
    pub const Render = struct {
        hard_breaks: bool = false,
        unsafe: bool = false,
        header_anchors: bool = false,
    };

    extensions: Extensions = .{},
    parse: Parse = .{},
    render: Render = .{},
};
