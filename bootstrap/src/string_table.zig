const std = @import("std");

pub const StringIndex = u32;

pub const StringTable = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    offsets: std.ArrayList(Offset) = .empty,
    map: std.StringHashMapUnmanaged(StringIndex) = .empty,

    const Offset = struct { start: u32, len: u32 };

    pub fn init(allocator: std.mem.Allocator) StringTable {
        return .{ .allocator = allocator };
    }

    pub fn deinit(st: *StringTable) void {
        st.bytes.deinit(st.allocator);
        st.offsets.deinit(st.allocator);
        st.map.deinit(st.allocator);
    }

    pub fn intern(st: *StringTable, text: []const u8) !StringIndex {
        if (st.map.get(text)) |idx| return idx;
        const start = st.bytes.items.len;
        try st.bytes.appendSlice(st.allocator, text);
        const stored = st.bytes.items[start..][0..text.len];
        const idx: StringIndex = @intCast(st.offsets.items.len);
        try st.offsets.append(st.allocator, .{ .start = @intCast(start), .len = @intCast(text.len) });
        try st.map.put(st.allocator, stored, idx);
        return idx;
    }

    pub fn get(st: *const StringTable, idx: StringIndex) []const u8 {
        const off = st.offsets.items[idx];
        return st.bytes.items[off.start..][0..off.len];
    }
};

test "string table deduplicates" {
    var st = StringTable.init(std.testing.allocator);
    defer st.deinit();
    const a = try st.intern("Basic");
    const b = try st.intern("Basic");
    try std.testing.expectEqual(a, b);
    try std.testing.expectEqualStrings("Basic", st.get(a));
}
