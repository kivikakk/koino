const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

pub fn Ast(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: *mem.Allocator,
        data: T,

        parent: ?*Self = null,
        prev: ?*Self = null,
        next: ?*Self = null,
        first_child: ?*Self = null,
        last_child: ?*Self = null,

        pub fn create(allocator: *mem.Allocator, data: T) !*Self {
            var obj = try allocator.create(Self);
            obj.* = .{
                .allocator = allocator,
                .data = data,
            };
            return obj;
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit(self.allocator);
            var it = self.first_child;
            while (it) |child| {
                var next = child.next;
                child.deinit();
                it = next;
            }
            self.allocator.destroy(self);
        }

        pub fn append(self: *Self, child: *Self) void {
            child.detach();
            child.parent = self;

            if (self.last_child) |last_child| {
                child.prev = last_child;
                assert(last_child.next == null);
                last_child.next = child;
            } else {
                assert(self.first_child == null);
                self.first_child = child;
            }
            self.last_child = child;
        }

        pub fn insertAfter(self: *Self, sibling: *Self) void {
            sibling.detach();
            sibling.parent = self.parent;
            sibling.prev = self;
            if (self.next) |next| {
                assert(next.prev.? == self);
                next.prev = sibling;
                sibling.next = next;
            } else if (self.parent) |parent| {
                assert(parent.last_child.? == self);
                parent.last_child = sibling;
            }
            self.next = sibling;
        }

        pub fn insertBefore(self: *Self, sibling: *Self) void {
            sibling.detach();
            sibling.parent = self.parent;
            sibling.next = self;
            if (self.prev) |prev| {
                sibling.prev = prev;
                assert(prev.next.? == self);
                prev.next = sibling;
            } else if (self.parent) |parent| {
                assert(parent.first_child.? == self);
                parent.first_child = sibling;
            }
            self.prev = sibling;
        }

        pub fn detach(self: *Self) void {
            if (self.next) |next| {
                next.prev = self.prev;
            } else if (self.parent) |parent| {
                parent.last_child = self.prev;
            }

            if (self.prev) |prev| {
                prev.next = self.next;
            } else if (self.parent) |parent| {
                parent.first_child = self.next;
            }

            self.parent = null;
            self.prev = null;
            self.next = null;
        }

        pub fn detachDeinit(self: *Self) void {
            self.detach();
            self.deinit();
        }

        pub const ReverseChildrenIterator = struct {
            next_value: ?*Self,

            pub fn next(self: *@This()) ?*Self {
                var to_return = self.next_value;
                if (to_return) |n| {
                    self.next_value = n.prev;
                }
                return to_return;
            }
        };

        pub fn reverseChildrenIterator(self: *Self) ReverseChildrenIterator {
            return .{ .next_value = self.last_child };
        }

        // These don't quite belong.

        pub fn lastChildIsOpen(self: *Self) bool {
            if (self.last_child) |n| {
                return n.data.open;
            }
            return false;
        }

        pub fn endsWithBlankLine(self: *Self) bool {
            var it: ?*Self = self;
            while (it) |cur| {
                if (cur.data.last_line_blank)
                    return true;
                switch (cur.data.value) {
                    .List, .Item => it = cur.last_child,
                    else => it = null,
                }
            }
            return false;
        }
    };
}
