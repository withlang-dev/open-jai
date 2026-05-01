const builtin = @import("builtin");

pub const TargetInfo = struct {
    os: []const u8,
    arch: []const u8,
    triple: []const u8,
    pointer_size: u8,
};

pub fn native() TargetInfo {
    return .{
        .os = @tagName(builtin.target.os.tag),
        .arch = @tagName(builtin.target.cpu.arch),
        .triple = switch (builtin.target.cpu.arch) {
            .aarch64 => "arm64-apple-macosx",
            .x86_64 => "x86_64-apple-macosx",
            else => @tagName(builtin.target.cpu.arch),
        },
        .pointer_size = @sizeOf(usize),
    };
}
