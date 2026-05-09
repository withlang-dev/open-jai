const std = @import("std");

comptime {
    _ = std;
    _ = @import("core.zig");
    _ = @import("platform_darwin.zig");
    _ = @import("start_exe.zig");
}
