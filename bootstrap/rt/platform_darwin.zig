const std = @import("std");
const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("sys/mman.h");
    @cInclude("sys/stat.h");
    @cInclude("time.h");
});

const OpenJaiRtStat = extern struct {
    size: i64,
    is_dir: i32,
    is_file: i32,
    modified_ns: i64,
};

const OpenJaiCalendar = extern struct {
    year: i64,
    month_starting_at_0: i64,
    day_of_month_starting_at_0: i64,
    day_of_week_starting_at_0: i64,
    hour: i64,
    minute: i64,
    second: i64,
    millisecond: i64,
    time_zone: i64,
};

const OJ_O_RDONLY = 0;
const OJ_O_WRONLY = 1;
const OJ_O_RDWR = 2;
const OJ_O_CREAT = 0x0200;
const OJ_O_TRUNC = 0x0400;
const OJ_O_APPEND = 0x0800;

const OJ_SEEK_SET = 0;
const OJ_SEEK_CUR = 1;
const OJ_SEEK_END = 2;

export fn oj_rt_write(fd: i32, data: [*]const u8, len: usize) i64 {
    var offset: usize = 0;
    while (offset < len) {
        const rc = std.posix.system.write(fd, data + offset, len - offset);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                const wrote: usize = @intCast(rc);
                if (wrote == 0) return @intCast(offset);
                offset += wrote;
            },
            .INTR => continue,
            .AGAIN => if (offset != 0) return @intCast(offset) else return -11,
            .BADF => return -9,
            .PIPE => return -32,
            else => return -5,
        }
    }
    return @intCast(offset);
}

export fn oj_rt_read(fd: i32, data: [*]u8, len: usize) i64 {
    while (true) {
        const rc = c.read(fd, data, len);
        if (rc >= 0) return @intCast(rc);
        const err = errnoCode();
        if (err == 4) continue;
        return -err;
    }
}

export fn oj_rt_open(path_z: [*:0]const u8, flags: i32, mode: i32) i32 {
    var native_flags: c_int = switch (flags & 3) {
        OJ_O_WRONLY => c.O_WRONLY,
        OJ_O_RDWR => c.O_RDWR,
        else => c.O_RDONLY,
    };
    if ((flags & OJ_O_CREAT) != 0) native_flags |= c.O_CREAT;
    if ((flags & OJ_O_TRUNC) != 0) native_flags |= c.O_TRUNC;
    if ((flags & OJ_O_APPEND) != 0) native_flags |= c.O_APPEND;

    while (true) {
        const fd = c.open(path_z, native_flags, @as(c.mode_t, @intCast(mode)));
        if (fd >= 0) return @intCast(fd);
        const err = errnoCode();
        if (err == 4) continue;
        return -err;
    }
}

export fn oj_rt_close(fd: i32) i32 {
    while (true) {
        const rc = c.close(fd);
        if (rc == 0) return 0;
        const err = errnoCode();
        if (err == 4) continue;
        return -err;
    }
}

export fn oj_rt_seek(fd: i32, offset: i64, whence: i32) i64 {
    const native_whence: c_int = switch (whence) {
        OJ_SEEK_CUR => c.SEEK_CUR,
        OJ_SEEK_END => c.SEEK_END,
        else => c.SEEK_SET,
    };
    const rc = c.lseek(fd, offset, native_whence);
    if (rc >= 0) return @intCast(rc);
    return -errnoCode();
}

export fn oj_rt_stat(path_z: [*:0]const u8, out: ?*OpenJaiRtStat) i32 {
    const out_ptr = out orelse return -22;
    var native: c.struct_stat = undefined;
    if (c.stat(path_z, &native) != 0) return -errnoCode();
    out_ptr.* = .{
        .size = @intCast(native.st_size),
        .is_dir = if ((native.st_mode & c.S_IFMT) == c.S_IFDIR) 1 else 0,
        .is_file = if ((native.st_mode & c.S_IFMT) == c.S_IFREG) 1 else 0,
        .modified_ns = @as(i64, @intCast(native.st_mtimespec.tv_sec)) * std.time.ns_per_s + @as(i64, @intCast(native.st_mtimespec.tv_nsec)),
    };
    return 0;
}

export fn oj_rt_mkdir(path_z: [*:0]const u8, mode: i32) i32 {
    if (c.mkdir(path_z, @as(c.mode_t, @intCast(mode))) == 0) return 0;
    const err = errnoCode();
    if (err == 17) return 0;
    return -err;
}

export fn oj_rt_mmap(len: usize) ?*anyopaque {
    if (len == 0) return null;
    const ptr = c.mmap(null, len, c.PROT_READ | c.PROT_WRITE, c.MAP_PRIVATE | c.MAP_ANON, -1, 0);
    if (@intFromPtr(ptr) == std.math.maxInt(usize)) return null;
    return ptr;
}

export fn oj_rt_munmap(ptr: ?*anyopaque, len: usize) void {
    const p = ptr orelse return;
    if (len == 0) return;
    _ = c.munmap(p, len);
}

export fn oj_rt_sleep_milliseconds(ms: u64) void {
    var remaining = c.struct_timespec{
        .tv_sec = @intCast(ms / 1000),
        .tv_nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
    };
    while (c.nanosleep(&remaining, &remaining) != 0) {
        if (errnoCode() != 4) return;
    }
}

export fn oj_rt_exit(code: i32) noreturn {
    std.process.exit(@intCast(code));
}

export fn oj_rt_clock_realtime_ns() i64 {
    var ts: std.posix.timespec = undefined;
    switch (std.posix.errno(std.posix.system.clock_gettime(.REALTIME, &ts))) {
        .SUCCESS => return @as(i64, @intCast(ts.sec)) * std.time.ns_per_s + @as(i64, @intCast(ts.nsec)),
        .INTR => return oj_rt_clock_realtime_ns(),
        else => return -5,
    }
}

export fn oj_rt_clock_monotonic_ns() i64 {
    var ts: std.posix.timespec = undefined;
    switch (std.posix.errno(std.posix.system.clock_gettime(.MONOTONIC, &ts))) {
        .SUCCESS => return @as(i64, @intCast(ts.sec)) * std.time.ns_per_s + @as(i64, @intCast(ts.nsec)),
        .INTR => return oj_rt_clock_monotonic_ns(),
        else => return -5,
    }
}

export fn oj_rt_to_calendar(low_ns: u64, timezone: i64, out: ?*OpenJaiCalendar) i32 {
    const calendar = out orelse return -22;
    const sec_u64 = low_ns / std.time.ns_per_s;
    const nsec = low_ns % std.time.ns_per_s;
    const seconds: c.time_t = @intCast(sec_u64);
    var tm_value: c.struct_tm = undefined;
    const tm_ptr = if (timezone == 1) c.localtime_r(&seconds, &tm_value) else c.gmtime_r(&seconds, &tm_value);
    if (tm_ptr == null) return -5;
    calendar.* = .{
        .year = @as(i64, tm_value.tm_year) + 1900,
        .month_starting_at_0 = @intCast(tm_value.tm_mon),
        .day_of_month_starting_at_0 = @as(i64, tm_value.tm_mday) - 1,
        .day_of_week_starting_at_0 = @intCast(tm_value.tm_wday),
        .hour = @intCast(tm_value.tm_hour),
        .minute = @intCast(tm_value.tm_min),
        .second = @intCast(tm_value.tm_sec),
        .millisecond = @intCast(nsec / std.time.ns_per_ms),
        .time_zone = timezone,
    };
    return 0;
}

fn errnoCode() i32 {
    return @intCast(std.posix.system._errno().*);
}
