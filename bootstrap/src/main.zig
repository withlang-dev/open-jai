const std = @import("std");
const Compilation = @import("Compilation.zig").Compilation;
const Options = @import("Compilation.zig").Options;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const options = parseArgs(init.minimal) catch |err| switch (err) {
        error.InvalidArguments => std.process.exit(64),
    };

    var comp = Compilation.init(allocator, init.io, options);
    comp.compile() catch std.process.exit(1);
}

fn parseArgs(init: std.process.Init.Minimal) !Options {
    var args = std.process.Args.Iterator.init(init.args);

    _ = args.next();
    const input_path = args.next() orelse {
        usage();
        return error.InvalidArguments;
    };
    if (std.mem.eql(u8, input_path, "--help") or std.mem.eql(u8, input_path, "-h")) {
        usage();
        std.process.exit(0);
    }

    var output_path: []const u8 = "a.out";
    var runtime_path: []const u8 = "zig-out/lib/openjai_runtime.o";
    var check_only = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            check_only = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            output_path = args.next() orelse {
                std.debug.print("openjai: error: expected output path after -o\n", .{});
                return error.InvalidArguments;
            };
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            runtime_path = args.next() orelse {
                std.debug.print("openjai: error: expected runtime object path after --runtime\n", .{});
                return error.InvalidArguments;
            };
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
    };
}

fn usage() void {
    std.debug.print("usage: openjai <input.jai> [--check] [-o output] [--runtime runtime.o]\n", .{});
}

test "argument parser module loads" {
    try std.testing.expect(true);
}
