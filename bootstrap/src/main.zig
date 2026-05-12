const std = @import("std");
const Compilation = @import("Compilation.zig").Compilation;
const Options = @import("Compilation.zig").Options;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const options = parseArgs(allocator, init.minimal) catch |err| switch (err) {
        error.InvalidArguments => std.process.exit(64),
        else => return err,
    };
    defer allocator.free(options.command_line);

    var comp = Compilation.init(allocator, init.io, options);
    comp.compile() catch std.process.exit(1);
}

fn parseArgs(allocator: std.mem.Allocator, init: std.process.Init.Minimal) !Options {
    var args = std.process.Args.Iterator.init(init.args);

    var command_line = std.ArrayList([]const u8).empty;
    errdefer command_line.deinit(allocator);
    while (args.next()) |arg| try command_line.append(allocator, arg);

    if (command_line.items.len < 2) {
        usage();
        return error.InvalidArguments;
    }
    const input_path = command_line.items[1];
    if (std.mem.eql(u8, input_path, "--help") or std.mem.eql(u8, input_path, "-h")) {
        usage();
        std.process.exit(0);
    }

    var output_path: []const u8 = "out/a.out";
    var runtime_path: []const u8 = "zig-out/lib/openjai_runtime.manifest";
    var check_only = false;
    var i: usize = 2;
    while (i < command_line.items.len) : (i += 1) {
        const arg = command_line.items[i];
        if (std.mem.eql(u8, arg, "--check")) {
            check_only = true;
        } else if (std.mem.eql(u8, arg, "--no-implicit-placeholders") or std.mem.eql(u8, arg, "--strict-placeholders")) {
            // This is the default bootstrap policy; keep the flag accepted for scripts.
        } else if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= command_line.items.len) {
                std.debug.print("openjai: error: expected output path after -o\n", .{});
                return error.InvalidArguments;
            }
            output_path = command_line.items[i];
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            i += 1;
            if (i >= command_line.items.len) {
                std.debug.print("openjai: error: expected runtime object path after --runtime\n", .{});
                return error.InvalidArguments;
            }
            runtime_path = command_line.items[i];
        } else {
            std.debug.print("openjai: error: unrecognized argument '{s}'\n", .{arg});
            usage();
            return error.InvalidArguments;
        }
    }

    return .{
        .input_path = input_path,
        .output_path = output_path,
        .runtime_path = runtime_path,
        .check_only = check_only,
        .command_line = try command_line.toOwnedSlice(allocator),
    };
}

fn usage() void {
    std.debug.print("usage: openjai <input.jai> [--check] [-o output] [--runtime runtime.o]\n", .{});
}

test "argument parser module loads" {
    try std.testing.expect(true);
}
