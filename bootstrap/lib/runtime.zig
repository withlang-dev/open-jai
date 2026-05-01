const std = @import("std");

export fn __openjai_print(data: [*]const u8, len: usize) void {
    writeAll(data[0..len]);
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
        else => "<unknown type>",
    };
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
