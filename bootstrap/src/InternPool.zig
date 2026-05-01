const std = @import("std");

pub const Index = u32;

pub const InternPool = struct {
    pub const well_known = struct {
        pub const void_type: Index = 0;
        pub const bool_type: Index = 1;
        pub const s8_type: Index = 2;
        pub const s16_type: Index = 3;
        pub const s32_type: Index = 4;
        pub const s64_type: Index = 5;
        pub const s128_type: Index = 6;
        pub const u8_type: Index = 7;
        pub const u16_type: Index = 8;
        pub const u32_type: Index = 9;
        pub const u64_type: Index = 10;
        pub const u128_type: Index = 11;
        pub const float32_type: Index = 12;
        pub const float64_type: Index = 13;
        pub const string_type: Index = 14;
        pub const type_type: Index = 15;
        pub const any_type: Index = 16;
    };

    allocator: std.mem.Allocator,
    keys: std.ArrayList(Key) = .empty,
    strings: std.ArrayList([]const u8) = .empty,

    pub const Key = union(enum) {
        type_void,
        type_bool,
        type_int: IntType,
        type_float: u16,
        type_string,
        type_type,
        type_any,
        value_string: u32,
        value_int: i128,
        value_bool: bool,
    };

    pub const IntType = struct { signed: bool, bits: u16 };

    pub fn init(allocator: std.mem.Allocator) !InternPool {
        var ip = InternPool{ .allocator = allocator };
        errdefer ip.deinit();
        try ip.seed();
        return ip;
    }

    pub fn deinit(ip: *InternPool) void {
        for (ip.strings.items) |s| ip.allocator.free(s);
        ip.strings.deinit(ip.allocator);
        ip.keys.deinit(ip.allocator);
    }

    fn seed(ip: *InternPool) !void {
        try ip.keys.appendSlice(ip.allocator, &.{
            .type_void,
            .type_bool,
            .{ .type_int = .{ .signed = true, .bits = 8 } },
            .{ .type_int = .{ .signed = true, .bits = 16 } },
            .{ .type_int = .{ .signed = true, .bits = 32 } },
            .{ .type_int = .{ .signed = true, .bits = 64 } },
            .{ .type_int = .{ .signed = true, .bits = 128 } },
            .{ .type_int = .{ .signed = false, .bits = 8 } },
            .{ .type_int = .{ .signed = false, .bits = 16 } },
            .{ .type_int = .{ .signed = false, .bits = 32 } },
            .{ .type_int = .{ .signed = false, .bits = 64 } },
            .{ .type_int = .{ .signed = false, .bits = 128 } },
            .{ .type_float = 32 },
            .{ .type_float = 64 },
            .type_string,
            .type_type,
            .type_any,
        });
    }

    pub fn key(ip: *const InternPool, idx: Index) Key { return ip.keys.items[idx]; }

    pub fn internStringValue(ip: *InternPool, value: []const u8) !Index {
        const owned = try ip.allocator.dupe(u8, value);
        errdefer ip.allocator.free(owned);
        const string_idx: u32 = @intCast(ip.strings.items.len);
        try ip.strings.append(ip.allocator, owned);
        const idx: Index = @intCast(ip.keys.items.len);
        try ip.keys.append(ip.allocator, .{ .value_string = string_idx });
        return idx;
    }
};

test "well known types are stable" {
    var ip = try InternPool.init(std.testing.allocator);
    defer ip.deinit();
    try std.testing.expectEqual(InternPool.Key.type_void, ip.key(InternPool.well_known.void_type));
    try std.testing.expectEqual(InternPool.Key.type_string, ip.key(InternPool.well_known.string_type));
}
