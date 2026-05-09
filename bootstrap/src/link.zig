const std = @import("std");
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub fn link(allocator: std.mem.Allocator, io: std.Io, object_path: []const u8, runtime_path: []const u8, output_path: []const u8, diag: Diagnostic) !void {
    _ = diag;
    var runtime_inputs = try resolveRuntimeInputs(allocator, io, runtime_path);
    defer runtime_inputs.deinit(allocator);

    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{ "cc", "-o", output_path, object_path });
    try argv.appendSlice(allocator, runtime_inputs.items.items);
    try argv.append(allocator, "-lSystem");

    const result = std.process.run(allocator, io, .{ .argv = argv.items, .stderr_limit = .limited(64 * 1024), .stdout_limit = .limited(64 * 1024) }) catch |err| {
        std.debug.print("link: error: failed to spawn linker: {s}\n", .{@errorName(err)});
        return error.LinkFailed;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code == 0) return else {
            std.debug.print("link: error: linker exited with code {d}\ncommand:", .{code});
            for (argv.items) |arg| std.debug.print(" {s}", .{arg});
            std.debug.print("\n{s}\n", .{result.stderr});
            return error.LinkFailed;
        },
        else => {
            std.debug.print("link: error: linker terminated abnormally\n{s}\n", .{result.stderr});
            return error.LinkFailed;
        },
    }
}

const RuntimeInputs = struct {
    items: std.ArrayList([]const u8) = .empty,
    owned: std.ArrayList([]const u8) = .empty,

    fn appendBorrowed(r: *RuntimeInputs, allocator: std.mem.Allocator, value: []const u8) !void {
        try r.items.append(allocator, value);
    }

    fn appendOwned(r: *RuntimeInputs, allocator: std.mem.Allocator, value: []const u8) !void {
        try r.owned.append(allocator, value);
        try r.items.append(allocator, value);
    }

    fn deinit(r: *RuntimeInputs, allocator: std.mem.Allocator) void {
        for (r.owned.items) |value| allocator.free(value);
        r.owned.deinit(allocator);
        r.items.deinit(allocator);
    }
};

fn resolveRuntimeInputs(allocator: std.mem.Allocator, io: std.Io, runtime_path: []const u8) !RuntimeInputs {
    var inputs = RuntimeInputs{};
    errdefer inputs.deinit(allocator);

    if (std.mem.endsWith(u8, runtime_path, ".manifest")) {
        try appendManifestRuntimeInputs(allocator, io, &inputs, runtime_path);
        return inputs;
    }

    const manifest_path = try companionManifestPath(allocator, runtime_path);
    defer allocator.free(manifest_path);
    if (try pathExists(io, manifest_path)) {
        try appendManifestRuntimeInputs(allocator, io, &inputs, manifest_path);
        return inputs;
    }

    try inputs.appendBorrowed(allocator, runtime_path);
    return inputs;
}

fn companionManifestPath(allocator: std.mem.Allocator, runtime_path: []const u8) ![]const u8 {
    if (std.mem.endsWith(u8, runtime_path, ".o")) {
        return try std.fmt.allocPrint(allocator, "{s}.manifest", .{runtime_path[0 .. runtime_path.len - 2]});
    }
    return try std.fmt.allocPrint(allocator, "{s}.manifest", .{runtime_path});
}

fn appendManifestRuntimeInputs(allocator: std.mem.Allocator, io: std.Io, inputs: *RuntimeInputs, manifest_path: []const u8) !void {
    const manifest = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(1024 * 1024)) catch |err| {
        std.debug.print("link: error: failed to read runtime manifest '{s}': {s}\n", .{ manifest_path, @errorName(err) });
        return error.LinkFailed;
    };
    defer allocator.free(manifest);

    const base_dir = std.fs.path.dirname(manifest_path);
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.fs.path.isAbsolute(line)) {
            try inputs.appendOwned(allocator, try allocator.dupe(u8, line));
        } else if (base_dir) |dir| {
            try inputs.appendOwned(allocator, try std.fs.path.join(allocator, &.{ dir, line }));
        } else {
            try inputs.appendOwned(allocator, try allocator.dupe(u8, line));
        }
    }

    if (inputs.items.items.len == 0) {
        std.debug.print("link: error: runtime manifest '{s}' did not list any runtime objects\n", .{manifest_path});
        return error.LinkFailed;
    }
}

fn pathExists(io: std.Io, path: []const u8) !bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}
