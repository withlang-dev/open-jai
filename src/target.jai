// Port of bootstrap/src/target.zig.

Target_OS :: enum {
    UNKNOWN;
    WINDOWS;
    MACOS;
    LINUX;
}

host_os :: () -> Target_OS {
    return .MACOS;
}

