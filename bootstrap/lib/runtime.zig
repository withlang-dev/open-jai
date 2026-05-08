const std = @import("std");
const c = @cImport({
    @cInclude("crt_externs.h");
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
    @cInclude("time.h");
});

export fn __openjai_print(data: [*]const u8, len: usize) void {
    writeAll(data[0..len]);
}

export fn __openjai_print_return_int(data: [*]const u8, len: usize) i64 {
    writeAll(data[0..len]);
    return @intCast(len);
}

export fn __openjai_print_int(value: i64) void {
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
    writeAll(text);
}

export fn __openjai_print_format_int(value: i64, base: i64, minimum_digits: i64) void {
    var buf: [128]u8 = undefined;
    const unsigned_value: u64 = @intCast(value);
    const digits = "0123456789abcdef";
    var tmp: [65]u8 = undefined;
    var n = unsigned_value;
    var len: usize = 0;
    const actual_base: u64 = if (base == 16) 16 else 10;
    while (true) {
        tmp[tmp.len - 1 - len] = digits[@intCast(n % actual_base)];
        len += 1;
        n /= actual_base;
        if (n == 0) break;
    }
    var out_len: usize = 0;
    const min_digits: usize = if (minimum_digits > 0) @intCast(minimum_digits) else 0;
    while (out_len + len < min_digits) : (out_len += 1) buf[out_len] = '0';
    @memcpy(buf[out_len .. out_len + len], tmp[tmp.len - len ..]);
    out_len += len;
    writeAll(buf[0..out_len]);
}

export fn __openjai_print_float(value: f64) void {
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d:.6}", .{value}) catch unreachable;
    writeFloatText(text);
}

export fn __openjai_print_format_float(value: f64, width: i64, trailing_width: i64, zero_removal: i64, mode: i64) void {
    var buf: [128]u8 = undefined;
    const precision: usize = if (trailing_width >= 0) @intCast(trailing_width) else 6;
    const text = if (mode == 1)
        std.fmt.bufPrint(&buf, "{e:.6}", .{value}) catch unreachable
    else switch (precision) {
        0 => std.fmt.bufPrint(&buf, "{d:.0}", .{value}) catch unreachable,
        1 => std.fmt.bufPrint(&buf, "{d:.1}", .{value}) catch unreachable,
        2 => std.fmt.bufPrint(&buf, "{d:.2}", .{value}) catch unreachable,
        3 => std.fmt.bufPrint(&buf, "{d:.3}", .{value}) catch unreachable,
        4 => std.fmt.bufPrint(&buf, "{d:.4}", .{value}) catch unreachable,
        5 => std.fmt.bufPrint(&buf, "{d:.5}", .{value}) catch unreachable,
        else => std.fmt.bufPrint(&buf, "{d:.6}", .{value}) catch unreachable,
    };
    _ = width;
    if (mode == 1) {
        writeScientificText(text);
    } else if (zero_removal != 0) writeFloatText(text) else writeAll(text);
}

fn writeScientificText(text: []const u8) void {
    if (std.mem.indexOfScalar(u8, text, 'e') orelse std.mem.indexOfScalar(u8, text, 'E')) |exp| {
        writeAll(text[0 .. exp + 1]);
        if (exp + 1 < text.len and text[exp + 1] != '+' and text[exp + 1] != '-') writeAll("+");
        writeAll(text[exp + 1 ..]);
        return;
    }
    writeAll(text);
}

export fn __openjai_print_bool(value: bool) void {
    writeAll(if (value) "true" else "false");
}

export fn __openjai_print_type(type_id: u64) void {
    const text = switch (type_id) {
        1 => "bool",
        5 => "s64",
        12 => "float32",
        13 => "float64",
        14 => "string",
        15 => "Type",
        16 => "Any",
        20 => "int",
        21 => "float",
        30 => "procedure (s64, s64, s64) -> s64",
        31 => "procedure ()",
        else => "<unknown type>",
    };
    writeAll(text);
}

export fn __openjai_alloc(size: usize) ?*anyopaque {
    const ptr = c.malloc(size);
    if (ptr) |p| @memset(@as([*]u8, @ptrCast(p))[0..size], 0);
    return ptr;
}

export fn __openjai_free(ptr: ?*anyopaque) void {
    c.free(ptr);
}

export fn __openjai_assert_fail() noreturn {
    writeAll("Assertion failed\n");
    std.process.exit(1);
}

export fn __openjai_memcpy(dst: ?*anyopaque, src: ?*const anyopaque, len: usize) void {
    if (len == 0) return;
    const d = dst orelse unreachable;
    const s = src orelse unreachable;
    @memcpy(@as([*]u8, @ptrCast(d))[0..len], @as([*]const u8, @ptrCast(s))[0..len]);
}

export fn __openjai_exit(status: i32) noreturn {
    std.process.exit(@intCast(status));
}

var openjai_random_state: u64 = 0x4d595df4d0f33173;

const OpenJaiCalendar = extern struct {
    year: i64,
    month_starting_at_0: i64,
    day_of_month_starting_at_0: i64,
    day_of_week_starting_at_0: i64,
    hour: i64,
    minute: i64,
    second: i64,
    millisecond: i64,
    time_zone: i64,
};

const OpenJaiRuntimeString = extern struct {
    len: usize,
    data: [*]const u8,
};

const OpenJaiArray = extern struct {
    count: usize,
    capacity: usize,
    data: ?*anyopaque,
};

fn makeRuntimeString(bytes: []const u8) ?*OpenJaiRuntimeString {
    const header_raw = c.malloc(@sizeOf(OpenJaiRuntimeString)) orelse return null;
    errdefer c.free(header_raw);
    const allocation_len = @max(bytes.len, 1);
    const data_raw = c.malloc(allocation_len) orelse return null;
    const data: [*]u8 = @ptrCast(data_raw);
    if (bytes.len != 0) @memcpy(data[0..bytes.len], bytes);
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    header.* = .{ .len = bytes.len, .data = data };
    return header;
}

export fn __openjai_arg_count() i64 {
    return @intCast(c._NSGetArgc().*);
}

export fn __openjai_arg_value(index: i64) ?*OpenJaiRuntimeString {
    if (index < 0) return makeRuntimeString("");
    const argc = c._NSGetArgc().*;
    if (index >= argc) return makeRuntimeString("");
    const argv = c._NSGetArgv().*;
    const raw = argv[@intCast(index)];
    if (raw == null) return makeRuntimeString("");
    const bytes = std.mem.span(raw);
    return makeRuntimeString(bytes);
}

export fn __openjai_read_entire_file(path_data: [*]const u8, path_len: usize) ?*OpenJaiRuntimeString {
    const path_raw = c.malloc(path_len + 1) orelse return null;
    defer c.free(path_raw);
    const path: [*]u8 = @ptrCast(path_raw);
    if (path_len != 0) @memcpy(path[0..path_len], path_data[0..path_len]);
    path[path_len] = 0;

    const file = c.fopen(path, "rb") orelse return makeRuntimeString("");
    defer _ = c.fclose(file);
    if (c.fseek(file, 0, c.SEEK_END) != 0) return makeRuntimeString("");
    const size = c.ftell(file);
    if (size < 0) return makeRuntimeString("");
    if (c.fseek(file, 0, c.SEEK_SET) != 0) return makeRuntimeString("");
    const len: usize = @intCast(size);
    const header_raw = c.malloc(@sizeOf(OpenJaiRuntimeString)) orelse return null;
    errdefer c.free(header_raw);
    const data_raw = c.malloc(@max(len, 1)) orelse return null;
    const data: [*]u8 = @ptrCast(data_raw);
    if (len != 0) {
        const read_count = c.fread(data, 1, len, file);
        if (read_count != len) {
            c.free(data_raw);
            return makeRuntimeString("");
        }
    }
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    header.* = .{ .len = len, .data = data };
    return header;
}

export fn __openjai_string_equal(lhs_data: [*]const u8, lhs_len: usize, rhs_data: [*]const u8, rhs_len: usize) bool {
    if (lhs_len != rhs_len) return false;
    if (lhs_len == 0) return true;
    return c.memcmp(lhs_data, rhs_data, lhs_len) == 0;
}

export fn __openjai_string_slice(source: ?*OpenJaiRuntimeString, start_raw: i64, len_raw: i64) ?*OpenJaiRuntimeString {
    const src = source orelse return makeRuntimeString("");
    const start: usize = if (start_raw < 0) 0 else @intCast(start_raw);
    if (start >= src.len) return makeRuntimeString("");
    const requested: usize = if (len_raw < 0) 0 else @intCast(len_raw);
    const len = @min(requested, src.len - start);
    const header_raw = c.malloc(@sizeOf(OpenJaiRuntimeString)) orelse return null;
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    header.* = .{ .len = len, .data = src.data + start };
    return header;
}

export fn __openjai_array_add(slot: ?*?*OpenJaiArray, item: ?*const anyopaque, elem_size: usize) ?*anyopaque {
    const slot_ptr = slot orelse @panic("array_add on null array slot");
    if (elem_size == 0) return null;
    var array = slot_ptr.*;
    if (array == null) {
        const raw = c.malloc(@sizeOf(OpenJaiArray)) orelse return null;
        array = @ptrCast(@alignCast(raw));
        array.?.* = .{ .count = 0, .capacity = 0, .data = null };
        slot_ptr.* = array;
    }
    const a = array.?;
    if (a.count == a.capacity) {
        const new_capacity: usize = if (a.capacity == 0) 8 else a.capacity * 2;
        const bytes = new_capacity * elem_size;
        const new_data = if (a.data) |old| c.realloc(old, bytes) else c.malloc(bytes);
        if (new_data == null) return null;
        a.data = new_data;
        a.capacity = new_capacity;
    }
    const data: [*]u8 = @ptrCast(a.data.?);
    const dst = data + a.count * elem_size;
    if (item) |src_raw| {
        const src: [*]const u8 = @ptrCast(src_raw);
        @memcpy(dst[0..elem_size], src[0..elem_size]);
    } else {
        @memset(dst[0..elem_size], 0);
    }
    a.count += 1;
    return dst;
}

export fn __openjai_array_count(slot: ?*?*OpenJaiArray) i64 {
    const slot_ptr = slot orelse return 0;
    return @intCast(if (slot_ptr.*) |a| a.count else 0);
}

export fn __openjai_array_data(slot: ?*?*OpenJaiArray) ?*anyopaque {
    const slot_ptr = slot orelse return null;
    return if (slot_ptr.*) |a| a.data else null;
}

export fn __openjai_array_index(slot: ?*?*OpenJaiArray, index: i64, elem_size: usize) ?*anyopaque {
    const slot_ptr = slot orelse @panic("indexing null dynamic array slot");
    const a = slot_ptr.* orelse @panic("indexing null dynamic array");
    if (index < 0 or @as(usize, @intCast(index)) >= a.count) {
        std.debug.print("openjai runtime: dynamic array index out of bounds: array={*} count={} index={} elem_size={}\n", .{ a, a.count, index, elem_size });
        @panic("dynamic array index out of bounds");
    }
    const data: [*]u8 = @ptrCast(a.data.?);
    return data + @as(usize, @intCast(index)) * elem_size;
}

export fn __openjai_to_calendar(low_ns: u64, timezone: i64) ?*OpenJaiCalendar {
    const raw = c.malloc(@sizeOf(OpenJaiCalendar)) orelse return null;
    const cal: *OpenJaiCalendar = @ptrCast(@alignCast(raw));
    const sec_u64 = low_ns / std.time.ns_per_s;
    const nsec = low_ns % std.time.ns_per_s;
    const seconds: c.time_t = @intCast(sec_u64);
    var tm_value: c.struct_tm = undefined;
    const tm_ptr = if (timezone == 1) c.localtime_r(&seconds, &tm_value) else c.gmtime_r(&seconds, &tm_value);
    if (tm_ptr == null) @panic("calendar conversion failed");
    cal.* = .{
        .year = @as(i64, tm_value.tm_year) + 1900,
        .month_starting_at_0 = @intCast(tm_value.tm_mon),
        .day_of_month_starting_at_0 = @as(i64, tm_value.tm_mday) - 1,
        .day_of_week_starting_at_0 = @intCast(tm_value.tm_wday),
        .hour = @intCast(tm_value.tm_hour),
        .minute = @intCast(tm_value.tm_min),
        .second = @intCast(tm_value.tm_sec),
        .millisecond = @intCast(nsec / std.time.ns_per_ms),
        .time_zone = timezone,
    };
    return cal;
}

export fn __openjai_calendar_get_i64(calendar: ?*OpenJaiCalendar, field_id: i64) i64 {
    const cal = calendar orelse @panic("null Calendar");
    return switch (field_id) {
        0 => cal.year,
        1 => cal.month_starting_at_0,
        2 => cal.day_of_month_starting_at_0,
        3 => cal.day_of_week_starting_at_0,
        4 => cal.hour,
        5 => cal.minute,
        6 => cal.second,
        7 => cal.millisecond,
        8 => cal.time_zone,
        else => @panic("invalid Calendar field id"),
    };
}

export fn __openjai_calendar_to_string(calendar: ?*OpenJaiCalendar) ?*OpenJaiRuntimeString {
    const cal = calendar orelse @panic("null Calendar");
    const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const month_idx: usize = if (cal.month_starting_at_0 >= 0 and cal.month_starting_at_0 < 12) @intCast(cal.month_starting_at_0) else 0;
    var tmp: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&tmp, "{d} {s} {d}, {d:0>2}:{d:0>2}:{d:0>2}", .{ cal.day_of_month_starting_at_0 + 1, months[month_idx], cal.year, @as(u64, @intCast(cal.hour)), @as(u64, @intCast(cal.minute)), @as(u64, @intCast(cal.second)) }) catch unreachable;
    const header_raw = c.malloc(@sizeOf(OpenJaiRuntimeString)) orelse return null;
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    const data = @as(?[*]u8, @ptrCast(c.malloc(text.len))) orelse return null;
    @memcpy(data[0..text.len], text);
    header.* = .{ .len = text.len, .data = data };
    return header;
}

export fn __openjai_current_time_consensus_low() u64 {
    var ts: std.posix.timespec = undefined;
    switch (std.posix.errno(std.posix.system.clock_gettime(.REALTIME, &ts))) {
        .SUCCESS => return @as(u64, @intCast(ts.sec)) *% std.time.ns_per_s +% @as(u64, @intCast(ts.nsec)),
        else => @panic("clock_gettime(CLOCK_REALTIME) failed"),
    }
}

export fn __openjai_current_time_monotonic_low() u64 {
    var ts: std.posix.timespec = undefined;
    switch (std.posix.errno(std.posix.system.clock_gettime(.MONOTONIC, &ts))) {
        .SUCCESS => return @as(u64, @intCast(ts.sec)) *% std.time.ns_per_s +% @as(u64, @intCast(ts.nsec)),
        else => @panic("clock_gettime(CLOCK_MONOTONIC) failed"),
    }
}

export fn __openjai_random_seed(seed: u64) void {
    openjai_random_state = if (seed == 0) 0x9e3779b97f4a7c15 else seed;
}

export fn __openjai_random_get() u64 {
    var z = openjai_random_state +% 0x9e3779b97f4a7c15;
    openjai_random_state = z;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

export fn __openjai_random_get_zero_to_one() f64 {
    const bits = __openjai_random_get() >> 11;
    return @as(f64, @floatFromInt(bits)) * (1.0 / 9007199254740992.0);
}

export fn __openjai_random_get_within_range(min: f64, max: f64) f64 {
    return min + (max - min) * __openjai_random_get_zero_to_one();
}

fn writeFloatText(text: []const u8) void {
    if (std.mem.indexOfScalar(u8, text, '.')) |dot| {
        var end = text.len;
        while (end > dot + 1 and text[end - 1] == '0') end -= 1;
        if (end == dot + 1) end = dot;
        writeAll(text[0..end]);
        return;
    }
    writeAll(text);
}

fn writeAll(bytes: []const u8) void {
    var index: usize = 0;
    while (index < bytes.len) {
        const rc = std.posix.system.write(std.posix.STDOUT_FILENO, bytes[index..].ptr, bytes.len - index);
        switch (std.posix.errno(rc)) {
            .SUCCESS => index += @intCast(rc),
            .INTR => continue,
            else => unreachable,
        }
    }
}
