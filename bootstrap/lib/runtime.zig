const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
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

export fn __openjai_print_float(value: f64) void {
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
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
        20 => "int",
        21 => "float",
        30 => "procedure (s64, s64, s64) -> s64",
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
