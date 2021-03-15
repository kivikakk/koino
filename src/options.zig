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
        /// when anchors are enabled, render this icon in front of each heading so people can click it
        anchor_icon: []const u8 = "",
    };

    extensions: Extensions = .{},
    parse: Parse = .{},
    render: Render = .{},
};
