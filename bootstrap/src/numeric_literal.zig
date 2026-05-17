const std = @import("std");

pub const Error = error{
    Empty,
    InvalidBasePrefix,
    MissingDigits,
    InvalidDigit,
    InvalidUnderscore,
    InvalidExponent,
    InvalidSuffix,
    Overflow,
};

pub const Kind = enum {
    integer,
    float,
    bit_pattern,
};

pub const Parsed = union(Kind) {
    integer: Integer,
    float: Float,
    bit_pattern: BitPattern,
};

pub const Integer = struct {
    value: u128,
    base: u8,
};

pub const Float = struct {
    value: f64,
};

pub const BitPattern = struct {
    bits: u64,
    hex_digits: u8,

    pub fn inferredFloatBits(p: BitPattern) u16 {
        return if (p.hex_digits <= 8) 32 else 64;
    }
};

pub fn parse(raw: []const u8) Error!Parsed {
    if (raw.len == 0) return error.Empty;
    if (isBitPattern(raw)) return .{ .bit_pattern = try parseBitPattern(raw) };
    if (isBasedInteger(raw, 'x') or isBasedInteger(raw, 'X')) return .{ .integer = try parseInteger(raw, 16, 2) };
    if (isBasedInteger(raw, 'b') or isBasedInteger(raw, 'B')) return .{ .integer = try parseInteger(raw, 2, 2) };
    if (looksFloat(raw)) return .{ .float = .{ .value = try parseDecimalFloat(raw) } };
    return .{ .integer = try parseInteger(raw, 10, 0) };
}

pub fn classify(raw: []const u8) Error!Kind {
    return switch (try parse(raw)) {
        .integer => .integer,
        .float => .float,
        .bit_pattern => .bit_pattern,
    };
}

pub fn parseInt(raw: []const u8) Error!i64 {
    return switch (try parse(raw)) {
        .integer => |v| if (v.value <= @as(u128, std.math.maxInt(u64)))
            @bitCast(@as(u64, @intCast(v.value)))
        else
            error.Overflow,
        .bit_pattern => |v| @bitCast(v.bits),
        .float => error.InvalidDigit,
    };
}

pub fn parseFloat(raw: []const u8, target_bits: ?u16) Error!f64 {
    return switch (try parse(raw)) {
        .float => |v| v.value,
        .integer => |v| @floatFromInt(v.value),
        .bit_pattern => |v| bitPatternToFloat(v, target_bits),
    };
}

pub fn isBitPattern(raw: []const u8) bool {
    return raw.len >= 2 and raw[0] == '0' and (raw[1] == 'h' or raw[1] == 'H');
}

pub fn bitPatternInfo(raw: []const u8) Error!?BitPattern {
    if (!isBitPattern(raw)) return null;
    return try parseBitPattern(raw);
}

pub fn bitPatternToFloat(pattern: BitPattern, target_bits: ?u16) Error!f64 {
    const bits = target_bits orelse pattern.inferredFloatBits();
    return switch (bits) {
        32 => {
            if (pattern.bits > std.math.maxInt(u32)) return error.Overflow;
            const as_f32: f32 = @bitCast(@as(u32, @intCast(pattern.bits)));
            return @floatCast(as_f32);
        },
        64 => @bitCast(pattern.bits),
        else => error.InvalidSuffix,
    };
}

fn parseBitPattern(raw: []const u8) Error!BitPattern {
    var value: u64 = 0;
    var digits: u8 = 0;
    var prev_underscore = false;
    if (raw.len <= 2) return error.MissingDigits;
    for (raw[2..], 2..) |c, i| {
        if (c == '_') {
            if (i == 2 or prev_underscore) return error.InvalidUnderscore;
            prev_underscore = true;
            continue;
        }
        const digit = hexDigit(c) orelse return error.InvalidDigit;
        if (digits == 16) return error.Overflow;
        value = (value << 4) | digit;
        digits += 1;
        prev_underscore = false;
    }
    if (digits == 0) return error.MissingDigits;
    if (prev_underscore) return error.InvalidUnderscore;
    return .{ .bits = value, .hex_digits = digits };
}

fn parseInteger(raw: []const u8, base: u8, start: usize) Error!Integer {
    var value: u128 = 0;
    var digits: usize = 0;
    var prev_underscore = false;
    if (raw.len <= start) return error.MissingDigits;
    for (raw[start..], start..) |c, i| {
        if (c == '_') {
            if (i == start or prev_underscore) return error.InvalidUnderscore;
            prev_underscore = true;
            continue;
        }
        const digit = digitValue(c) orelse return error.InvalidDigit;
        if (digit >= base) return error.InvalidDigit;
        value = std.math.mul(u128, value, base) catch return error.Overflow;
        value = std.math.add(u128, value, digit) catch return error.Overflow;
        digits += 1;
        prev_underscore = false;
    }
    if (digits == 0) return error.MissingDigits;
    if (prev_underscore) return error.InvalidUnderscore;
    return .{ .value = value, .base = base };
}

fn parseDecimalFloat(raw: []const u8) Error!f64 {
    var cleaned: [256]u8 = undefined;
    if (raw.len > cleaned.len) return error.Overflow;
    var len: usize = 0;
    var prev_underscore = false;
    var saw_digit = false;
    var exp_seen = false;
    var exp_digits: usize = 0;
    for (raw, 0..) |c, i| {
        if (c == '_') {
            if (i == 0 or prev_underscore) return error.InvalidUnderscore;
            prev_underscore = true;
            continue;
        }
        if (std.ascii.isDigit(c)) {
            saw_digit = true;
            if (exp_seen) exp_digits += 1;
        } else if (c == 'e' or c == 'E') {
            if (exp_seen) return error.InvalidExponent;
            exp_seen = true;
            exp_digits = 0;
        } else if (c == '+' or c == '-') {
            if (i == 0) return error.InvalidDigit;
            const prev = raw[i - 1];
            if (prev != 'e' and prev != 'E') return error.InvalidDigit;
        } else if (c != '.') {
            return error.InvalidDigit;
        }
        cleaned[len] = c;
        len += 1;
        prev_underscore = false;
    }
    if (!saw_digit) return error.MissingDigits;
    if (prev_underscore) return error.InvalidUnderscore;
    if (exp_seen and exp_digits == 0) return error.InvalidExponent;
    return std.fmt.parseFloat(f64, cleaned[0..len]) catch error.InvalidDigit;
}

fn looksFloat(raw: []const u8) bool {
    return std.mem.indexOfScalar(u8, raw, '.') != null or
        std.mem.indexOfScalar(u8, raw, 'e') != null or
        std.mem.indexOfScalar(u8, raw, 'E') != null;
}

fn isBasedInteger(raw: []const u8, marker: u8) bool {
    return raw.len >= 2 and raw[0] == '0' and raw[1] == marker;
}

fn digitValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'z' => 10 + c - 'a',
        'A'...'Z' => 10 + c - 'A',
        else => null,
    };
}

fn hexDigit(c: u8) ?u64 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + c - 'a',
        'A'...'F' => 10 + c - 'A',
        else => null,
    };
}

test "numeric literal parses integer bases and underscores" {
    try std.testing.expectEqual(@as(i64, 255), try parseInt("0xff"));
    try std.testing.expectEqual(@as(i64, 5), try parseInt("0b0101"));
    try std.testing.expectEqual(@as(i64, 1_000_000), try parseInt("1_000_000"));
    try std.testing.expectError(error.InvalidUnderscore, parseInt("1_"));
}

test "numeric literal parses hex bit-pattern floats" {
    const one = try parseFloat("0h3f80_0000", 32);
    try std.testing.expectEqual(@as(f64, 1.0), one);
    const neg_zero = try parseFloat("0h8000_0000_0000_0000", 64);
    try std.testing.expect(std.math.signbit(neg_zero));
    const info = (try bitPatternInfo("0h7fbf_ffff")).?;
    try std.testing.expectEqual(@as(u16, 32), info.inferredFloatBits());
}
