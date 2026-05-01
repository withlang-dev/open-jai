const std = @import("std");
const Diagnostic = @import("diagnostics.zig").Diagnostic;

pub fn link(allocator: std.mem.Allocator, io: std.Io, object_path: []const u8, runtime_path: []const u8, output_path: []const u8, diag: Diagnostic) !void {
    _ = diag;
    const argv = &[_][]const u8{ "cc", "-o", output_path, object_path, runtime_path, "-lSystem" };
    const result = std.process.run(allocator, io, .{ .argv = argv, .stderr_limit = .limited(64 * 1024), .stdout_limit = .limited(64 * 1024) }) catch |err| {
        std.debug.print("link: error: failed to spawn linker: {s}\n", .{@errorName(err)});
        return error.LinkFailed;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code == 0) return else {
            std.debug.print("link: error: linker exited with code {d}\ncommand: cc -o {s} {s} {s} -lSystem\n{s}\n", .{ code, output_path, object_path, runtime_path, result.stderr });
            return error.LinkFailed;
        },
        else => {
            std.debug.print("link: error: linker terminated abnormally\n{s}\n", .{result.stderr});
            return error.LinkFailed;
        },
    }
}
