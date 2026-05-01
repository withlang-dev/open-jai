const std = @import("std");
const Index = @import("InternPool.zig").Index;

pub const Value = struct {
    index: Index,

    pub fn init(index: Index) Value { return .{ .index = index }; }

    pub fn toInteger(v: Value) !i128 {
        _ = v;
        return error.NotInteger;
    }

    pub fn toString(v: Value) ![]const u8 {
        _ = v;
        return error.NotString;
    }
};
