const std = @import("std");
const builtin = @import("builtin");

comptime {
    _ = std;
    _ = @import("core.zig");
    _ = @import("start_exe.zig");

    switch (builtin.os.tag) {
        .macos => _ = @import("platform_darwin.zig"),
        .linux => _ = @import("platform_linux.zig"),
        else => @compileError("Unsupported operating system"),
    }
}

