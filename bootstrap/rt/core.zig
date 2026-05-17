const std = @import("std");

var debug_state: enum(u8) { unchecked, off, on } = .unchecked;

fn isDebugEnabled() bool {
    if (debug_state != .unchecked) return debug_state == .on;
    const val = std.c.getenv("OPENJAI_DEBUG");
    debug_state = if (val != null and val.?[0] != 0 and val.?[0] != '0') .on else .off;
    return debug_state == .on;
}

fn debugLog(comptime fmt: []const u8, args: anytype) void {
    if (!isDebugEnabled()) return;
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[OJ_DEBUG] " ++ fmt ++ "\n", args) catch return;
    _ = oj_rt_write(2, msg.ptr, msg.len);
}

extern fn oj_rt_write(fd: i32, data: [*]const u8, len: usize) i64;
extern fn oj_rt_read(fd: i32, data: [*]u8, len: usize) i64;
extern fn oj_rt_open(path_z: [*:0]const u8, flags: i32, mode: i32) i32;
extern fn oj_rt_close(fd: i32) i32;
extern fn oj_rt_seek(fd: i32, offset: i64, whence: i32) i64;
extern fn oj_rt_stat(path_z: [*:0]const u8, out: ?*OpenJaiRtStat) i32;
extern fn oj_rt_mkdir(path_z: [*:0]const u8, mode: i32) i32;
extern fn oj_rt_delete_directory(path_z: [*:0]const u8) i32;
extern fn oj_rt_chdir(path_z: [*:0]const u8) i32;
extern fn oj_rt_getcwd(buffer: [*]u8, len: usize) i64;
extern fn oj_rt_executable_path(buffer: [*]u8, len: usize) i64;
extern fn oj_rt_mmap(len: usize) ?*anyopaque;
extern fn oj_rt_munmap(ptr: ?*anyopaque, len: usize) void;
extern fn oj_rt_sleep_milliseconds(ms: u64) void;
extern fn oj_rt_exit(code: i32) noreturn;
extern fn oj_rt_clock_realtime_ns() i64;
extern fn oj_rt_clock_monotonic_ns() i64;
extern fn oj_rt_to_calendar(low_ns: u64, timezone: i64, out: ?*OpenJaiCalendar) i32;
extern fn oj_rt_cpu_has_feature(feature: i64) i32;

const OpenJaiRtStat = extern struct {
    size: i64,
    is_dir: i32,
    is_file: i32,
    modified_ns: i64,
};

const OJ_O_RDONLY = 0;
const OJ_O_WRONLY = 1;
const OJ_O_RDWR = 2;
const OJ_O_CREAT = 0x0200;
const OJ_O_TRUNC = 0x0400;

const OJ_SEEK_SET = 0;
const OJ_SEEK_CUR = 1;
const OJ_SEEK_END = 2;

const RuntimeAllocationHeader = extern struct {
    magic: usize,
    mapped_addr: usize,
    mapped_len: usize,
    requested_len: usize,
    owner_proc: i64,
    owner_data: usize,
    default_alias: usize,
};

const runtime_allocation_magic = 0x4f50454e4a414941;
const runtime_allocation_alignment = 16;
const allocator_proc_default: i64 = 1;
const allocator_proc_pool: i64 = 2;
const allocator_proc_flat_pool: i64 = 3;
const allocator_proc_rpmalloc: i64 = 4;
const allocator_cap_is_this_yours: i64 = 1 << 3;
const allocator_mode_startup: i64 = 0;
const allocator_mode_allocate: i64 = 1;
const allocator_mode_resize: i64 = 2;
const allocator_mode_free: i64 = 3;

var runtime_argc: i32 = 0;
var runtime_argv: ?[*]?[*:0]const u8 = null;
var runtime_start_monotonic_ns: i64 = 0;

export fn __openjai_runtime_init(argc: i32, argv: ?[*]?[*:0]const u8) void {
    runtime_argc = argc;
    runtime_argv = argv;
    runtime_start_monotonic_ns = oj_rt_clock_monotonic_ns();
}

export fn __openjai_runtime_fini() void {}

export fn __openjai_print(data: [*]const u8, len: usize) void {
    writeAll(data[0..len]);
}

export fn __openjai_print_return_int(data: [*]const u8, len: usize) i64 {
    writeAll(data[0..len]);
    return @intCast(len);
}

export fn __openjai_print_int(value: i64) void {
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
    writeAll(text);
}

export fn __openjai_print_uint(value: u64) void {
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
    writeAll(text);
}

export fn __openjai_print_static_int_array(data: ?*const anyopaque, count: usize, elem_size: usize) void {
    const base: [*]const u8 = @ptrCast(data orelse {
        writeAll("[]");
        return;
    });
    writeAll("[");
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (i != 0) writeAll(", ");
        const ptr = base + i * elem_size;
        const val: i64 = switch (elem_size) {
            1 => @as(i64, @intCast(@as(*const u8, @ptrCast(ptr)).*)),
            2 => @as(i64, @intCast(std.mem.readInt(i16, @ptrCast(ptr), .little))),
            4 => @as(i64, @intCast(std.mem.readInt(i32, @ptrCast(ptr), .little))),
            else => std.mem.readInt(i64, @ptrCast(@alignCast(ptr)), .little),
        };
        __openjai_print_int(val);
    }
    writeAll("]");
}

export fn __openjai_print_static_float_array(data: ?*const anyopaque, count: usize) void {
    const base = data orelse {
        writeAll("[]");
        return;
    };
    const floats: [*]const f64 = @ptrCast(@alignCast(base));
    writeAll("[");
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (i != 0) writeAll(", ");
        __openjai_print_float(floats[i]);
    }
    writeAll("]");
}

export fn __openjai_print_static_string_array(data: ?*const anyopaque, count: usize) void {
    const base: [*]const u8 = @ptrCast(data orelse {
        writeAll("[]");
        return;
    });
    writeAll("[");
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (i != 0) writeAll(", ");
        const elem = base + i * 16;
        const len = std.mem.readInt(u64, @ptrCast(elem), .little);
        const data_ptr_int = std.mem.readInt(u64, @ptrCast(elem + 8), .little);
        writeAll("\"");
        if (data_ptr_int != 0 and len > 0) {
            const str_data: [*]const u8 = @ptrFromInt(data_ptr_int);
            writeAll(str_data[0..len]);
        }
        writeAll("\"");
    }
    writeAll("]");
}

export fn __openjai_print_static_bool_array(data: ?*const anyopaque, count: usize) void {
    const base = data orelse {
        writeAll("[]");
        return;
    };
    const bools: [*]const u8 = @ptrCast(base);
    writeAll("[");
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (i != 0) writeAll(", ");
        writeAll(if (bools[i] != 0) "true" else "false");
    }
    writeAll("]");
}

export fn __openjai_print_format_int(value: i64, base: i64, minimum_digits: i64) void {
    var buf: [128]u8 = undefined;
    const digits = "0123456789abcdef";
    var tmp: [65]u8 = undefined;
    const actual_base: u64 = if (base >= 2 and base <= 16) @intCast(base) else 10;
    const negative_decimal = value < 0 and actual_base == 10;
    var n: u64 = if (value < 0)
        if (actual_base == 10) @as(u64, @intCast(-(value + 1))) + 1 else @bitCast(value)
    else
        @intCast(value);
    var len: usize = 0;
    while (true) {
        tmp[tmp.len - 1 - len] = digits[@intCast(n % actual_base)];
        len += 1;
        n /= actual_base;
        if (n == 0) break;
    }
    var out_len: usize = 0;
    if (negative_decimal) {
        buf[out_len] = '-';
        out_len += 1;
    }
    const min_digits: usize = if (minimum_digits > 0) @intCast(minimum_digits) else 0;
    var pad_len: usize = 0;
    while (pad_len + len < min_digits) : (pad_len += 1) {
        buf[out_len] = '0';
        out_len += 1;
    }
    @memcpy(buf[out_len .. out_len + len], tmp[tmp.len - len ..]);
    out_len += len;
    writeAll(buf[0..out_len]);
}

export fn __openjai_print_float(value: f64) void {
    if (writeLargeFloat32IntegerText(value)) return;
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d:.6}", .{value}) catch unreachable;
    writeFloatText(text);
}

fn writeLargeFloat32IntegerText(value: f64) bool {
    if (!std.math.isFinite(value) or @abs(value) < 1.0e15) return false;
    const value32: f32 = @floatCast(value);
    if (@as(f64, @floatCast(value32)) != value) return false;

    const bits: u32 = @bitCast(value32);
    const exp_raw = (bits >> 23) & 0xff;
    if (exp_raw == 0 or exp_raw == 0xff) return false;
    const exponent = @as(i32, @intCast(exp_raw)) - 127;
    if (exponent < 23) return false;
    const shift = exponent - 23;
    if (shift > 104) return false;

    const negative = (bits & 0x80000000) != 0;
    const mantissa = @as(u128, (bits & 0x7fffff) | 0x800000);
    var magnitude = mantissa << @as(u7, @intCast(shift));
    if (magnitude == 0) return false;

    var reversed: [64]u8 = undefined;
    var digit_count: usize = 0;
    while (magnitude != 0) {
        reversed[digit_count] = '0' + @as(u8, @intCast(magnitude % 10));
        digit_count += 1;
        magnitude /= 10;
    }

    var out: [80]u8 = undefined;
    var start: usize = 0;
    if (negative) {
        out[0] = '-';
        start = 1;
    }
    var i: usize = 0;
    while (i < digit_count) : (i += 1) {
        out[start + i] = reversed[digit_count - 1 - i];
    }

    const significant_digits: usize = 18;
    var total_len = start + digit_count;
    if (digit_count > significant_digits) {
        var carry = out[start + significant_digits] >= '5';
        if (carry) {
            var pos = start + significant_digits;
            while (pos > start) {
                pos -= 1;
                if (out[pos] != '9') {
                    out[pos] += 1;
                    carry = false;
                    break;
                }
                out[pos] = '0';
            }
        }
        if (carry) {
            out[start] = '1';
            var zero: usize = 1;
            while (zero <= digit_count) : (zero += 1) out[start + zero] = '0';
            total_len = start + digit_count + 1;
        } else {
            var zero = start + significant_digits;
            while (zero < start + digit_count) : (zero += 1) out[zero] = '0';
            total_len = start + digit_count;
        }
    }
    writeAll(out[0..total_len]);
    return true;
}

export fn __openjai_print_format_float(value: f64, width: i64, trailing_width: i64, zero_removal: i64, mode: i64) void {
    debugLog("print_format_float: value={d}, trail={d}, mode={d}", .{ value, trailing_width, mode });
    var buf: [128]u8 = undefined;
    const precision: usize = if (trailing_width >= 0) @intCast(trailing_width) else 6;
    const text = if (mode == 1)
        std.fmt.bufPrint(&buf, "{e:.6}", .{value}) catch unreachable
    else switch (precision) {
        0 => std.fmt.bufPrint(&buf, "{d:.0}", .{value}) catch unreachable,
        1 => std.fmt.bufPrint(&buf, "{d:.1}", .{value}) catch unreachable,
        2 => std.fmt.bufPrint(&buf, "{d:.2}", .{value}) catch unreachable,
        3 => std.fmt.bufPrint(&buf, "{d:.3}", .{value}) catch unreachable,
        4 => std.fmt.bufPrint(&buf, "{d:.4}", .{value}) catch unreachable,
        5 => std.fmt.bufPrint(&buf, "{d:.5}", .{value}) catch unreachable,
        else => std.fmt.bufPrint(&buf, "{d:.6}", .{value}) catch unreachable,
    };
    _ = width;
    if (mode == 1) {
        writeScientificText(text);
    } else if (zero_removal != 0) writeFloatText(text) else writeAll(text);
}

fn writeScientificText(text: []const u8) void {
    if (std.mem.indexOfScalar(u8, text, 'e') orelse std.mem.indexOfScalar(u8, text, 'E')) |exp| {
        writeAll(text[0 .. exp + 1]);
        if (exp + 1 < text.len and text[exp + 1] != '+' and text[exp + 1] != '-') writeAll("+");
        writeAll(text[exp + 1 ..]);
        return;
    }
    writeAll(text);
}

export fn __openjai_print_bool(value: bool) void {
    writeAll(if (value) "true" else "false");
}

export fn __openjai_print_type(type_id: u64) void {
    const text = switch (type_id) {
        1 => "bool",
        4 => "s32",
        5 => "s64",
        7 => "u8",
        8 => "u16",
        9 => "u32",
        10 => "*void",
        12 => "float32",
        13 => "float64",
        14 => "string",
        15 => "Type",
        16 => "Any",
        20 => "int",
        21 => "float",
        30 => "procedure (s64, s64, s64) -> s64",
        31 => "procedure ()",
        else => "<unknown type>",
    };
    writeAll(text);
}

export fn __openjai_alloc(size: usize) ?*anyopaque {
    const ptr = rtAllocOwned(size, allocator_proc_default, 0, false);
    if (ptr) |p| @memset(@as([*]u8, @ptrCast(p))[0..size], 0);
    return ptr;
}

export fn __openjai_alloc_owned(size: usize, allocator_raw: ?*OpenJaiAllocator) ?*anyopaque {
    const allocator = allocator_raw orelse return __openjai_alloc(size);
    const owner_data = if (allocator.data) |data| @intFromPtr(data) else 0;
    if (allocator.proc == allocator_proc_pool or allocator.proc == allocator_proc_flat_pool) {
        chargePool(owner_data, @intCast(size));
    }
    const ptr = rtAllocOwned(size, allocator.proc, owner_data, allocator.proc == allocator_proc_pool);
    if (ptr) |p| {
        @memset(@as([*]u8, @ptrCast(p))[0..size], 0);
        if (allocator.proc == allocator_proc_pool or allocator.proc == allocator_proc_flat_pool) {
            if (findPoolState(owner_data)) |state| {
                registerPoolAllocation(state, @as([*]u8, @ptrCast(p)), size);
            }
        }
    }
    return ptr;
}

export fn __openjai_allocator_proc_call(allocator_raw: ?*OpenJaiAllocator, mode: i64, size: i64, old_size: i64, old_memory: ?*anyopaque, allocator_data: ?*anyopaque) ?*anyopaque {
    const allocator = allocator_raw orelse return null;
    const owner_data = if (allocator_data) |data| @intFromPtr(data) else if (allocator.data) |data| @intFromPtr(data) else 0;
    switch (mode) {
        allocator_mode_startup => return null,
        allocator_mode_allocate => return __openjai_alloc_owned(@intCast(@max(size, 0)), allocator),
        allocator_mode_resize => return rtReallocOwned(old_memory, @intCast(@max(old_size, 0)), @intCast(@max(size, 0)), allocator.proc, owner_data, allocator.proc == allocator_proc_pool),
        allocator_mode_free => {
            rtFree(old_memory);
            return null;
        },
        allocator_cap_is_this_yours => {
            if (old_memory) |ptr| {
                if (findAllocationHeader(ptr)) |header| {
                    const owns_exact = header.owner_proc == allocator.proc and (owner_data == 0 or header.owner_data == owner_data);
                    const owns_as_backing = allocator.proc == allocator_proc_default and header.default_alias != 0;
                    return @ptrFromInt(if (owns_exact or owns_as_backing) @as(usize, 1) else @as(usize, 0));
                }
            }
            return null;
        },
        else => return null,
    }
}

export fn __openjai_allocator_owns(allocator_raw: ?*OpenJaiAllocator, memory: ?*anyopaque) bool {
    const allocator = allocator_raw orelse return false;
    const ptr = memory orelse return false;
    const header = findAllocationHeader(ptr) orelse return false;
    const owner_data = if (allocator.data) |data| @intFromPtr(data) else 0;
    if (allocator.proc == allocator_proc_pool or allocator.proc == allocator_proc_flat_pool) {
        return header.owner_proc == allocator.proc and (owner_data == 0 or header.owner_data == owner_data);
    }
    if (allocator.proc == allocator_proc_rpmalloc) {
        return header.owner_proc == allocator.proc;
    }
    if (header.owner_proc == allocator.proc and (owner_data == 0 or header.owner_data == owner_data)) return true;
    return allocator.proc == allocator_proc_default and header.default_alias != 0;
}

export fn __openjai_allocator_cap_flags(allocator_raw: ?*OpenJaiAllocator) i64 {
    _ = allocator_raw;
    return allocator_cap_is_this_yours;
}

export fn __openjai_allocator_cap_name(allocator_raw: ?*OpenJaiAllocator) ?*OpenJaiRuntimeString {
    const proc_id = if (allocator_raw) |allocator| allocator.proc else allocator_proc_default;
    return makeRuntimeString(switch (proc_id) {
        allocator_proc_pool => "modules/Pool",
        allocator_proc_flat_pool => "modules/Flat_Pool",
        allocator_proc_rpmalloc => "rpmalloc 1.4.4",
        else => "stripped-down rpmalloc 1.4.4 intended as Default_Allocator",
    });
}

export fn __openjai_pool_get(pool: ?*anyopaque, size_raw: i64, kind: i64) ?*anyopaque {
    const key = if (pool) |ptr| @intFromPtr(ptr) else 0;
    const state = ensurePoolState(key) orelse return null;
    const size: usize = @intCast(@max(size_raw, 0));
    const owner = if (kind == 1) allocator_proc_flat_pool else allocator_proc_pool;
    const ptr = rtAllocOwned(size, owner, key, kind != 1);
    if (ptr) |p| {
        @memset(@as([*]u8, @ptrCast(p))[0..size], 0);
        registerPoolAllocation(state, @as([*]u8, @ptrCast(p)), size);
    }
    chargePoolStateRaw(state, @intCast(size));
    return ptr;
}

export fn __openjai_pool_release(pool: ?*anyopaque) void {
    const key = if (pool) |ptr| @intFromPtr(ptr) else 0;
    if (findPoolState(key)) |state| {
        freePoolAllocationNodes(state);
        state.bytes_left = 0;
    }
}

export fn __openjai_pool_reset(pool: ?*anyopaque, overwrite_memory: i64) void {
    const key = if (pool) |ptr| @intFromPtr(ptr) else 0;
    if (findPoolState(key)) |state| {
        if (overwrite_memory != 0) {
            zeroOwnedAllocations(state);
        }
        state.bytes_left = 65536;
    }
}

fn zeroOwnedAllocations(state: *OpenJaiPoolState) void {
    var node = state.alloc_list;
    while (node) |n| {
        @memset(n.data_ptr[0..n.data_len], 0);
        node = n.next;
    }
}

fn registerPoolAllocation(state: *OpenJaiPoolState, data: [*]u8, len: usize) void {
    const node_mem = oj_rt_mmap(@sizeOf(PoolAllocationNode)) orelse return;
    const n: *PoolAllocationNode = @ptrCast(@alignCast(node_mem));
    n.* = .{ .data_ptr = data, .data_len = len, .next = state.alloc_list };
    state.alloc_list = n;
}

fn freePoolAllocationNodes(state: *OpenJaiPoolState) void {
    var node = state.alloc_list;
    while (node) |n| {
        const next = n.next;
        oj_rt_munmap(@ptrCast(n), @sizeOf(PoolAllocationNode));
        node = next;
    }
    state.alloc_list = null;
}

export fn __openjai_pool_bytes_left(pool: ?*anyopaque) i64 {
    const key = if (pool) |ptr| @intFromPtr(ptr) else 0;
    return if (findPoolState(key)) |state| state.bytes_left else 0;
}

export fn __openjai_realloc(ptr: ?*anyopaque, old_size: usize, new_size: usize) ?*anyopaque {
    return rtRealloc(ptr, old_size, new_size);
}

export fn __openjai_free(ptr: ?*anyopaque) void {
    rtFree(ptr);
}

export fn __openjai_assert_fail() noreturn {
    writeAll("Assertion failed\n");
    oj_rt_exit(1);
}

export fn __openjai_memcpy(dst: ?*anyopaque, src: ?*const anyopaque, len: usize) void {
    if (len == 0) return;
    const d = dst orelse unreachable;
    const s = src orelse unreachable;
    @memcpy(@as([*]u8, @ptrCast(d))[0..len], @as([*]const u8, @ptrCast(s))[0..len]);
}

export fn __openjai_memset(dst: ?*anyopaque, byte: u8, len: usize) void {
    if (len == 0) return;
    const d = dst orelse unreachable;
    @memset(@as([*]u8, @ptrCast(d))[0..len], byte);
}

export fn __openjai_memcmp(lhs: ?*const anyopaque, rhs: ?*const anyopaque, len: usize) i32 {
    if (len == 0) return 0;
    const l = lhs orelse unreachable;
    const r = rhs orelse unreachable;
    return switch (std.mem.order(u8, @as([*]const u8, @ptrCast(l))[0..len], @as([*]const u8, @ptrCast(r))[0..len])) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

export fn __openjai_exit(status: i32) noreturn {
    oj_rt_exit(status);
}

var openjai_random_state: u64 = 0x4d595df4d0f33173;

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

const OpenJaiRuntimeString = extern struct {
    len: usize,
    data: [*]const u8,
};

const OpenJaiArray = extern struct {
    count: usize,
    capacity: usize,
    data: ?*anyopaque,
};

const OpenJaiStringBuilder = extern struct {
    len: usize,
    capacity: usize,
    data: ?*anyopaque,
};

const OpenJaiFile = extern struct {
    fd: i32,
};

const OpenJaiAllocator = extern struct {
    proc: i64,
    data: ?*anyopaque,
};

const PoolAllocationNode = struct {
    data_ptr: [*]u8,
    data_len: usize,
    next: ?*PoolAllocationNode,
};

const OpenJaiPoolState = extern struct {
    key: usize,
    bytes_left: i64,
    next: ?*OpenJaiPoolState,
    alloc_list: ?*PoolAllocationNode = null,
};

var pool_states: ?*OpenJaiPoolState = null;

fn makeRuntimeString(bytes: []const u8) ?*OpenJaiRuntimeString {
    const header_raw = rtAlloc(@sizeOf(OpenJaiRuntimeString)) orelse return null;
    const allocation_len = @max(bytes.len, 1);
    const data_raw = rtAlloc(allocation_len) orelse {
        rtFree(header_raw);
        return null;
    };
    const data: [*]u8 = @ptrCast(data_raw);
    if (bytes.len != 0) @memcpy(data[0..bytes.len], bytes);
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    header.* = .{ .len = bytes.len, .data = data };
    return header;
}

export fn __openjai_arg_count() i64 {
    return @intCast(runtime_argc);
}

export fn __openjai_arg_value(index: i64) ?*OpenJaiRuntimeString {
    if (index < 0) return makeRuntimeString("");
    if (index >= runtime_argc) return makeRuntimeString("");
    const argv = runtime_argv orelse return makeRuntimeString("");
    const raw = argv[@intCast(index)];
    if (raw == null) return makeRuntimeString("");
    const bytes = std.mem.span(raw.?);
    return makeRuntimeString(bytes);
}

export fn __openjai_get_command_line_arguments() ?*OpenJaiArray {
    const count: usize = if (runtime_argc <= 0) 0 else @intCast(runtime_argc);
    const array_raw = rtAlloc(@sizeOf(OpenJaiArray)) orelse return null;
    const array: *OpenJaiArray = @ptrCast(@alignCast(array_raw));
    const data_raw = rtAlloc(@max(count, 1) * @sizeOf(OpenJaiRuntimeString)) orelse {
        rtFree(array_raw);
        return null;
    };
    const items: [*]OpenJaiRuntimeString = @ptrCast(@alignCast(data_raw));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const str = __openjai_arg_value(@intCast(i));
        if (str) |s| {
            items[i] = s.*;
        } else {
            items[i] = .{ .len = 0, .data = @ptrCast(&[0]u8{}) };
        }
    }
    array.* = .{ .count = count, .capacity = count, .data = data_raw };
    return array;
}

export fn __openjai_sleep_milliseconds(ms: i64) void {
    if (ms <= 0) return;
    oj_rt_sleep_milliseconds(@intCast(ms));
}

export fn __openjai_cpu_has_feature(feature: i64) bool {
    return oj_rt_cpu_has_feature(feature) != 0;
}

export fn __openjai_read_entire_file(path_data: [*]const u8, path_len: usize) ?*OpenJaiRuntimeString {
    const path_raw = rtAlloc(path_len + 1) orelse return null;
    defer rtFree(path_raw);
    const path: [*]u8 = @ptrCast(path_raw);
    if (path_len != 0) @memcpy(path[0..path_len], path_data[0..path_len]);
    path[path_len] = 0;

    const path_z: [*:0]const u8 = @ptrCast(path);
    const fd = oj_rt_open(path_z, OJ_O_RDONLY, 0);
    if (fd < 0) return null;
    defer _ = oj_rt_close(fd);

    var stat: OpenJaiRtStat = undefined;
    if (oj_rt_stat(path_z, &stat) != 0 or stat.size < 0) return null;
    const len: usize = @intCast(stat.size);
    const header_raw = rtAlloc(@sizeOf(OpenJaiRuntimeString)) orelse return null;
    const data_raw = rtAlloc(@max(len, 1)) orelse {
        rtFree(header_raw);
        return null;
    };
    const data: [*]u8 = @ptrCast(data_raw);
    var offset: usize = 0;
    while (offset < len) {
        const read_count = oj_rt_read(fd, data + offset, len - offset);
        if (read_count <= 0) {
            rtFree(data_raw);
            rtFree(header_raw);
            return null;
        }
        offset += @intCast(read_count);
    }
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    header.* = .{ .len = len, .data = data };
    return header;
}

export fn __openjai_make_directory(path_data: [*]const u8, path_len: usize) bool {
    const path_raw = pathToZ(path_data, path_len) orelse return false;
    defer rtFree(path_raw);
    return oj_rt_mkdir(@ptrCast(path_raw), 0o755) == 0;
}

export fn __openjai_delete_directory(path_data: [*]const u8, path_len: usize) bool {
    const path_raw = pathToZ(path_data, path_len) orelse return false;
    defer rtFree(path_raw);
    return oj_rt_delete_directory(@ptrCast(path_raw)) == 0;
}

export fn __openjai_file_exists(path_data: [*]const u8, path_len: usize) bool {
    const path_raw = pathToZ(path_data, path_len) orelse return false;
    defer rtFree(path_raw);
    var stat: OpenJaiRtStat = undefined;
    return oj_rt_stat(@ptrCast(path_raw), &stat) == 0 and stat.is_file != 0;
}

export fn __openjai_set_working_directory(path_data: [*]const u8, path_len: usize) bool {
    const path_raw = pathToZ(path_data, path_len) orelse return false;
    defer rtFree(path_raw);
    return oj_rt_chdir(@ptrCast(path_raw)) == 0;
}

export fn __openjai_get_working_directory() ?*OpenJaiRuntimeString {
    return runtimePathFromPlatform(oj_rt_getcwd);
}

export fn __openjai_get_path_of_running_executable() ?*OpenJaiRuntimeString {
    return runtimePathFromPlatform(oj_rt_executable_path);
}

fn runtimePathFromPlatform(comptime callback: fn ([*]u8, usize) callconv(.c) i64) ?*OpenJaiRuntimeString {
    var capacity: usize = 256;
    while (capacity <= 65536) : (capacity *= 2) {
        const data_raw = rtAlloc(capacity) orelse return null;
        const data: [*]u8 = @ptrCast(data_raw);
        const len = callback(data, capacity);
        if (len >= 0) {
            const header_raw = rtAlloc(@sizeOf(OpenJaiRuntimeString)) orelse {
                rtFree(data_raw);
                return null;
            };
            const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
            header.* = .{ .len = @intCast(len), .data = data };
            return header;
        }
        rtFree(data_raw);
    }
    return null;
}

export fn __openjai_path_strip_filename(path_data: [*]const u8, path_len: usize) ?*OpenJaiRuntimeString {
    var end = path_len;
    while (end > 0) {
        end -= 1;
        if (path_data[end] == '/' or path_data[end] == '\\') return makeRuntimeString(path_data[0 .. end + 1]);
    }
    return makeRuntimeString("");
}

export fn __openjai_file_open(path_data: [*]const u8, path_len: usize, for_writing: bool, keep_existing_content: bool) ?*OpenJaiFile {
    const path_raw = pathToZ(path_data, path_len) orelse return null;
    defer rtFree(path_raw);
    if (for_writing) makeParentDirs(@ptrCast(path_raw), path_len);
    var flags: i32 = if (for_writing) OJ_O_RDWR | OJ_O_CREAT else OJ_O_RDONLY;
    if (for_writing and !keep_existing_content) flags |= OJ_O_TRUNC;
    const fd = oj_rt_open(@ptrCast(path_raw), flags, 0o666);
    if (fd < 0) return null;
    const handle_raw = rtAlloc(@sizeOf(OpenJaiFile)) orelse {
        _ = oj_rt_close(fd);
        return null;
    };
    const handle: *OpenJaiFile = @ptrCast(@alignCast(handle_raw));
    handle.* = .{ .fd = fd };
    return handle;
}

export fn __openjai_file_close(file: ?*OpenJaiFile) bool {
    const handle = file orelse return false;
    if (handle.fd < 0) return false;
    const rc = oj_rt_close(handle.fd);
    handle.fd = -1;
    rtFree(handle);
    return rc == 0;
}

export fn __openjai_file_length(file: ?*OpenJaiFile) i64 {
    const handle = file orelse return -1;
    if (handle.fd < 0) return -1;
    const current = oj_rt_seek(handle.fd, 0, OJ_SEEK_CUR);
    if (current < 0) return -1;
    const end = oj_rt_seek(handle.fd, 0, OJ_SEEK_END);
    _ = oj_rt_seek(handle.fd, current, OJ_SEEK_SET);
    return end;
}

export fn __openjai_file_set_position(file: ?*OpenJaiFile, position: i64) bool {
    const handle = file orelse return false;
    if (handle.fd < 0 or position < 0) return false;
    return oj_rt_seek(handle.fd, position, OJ_SEEK_SET) >= 0;
}

export fn __openjai_file_write(file: ?*OpenJaiFile, data: [*]const u8, len: usize) bool {
    const handle = file orelse return false;
    if (handle.fd < 0) return false;
    var offset: usize = 0;
    while (offset < len) {
        const wrote = oj_rt_write(handle.fd, data + offset, len - offset);
        if (wrote <= 0) return false;
        offset += @intCast(wrote);
    }
    return true;
}

export fn __openjai_file_read(file: ?*OpenJaiFile, data: [*]u8, len: usize) bool {
    const handle = file orelse return false;
    if (handle.fd < 0) return false;
    var offset: usize = 0;
    while (offset < len) {
        const read_count = oj_rt_read(handle.fd, data + offset, len - offset);
        if (read_count <= 0) return false;
        offset += @intCast(read_count);
    }
    return true;
}

export fn __openjai_posix_read(fd: i64, data: [*]u8, len: usize) i64 {
    if (fd < 0 or fd > std.math.maxInt(i32)) return -9;
    return oj_rt_read(@intCast(fd), data, len);
}

export fn __openjai_string_builder_init(slot: ?*?*OpenJaiStringBuilder) void {
    const slot_ptr = slot orelse @panic("init_string_builder on null slot");
    if (slot_ptr.* != null) __openjai_string_builder_free(slot);
    const raw = rtAlloc(@sizeOf(OpenJaiStringBuilder)) orelse @panic("string builder allocation failed");
    const builder: *OpenJaiStringBuilder = @ptrCast(@alignCast(raw));
    builder.* = .{ .len = 0, .capacity = 0, .data = null };
    slot_ptr.* = builder;
}

export fn __openjai_string_builder_free(slot: ?*?*OpenJaiStringBuilder) void {
    const slot_ptr = slot orelse return;
    const builder = slot_ptr.* orelse return;
    rtFree(builder.data);
    rtFree(builder);
    slot_ptr.* = null;
}

export fn __openjai_string_builder_append_string(slot: ?*?*OpenJaiStringBuilder, data: [*]const u8, len: usize) bool {
    const builder = ensureBuilder(slot) orelse return false;
    if (!builderEnsure(builder, len)) return false;
    if (len != 0) @memcpy(@as([*]u8, @ptrCast(builder.data.?))[builder.len .. builder.len + len], data[0..len]);
    builder.len += len;
    return true;
}

export fn __openjai_string_builder_append_int(slot: ?*?*OpenJaiStringBuilder, value: i64) bool {
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
    return __openjai_string_builder_append_string(slot, text.ptr, text.len);
}

export fn __openjai_string_builder_append_float(slot: ?*?*OpenJaiStringBuilder, value: f64) bool {
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d:.6}", .{value}) catch unreachable;
    return __openjai_string_builder_append_string(slot, text.ptr, trimFloatText(text).len);
}

export fn __openjai_string_builder_append_bool(slot: ?*?*OpenJaiStringBuilder, value: bool) bool {
    const text = if (value) "true" else "false";
    return __openjai_string_builder_append_string(slot, text.ptr, text.len);
}

export fn __openjai_string_builder_to_string(slot: ?*?*OpenJaiStringBuilder) ?*OpenJaiRuntimeString {
    const builder = ensureBuilder(slot) orelse return null;
    if (builder.data == null or builder.len == 0) return makeRuntimeString("");
    return makeRuntimeString(@as([*]const u8, @ptrCast(builder.data.?))[0..builder.len]);
}

export fn __openjai_string_builder_length(slot: ?*?*OpenJaiStringBuilder) i64 {
    const builder = ensureBuilder(slot) orelse return 0;
    return @intCast(builder.len);
}

export fn __openjai_string_builder_join_array(slot: ?*?*OpenJaiStringBuilder, arr_slot: ?*?*OpenJaiArray, sep_data: [*]const u8, sep_len: usize, flags: i64) void {
    const arr = arrayFromRuntimeValue(arr_slot) orelse return;
    const count = arr.count;
    if (count == 0) return;
    const items: [*]const OpenJaiRuntimeString = @ptrCast(@alignCast(arr.data orelse return));
    const before_first = (flags & 1) != 0;
    const after_last = (flags & 2) != 0;
    if (before_first) _ = __openjai_string_builder_append_string(slot, sep_data, sep_len);
    for (0..count) |idx| {
        if (idx > 0) _ = __openjai_string_builder_append_string(slot, sep_data, sep_len);
        const str = items[idx];
        _ = __openjai_string_builder_append_string(slot, str.data, str.len);
    }
    if (after_last) _ = __openjai_string_builder_append_string(slot, sep_data, sep_len);
}

export fn __openjai_copy_string(data: [*]const u8, len: usize) ?*OpenJaiRuntimeString {
    return makeRuntimeString(data[0..len]);
}

export fn __openjai_to_c_string(data: [*]const u8, len: usize) ?*anyopaque {
    const raw = rtAlloc(len + 1) orelse return null;
    const out: [*]u8 = @ptrCast(raw);
    if (len != 0) @memcpy(out[0..len], data[0..len]);
    out[len] = 0;
    return raw;
}

export fn __openjai_string_from_c(ptr: ?[*:0]const u8) ?*OpenJaiRuntimeString {
    const p = ptr orelse return makeRuntimeString("");
    return makeRuntimeString(std.mem.span(p));
}

export fn __openjai_string_from_parts(data: [*]const u8, len: usize) ?*OpenJaiRuntimeString {
    return makeRuntimeString(data[0..len]);
}

export fn __openjai_string_trim(data: [*]const u8, len: usize) ?*OpenJaiRuntimeString {
    var start: usize = 0;
    var end: usize = len;
    while (start < end and std.ascii.isWhitespace(data[start])) start += 1;
    while (end > start and std.ascii.isWhitespace(data[end - 1])) end -= 1;
    return makeRuntimeString(data[start..end]);
}

export fn __openjai_string_compare(lhs_data: [*]const u8, lhs_len: usize, rhs_data: [*]const u8, rhs_len: usize) i64 {
    return switch (std.mem.order(u8, lhs_data[0..lhs_len], rhs_data[0..rhs_len])) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

export fn __openjai_sort_i64(data: ?*anyopaque, count: usize) void {
    const base = data orelse return;
    const items: [*]i64 = @ptrCast(@alignCast(base));
    var i: usize = 1;
    while (i < count) : (i += 1) {
        var j = i;
        while (j > 0 and items[j - 1] > items[j]) : (j -= 1) {
            const tmp = items[j - 1];
            items[j - 1] = items[j];
            items[j] = tmp;
        }
    }
}

export fn __openjai_sort_f64(data: ?*anyopaque, count: usize) void {
    const base = data orelse return;
    const items: [*]f64 = @ptrCast(@alignCast(base));
    var i: usize = 1;
    while (i < count) : (i += 1) {
        var j = i;
        while (j > 0 and items[j - 1] > items[j]) : (j -= 1) {
            const tmp = items[j - 1];
            items[j - 1] = items[j];
            items[j] = tmp;
        }
    }
}

export fn __openjai_sort_runtime_strings(data: ?*anyopaque, count: usize) void {
    const base = data orelse return;
    const items: [*]OpenJaiRuntimeString = @ptrCast(@alignCast(base));
    var i: usize = 1;
    while (i < count) : (i += 1) {
        var j = i;
        while (j > 0 and inlineStringOrder(items[j - 1], items[j]) == .gt) : (j -= 1) {
            const tmp = items[j - 1];
            items[j - 1] = items[j];
            items[j] = tmp;
        }
    }
}

fn inlineStringOrder(lhs: OpenJaiRuntimeString, rhs: OpenJaiRuntimeString) std.math.Order {
    return std.mem.order(u8, lhs.data[0..lhs.len], rhs.data[0..rhs.len]);
}

export fn __openjai_string_contains(lhs_data: [*]const u8, lhs_len: usize, rhs_data: [*]const u8, rhs_len: usize) bool {
    if (rhs_len == 0) return true;
    return std.mem.indexOf(u8, lhs_data[0..lhs_len], rhs_data[0..rhs_len]) != null;
}

export fn __openjai_string_begins_with(lhs_data: [*]const u8, lhs_len: usize, rhs_data: [*]const u8, rhs_len: usize) bool {
    if (rhs_len > lhs_len) return false;
    return std.mem.eql(u8, lhs_data[0..rhs_len], rhs_data[0..rhs_len]);
}

export fn __openjai_string_find(lhs_data: [*]const u8, lhs_len: usize, rhs_data: [*]const u8, rhs_len: usize, from_right: bool) i64 {
    if (rhs_len == 0) return 0;
    const haystack = lhs_data[0..lhs_len];
    const needle = rhs_data[0..rhs_len];
    const found = if (from_right) std.mem.lastIndexOf(u8, haystack, needle) else std.mem.indexOf(u8, haystack, needle);
    return if (found) |idx| @intCast(idx) else -1;
}

export fn __openjai_string_parse_int(data: [*]const u8, len: usize) i64 {
    return std.fmt.parseInt(i64, std.mem.trim(u8, data[0..len], " \t\r\n"), 10) catch 0;
}

export fn __openjai_string_parse_int_ok(data: [*]const u8, len: usize) bool {
    _ = std.fmt.parseInt(i64, std.mem.trim(u8, data[0..len], " \t\r\n"), 10) catch return false;
    return true;
}

export fn __openjai_string_parse_float(data: [*]const u8, len: usize) f64 {
    return std.fmt.parseFloat(f64, std.mem.trim(u8, data[0..len], " \t\r\n")) catch 0.0;
}

export fn __openjai_string_parse_float_ok(data: [*]const u8, len: usize) bool {
    _ = std.fmt.parseFloat(f64, std.mem.trim(u8, data[0..len], " \t\r\n")) catch return false;
    return true;
}

export fn __openjai_string_replace(source_data: [*]const u8, source_len: usize, needle_data: [*]const u8, needle_len: usize, replacement_data: [*]const u8, replacement_len: usize) ?*OpenJaiRuntimeString {
    if (needle_len == 0) return makeRuntimeString(source_data[0..source_len]);
    var count: usize = 0;
    var cursor: usize = 0;
    while (cursor < source_len) {
        if (std.mem.indexOf(u8, source_data[cursor..source_len], needle_data[0..needle_len])) |idx| {
            count += 1;
            cursor += idx + needle_len;
        } else break;
    }
    const new_len = source_len - count * needle_len + count * replacement_len;
    const raw = rtAlloc(new_len) orelse return null;
    const out: [*]u8 = @ptrCast(raw);
    var in_pos: usize = 0;
    var out_pos: usize = 0;
    while (in_pos < source_len) {
        if (std.mem.indexOf(u8, source_data[in_pos..source_len], needle_data[0..needle_len])) |idx| {
            if (idx != 0) @memcpy(out[out_pos .. out_pos + idx], source_data[in_pos .. in_pos + idx]);
            out_pos += idx;
            if (replacement_len != 0) @memcpy(out[out_pos .. out_pos + replacement_len], replacement_data[0..replacement_len]);
            out_pos += replacement_len;
            in_pos += idx + needle_len;
        } else {
            const rest = source_len - in_pos;
            if (rest != 0) @memcpy(out[out_pos .. out_pos + rest], source_data[in_pos..source_len]);
            break;
        }
    }
    const header_raw = rtAlloc(@sizeOf(OpenJaiRuntimeString)) orelse {
        rtFree(raw);
        return null;
    };
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    header.* = .{ .len = new_len, .data = out };
    return header;
}

export fn __openjai_string_split(data: [*]const u8, len: usize, sep_data: [*]const u8, sep_len: usize) ?*OpenJaiArray {
    const array_raw = rtAlloc(@sizeOf(OpenJaiArray)) orelse return null;
    const array: *OpenJaiArray = @ptrCast(@alignCast(array_raw));
    array.* = .{ .count = 0, .capacity = 0, .data = null };
    var array_slot: ?*OpenJaiArray = array;
    var start: usize = 0;
    if (sep_len == 0) {
        while (start < len) : (start += 1) {
            const piece = makeRuntimeString(data[start .. start + 1]) orelse return null;
            _ = __openjai_array_add(&array_slot, @ptrCast(piece), @sizeOf(OpenJaiRuntimeString));
        }
        return array;
    }
    while (start <= len) {
        const rest = data[start..len];
        const next = std.mem.indexOf(u8, rest, sep_data[0..sep_len]);
        const end = if (next) |idx| start + idx else len;
        const piece = makeRuntimeString(data[start..end]) orelse return null;
        _ = __openjai_array_add(&array_slot, @ptrCast(piece), @sizeOf(OpenJaiRuntimeString));
        if (next == null) break;
        start = end + sep_len;
    }
    return array;
}

export fn __openjai_write_entire_file(path_data: [*]const u8, path_len: usize, contents_data: [*]const u8, contents_len: usize) bool {
    const path_raw = rtAlloc(path_len + 1) orelse return false;
    defer rtFree(path_raw);
    const path: [*]u8 = @ptrCast(path_raw);
    if (path_len != 0) @memcpy(path[0..path_len], path_data[0..path_len]);
    path[path_len] = 0;

    makeParentDirs(path, path_len);

    const fd = oj_rt_open(@ptrCast(path), OJ_O_WRONLY | OJ_O_CREAT | OJ_O_TRUNC, 0o666);
    if (fd < 0) return false;
    defer _ = oj_rt_close(fd);
    var offset: usize = 0;
    while (offset < contents_len) {
        const wrote = oj_rt_write(fd, contents_data + offset, contents_len - offset);
        if (wrote <= 0) return false;
        offset += @intCast(wrote);
    }
    return true;
}

fn makeParentDirs(path: [*]u8, path_len: usize) void {
    var i: usize = 0;
    while (i < path_len) : (i += 1) {
        if (path[i] != '/') continue;
        if (i == 0) continue;
        const saved = path[i];
        path[i] = 0;
        _ = oj_rt_mkdir(@ptrCast(path), 0o755);
        path[i] = saved;
    }
}

fn pathToZ(path_data: [*]const u8, path_len: usize) ?*anyopaque {
    const path_raw = rtAlloc(path_len + 1) orelse return null;
    const path: [*]u8 = @ptrCast(path_raw);
    if (path_len != 0) @memcpy(path[0..path_len], path_data[0..path_len]);
    path[path_len] = 0;
    return path_raw;
}

export fn __openjai_string_equal(lhs_data: [*]const u8, lhs_len: usize, rhs_data: [*]const u8, rhs_len: usize) bool {
    if (lhs_len != rhs_len) return false;
    if (lhs_len == 0) return true;
    return std.mem.eql(u8, lhs_data[0..lhs_len], rhs_data[0..rhs_len]);
}

export fn __openjai_string_slice(source: ?*OpenJaiRuntimeString, start_raw: i64, len_raw: i64) ?*OpenJaiRuntimeString {
    const src = source orelse return makeRuntimeString("");
    const start: usize = if (start_raw < 0) 0 else @intCast(start_raw);
    if (start >= src.len) return makeRuntimeString("");
    const requested: usize = if (len_raw < 0) 0 else @intCast(len_raw);
    const len = @min(requested, src.len - start);
    const header_raw = rtAlloc(@sizeOf(OpenJaiRuntimeString)) orelse return null;
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    header.* = .{ .len = len, .data = src.data + start };
    return header;
}

export fn __openjai_array_add(slot: ?*?*OpenJaiArray, item: ?*const anyopaque, elem_size: usize) ?*anyopaque {
    const slot_ptr = slot orelse @panic("array_add on null array slot");
    if (elem_size == 0) return null;
    var array = arrayFromRuntimeValue(slot);
    if (array == null) {
        const raw = rtAlloc(@sizeOf(OpenJaiArray)) orelse return null;
        array = @ptrCast(@alignCast(raw));
        array.?.* = .{ .count = 0, .capacity = 0, .data = null };
        slot_ptr.* = array;
    }
    const a = array.?;
    if (a.count == a.capacity) {
        const new_capacity: usize = if (a.capacity == 0) 8 else a.capacity * 2;
        const bytes = new_capacity * elem_size;
        const old_bytes = a.capacity * elem_size;
        const new_data = rtRealloc(a.data, old_bytes, bytes);
        if (new_data == null) return null;
        a.data = new_data;
        a.capacity = new_capacity;
    }
    const data: [*]u8 = @ptrCast(a.data.?);
    const dst = data + a.count * elem_size;
    if (item) |src_raw| {
        const src: [*]const u8 = @ptrCast(src_raw);
        @memcpy(dst[0..elem_size], src[0..elem_size]);
    } else {
        @memset(dst[0..elem_size], 0);
    }
    a.count += 1;
    return dst;
}

export fn __openjai_array_add_spread(slot: ?*?*OpenJaiArray, src_data: ?*const anyopaque, src_count: i64, elem_size: usize) void {
    if (src_count <= 0 or elem_size == 0) return;
    const src: [*]const u8 = @ptrCast(src_data orelse return);
    const count: usize = @intCast(src_count);
    for (0..count) |i| {
        _ = __openjai_array_add(slot, src + i * elem_size, elem_size);
    }
}

export fn __openjai_array_insert_at(slot: ?*?*OpenJaiArray, item: ?*const anyopaque, index: i64, elem_size: usize) void {
    const slot_ptr = slot orelse @panic("array_insert_at on null array slot");
    if (elem_size == 0) return;
    var array = arrayFromRuntimeValue(slot);
    if (array == null) {
        const raw = rtAlloc(@sizeOf(OpenJaiArray)) orelse return;
        array = @ptrCast(@alignCast(raw));
        array.?.* = .{ .count = 0, .capacity = 0, .data = null };
        slot_ptr.* = array;
    }
    const a = array.?;
    const idx: usize = if (index < 0) 0 else @intCast(@min(index, @as(i64, @intCast(a.count))));
    if (a.count == a.capacity) {
        const new_capacity: usize = if (a.capacity == 0) 8 else a.capacity * 2;
        const bytes = new_capacity * elem_size;
        const old_bytes = a.capacity * elem_size;
        const new_data = rtRealloc(a.data, old_bytes, bytes);
        if (new_data == null) return;
        a.data = new_data;
        a.capacity = new_capacity;
    }
    const data: [*]u8 = @ptrCast(a.data.?);
    const tail_count = a.count - idx;
    if (tail_count > 0) {
        const src = data + idx * elem_size;
        const dst = data + (idx + 1) * elem_size;
        std.mem.copyBackwards(u8, dst[0 .. tail_count * elem_size], src[0 .. tail_count * elem_size]);
    }
    const dst = data + idx * elem_size;
    if (item) |src_raw| {
        const src: [*]const u8 = @ptrCast(src_raw);
        @memcpy(dst[0..elem_size], src[0..elem_size]);
    } else {
        @memset(dst[0..elem_size], 0);
    }
    a.count += 1;
}

export fn __openjai_array_pop(slot: ?*?*OpenJaiArray, elem_size: usize) ?*anyopaque {
    const a = arrayFromRuntimeValue(slot) orelse @panic("pop on null dynamic array");
    if (a.count == 0) @panic("pop from empty dynamic array");
    const result = rtAlloc(elem_size) orelse return null;
    const data: [*]u8 = @ptrCast(a.data.?);
    const src = data + (a.count - 1) * elem_size;
    @memcpy(@as([*]u8, @ptrCast(result))[0..elem_size], src[0..elem_size]);
    a.count -= 1;
    return result;
}

export fn __openjai_array_reset(slot: ?*?*OpenJaiArray) void {
    const a = arrayFromRuntimeValue(slot) orelse return;
    a.count = 0;
}

export fn __openjai_array_reserve(slot: ?*?*OpenJaiArray, capacity: usize, elem_size: usize) void {
    const slot_ptr = slot orelse @panic("array_reserve on null array slot");
    if (elem_size == 0) return;
    var array = arrayFromRuntimeValue(slot);
    if (array == null) {
        const raw = rtAlloc(@sizeOf(OpenJaiArray)) orelse return;
        array = @ptrCast(@alignCast(raw));
        array.?.* = .{ .count = 0, .capacity = 0, .data = null };
        slot_ptr.* = array;
    }
    const a = array.?;
    if (capacity <= a.capacity) return;
    const old_bytes = a.capacity * elem_size;
    const new_bytes = capacity * elem_size;
    const new_data = rtRealloc(a.data, old_bytes, new_bytes) orelse return;
    a.data = new_data;
    a.capacity = capacity;
}

export fn __openjai_array_ordered_remove_by_index(slot: ?*?*OpenJaiArray, index: i64, elem_size: usize) void {
    const a = arrayFromRuntimeValue(slot) orelse @panic("array_ordered_remove_by_index on null dynamic array");
    if (index < 0 or @as(usize, @intCast(index)) >= a.count) @panic("array_ordered_remove_by_index out of bounds");
    const idx: usize = @intCast(index);
    const data: [*]u8 = @ptrCast(a.data.?);
    const trailing = a.count - idx - 1;
    if (trailing != 0) {
        const dst = data + idx * elem_size;
        const src = data + (idx + 1) * elem_size;
        std.mem.copyForwards(u8, dst[0 .. trailing * elem_size], src[0 .. trailing * elem_size]);
    }
    a.count -= 1;
}

export fn __openjai_array_unordered_remove_by_index(slot: ?*?*OpenJaiArray, index: i64, elem_size: usize) void {
    const a = arrayFromRuntimeValue(slot) orelse @panic("array_unordered_remove_by_index on null dynamic array");
    if (index < 0 or @as(usize, @intCast(index)) >= a.count) @panic("array_unordered_remove_by_index out of bounds");
    const idx: usize = @intCast(index);
    const data: [*]u8 = @ptrCast(a.data.?);
    if (idx != a.count - 1) {
        const dst = data + idx * elem_size;
        const src = data + (a.count - 1) * elem_size;
        @memcpy(dst[0..elem_size], src[0..elem_size]);
    }
    a.count -= 1;
}

export fn __openjai_array_find(slot: ?*?*OpenJaiArray, item: ?*const anyopaque, elem_size: usize) i64 {
    const a = arrayFromRuntimeValue(slot) orelse return -1;
    const needle = item orelse return -1;
    if (a.count == 0 or a.data == null) return -1;
    const data: [*]const u8 = @ptrCast(a.data.?);
    const wanted: [*]const u8 = @ptrCast(needle);
    var i: usize = 0;
    while (i < a.count) : (i += 1) {
        if (std.mem.eql(u8, data[i * elem_size .. (i + 1) * elem_size], wanted[0..elem_size])) return @intCast(i);
    }
    return -1;
}

export fn __openjai_static_array_find(data_ptr: ?*const anyopaque, count: i64, item: ?*const anyopaque, elem_size: usize) i64 {
    const data: [*]const u8 = @ptrCast(data_ptr orelse return -1);
    const needle: [*]const u8 = @ptrCast(item orelse return -1);
    if (count <= 0) return -1;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (std.mem.eql(u8, data[i * elem_size .. (i + 1) * elem_size], needle[0..elem_size])) return @intCast(i);
    }
    return -1;
}

export fn __openjai_array_copy(source: ?*?*OpenJaiArray, elem_size: usize) ?*OpenJaiArray {
    const src = arrayFromRuntimeValue(source) orelse return null;
    const raw = rtAlloc(@sizeOf(OpenJaiArray)) orelse return null;
    const dest: *OpenJaiArray = @ptrCast(@alignCast(raw));
    const bytes = src.count * elem_size;
    const data = if (bytes == 0) null else rtAlloc(bytes) orelse {
        rtFree(raw);
        return null;
    };
    if (bytes != 0) @memcpy(@as([*]u8, @ptrCast(data.?))[0..bytes], @as([*]u8, @ptrCast(src.data.?))[0..bytes]);
    dest.* = .{ .count = src.count, .capacity = src.count, .data = data };
    return dest;
}

export fn __openjai_array_copy_to(dest_slot: ?*?*OpenJaiArray, source: ?*?*OpenJaiArray, elem_size: usize) ?*OpenJaiArray {
    const src = arrayFromRuntimeValue(source) orelse return null;
    __openjai_array_reserve(dest_slot, src.count, elem_size);
    const dest = arrayFromRuntimeValue(dest_slot) orelse return null;
    const bytes = src.count * elem_size;
    if (bytes != 0) @memcpy(@as([*]u8, @ptrCast(dest.data.?))[0..bytes], @as([*]u8, @ptrCast(src.data.?))[0..bytes]);
    dest.count = src.count;
    return dest;
}

export fn __openjai_new_array(count: usize, elem_size: usize, elem_align: usize) ?*OpenJaiArray {
    if (elem_size == 0) return null;
    const array_raw = rtAlloc(@sizeOf(OpenJaiArray)) orelse return null;
    const array: *OpenJaiArray = @ptrCast(@alignCast(array_raw));
    const bytes = count * elem_size;
    const data = if (bytes == 0) null else rtAllocAligned(bytes, elem_align) orelse {
        rtFree(array_raw);
        return null;
    };
    if (data) |ptr| @memset(@as([*]u8, @ptrCast(ptr))[0..bytes], 0);
    array.* = .{ .count = count, .capacity = count, .data = data };
    return array;
}

export fn __openjai_array_free(array: ?*OpenJaiArray) void {
    const a = array orelse return;
    rtFree(a.data);
    rtFree(a);
}

export fn __openjai_array_count(slot: ?*?*OpenJaiArray) i64 {
    const array = arrayFromRuntimeValue(slot) orelse return 0;
    return @intCast(array.count);
}

export fn __openjai_array_data(slot: ?*?*OpenJaiArray) ?*anyopaque {
    const array = arrayFromRuntimeValue(slot) orelse return null;
    return array.data;
}

export fn __openjai_array_index(slot: ?*?*OpenJaiArray, index: i64, elem_size: usize) ?*anyopaque {
    const a = arrayFromRuntimeValue(slot) orelse return null;
    if (index < 0 or @as(usize, @intCast(index)) >= a.count) {
        std.debug.print("openjai runtime: dynamic array index out of bounds: array={*} count={} index={} elem_size={}\n", .{ a, a.count, index, elem_size });
        @panic("dynamic array index out of bounds");
    }
    const data: [*]u8 = @ptrCast(a.data orelse return null);
    return data + @as(usize, @intCast(index)) * elem_size;
}

export fn __openjai_sort_dynamic_i64(slot: ?*?*OpenJaiArray) void {
    const array = arrayFromRuntimeValue(slot) orelse return;
    __openjai_sort_i64(array.data, array.count);
}

export fn __openjai_sort_dynamic_f64(slot: ?*?*OpenJaiArray) void {
    const array = arrayFromRuntimeValue(slot) orelse return;
    __openjai_sort_f64(array.data, array.count);
}

export fn __openjai_sort_dynamic_strings(slot: ?*?*OpenJaiArray) void {
    const array = arrayFromRuntimeValue(slot) orelse return;
    __openjai_sort_runtime_strings(array.data, array.count);
}

fn arrayFromRuntimeValue(value: ?*?*OpenJaiArray) ?*OpenJaiArray {
    const raw = value orelse return null;
    if (raw.* == null) return null;
    const as_header: *OpenJaiArray = @ptrCast(@alignCast(raw));
    if (as_header.capacity >= as_header.count and as_header.count < 1_000_000_000) return as_header;
    return raw.*;
}

export fn __openjai_to_calendar(low_ns: u64, timezone: i64) ?*OpenJaiCalendar {
    const raw = rtAlloc(@sizeOf(OpenJaiCalendar)) orelse return null;
    const cal: *OpenJaiCalendar = @ptrCast(@alignCast(raw));
    if (oj_rt_to_calendar(low_ns, timezone, cal) != 0) @panic("calendar conversion failed");
    return cal;
}

export fn __openjai_calendar_get_i64(calendar: ?*OpenJaiCalendar, field_id: i64) i64 {
    const cal = calendar orelse @panic("null Calendar");
    return switch (field_id) {
        0 => cal.year,
        1 => cal.month_starting_at_0,
        2 => cal.day_of_month_starting_at_0,
        3 => cal.day_of_week_starting_at_0,
        4 => cal.hour,
        5 => cal.minute,
        6 => cal.second,
        7 => cal.millisecond,
        8 => cal.time_zone,
        else => @panic("invalid Calendar field id"),
    };
}

export fn __openjai_calendar_to_string(calendar: ?*OpenJaiCalendar) ?*OpenJaiRuntimeString {
    const cal = calendar orelse @panic("null Calendar");
    const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const month_idx: usize = if (cal.month_starting_at_0 >= 0 and cal.month_starting_at_0 < 12) @intCast(cal.month_starting_at_0) else 0;
    var tmp: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&tmp, "{d} {s} {d}, {d:0>2}:{d:0>2}:{d:0>2}", .{ cal.day_of_month_starting_at_0 + 1, months[month_idx], cal.year, @as(u64, @intCast(cal.hour)), @as(u64, @intCast(cal.minute)), @as(u64, @intCast(cal.second)) }) catch unreachable;
    const header_raw = rtAlloc(@sizeOf(OpenJaiRuntimeString)) orelse return null;
    const header: *OpenJaiRuntimeString = @ptrCast(@alignCast(header_raw));
    const data_raw = rtAlloc(@max(text.len, 1)) orelse {
        rtFree(header_raw);
        return null;
    };
    const data: [*]u8 = @ptrCast(data_raw);
    @memcpy(data[0..text.len], text);
    header.* = .{ .len = text.len, .data = data };
    return header;
}

export fn __openjai_current_time_consensus_low() u64 {
    const ns = oj_rt_clock_realtime_ns();
    if (ns < 0) @panic("realtime clock failed");
    return @intCast(ns);
}

export fn __openjai_current_time_monotonic_low() u64 {
    const ns = oj_rt_clock_monotonic_ns();
    if (ns < 0) @panic("monotonic clock failed");
    return @intCast(ns);
}

export fn __openjai_get_time_seconds() f64 {
    const ns = oj_rt_clock_realtime_ns();
    if (ns < 0) @panic("realtime clock failed");
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
}

export fn __openjai_seconds_since_init() f64 {
    const ns = oj_rt_clock_monotonic_ns();
    if (ns < 0 or runtime_start_monotonic_ns < 0) @panic("monotonic clock failed");
    return @as(f64, @floatFromInt(ns - runtime_start_monotonic_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
}

export fn __openjai_to_float64_seconds(low_ns: u64) f64 {
    return @as(f64, @floatFromInt(low_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
}

export fn __openjai_random_seed(seed: u64) void {
    openjai_random_state = if (seed == 0) 0x9e3779b97f4a7c15 else seed;
}

export fn __openjai_random_get() u64 {
    var z = openjai_random_state +% 0x9e3779b97f4a7c15;
    openjai_random_state = z;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

export fn __openjai_random_get_zero_to_one() f64 {
    const bits = __openjai_random_get() >> 11;
    return @as(f64, @floatFromInt(bits)) * (1.0 / 9007199254740992.0);
}

export fn __openjai_random_get_within_range(min: f64, max: f64) f64 {
    return min + (max - min) * __openjai_random_get_zero_to_one();
}

fn writeFloatText(text: []const u8) void {
    writeAll(trimFloatText(text));
}

fn trimFloatText(text: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, text, '.')) |dot| {
        var end = text.len;
        while (end > dot + 1 and text[end - 1] == '0') end -= 1;
        if (end == dot + 1) end = dot;
        return text[0..end];
    }
    return text;
}

fn ensureBuilder(slot: ?*?*OpenJaiStringBuilder) ?*OpenJaiStringBuilder {
    const slot_ptr = slot orelse return null;
    if (slot_ptr.* == null) __openjai_string_builder_init(slot);
    return slot_ptr.*;
}

fn builderEnsure(builder: *OpenJaiStringBuilder, additional: usize) bool {
    const needed = builder.len + additional;
    if (needed <= builder.capacity) return true;
    var new_capacity: usize = if (builder.capacity == 0) 64 else builder.capacity * 2;
    while (new_capacity < needed) new_capacity *= 2;
    const new_data = rtRealloc(builder.data, builder.capacity, new_capacity) orelse return false;
    builder.data = new_data;
    builder.capacity = new_capacity;
    return true;
}

fn writeAll(bytes: []const u8) void {
    var index: usize = 0;
    while (index < bytes.len) {
        const wrote = oj_rt_write(1, bytes[index..].ptr, bytes.len - index);
        if (wrote < 0) @panic("stdout write failed");
        if (wrote == 0) @panic("stdout write made no progress");
        index += @intCast(wrote);
    }
}


fn rtAlloc(size: usize) ?*anyopaque {
    return rtAllocAligned(size, runtime_allocation_alignment);
}

fn rtAllocOwned(size: usize, owner_proc: i64, owner_data: usize, default_alias: bool) ?*anyopaque {
    return rtAllocAlignedOwned(size, runtime_allocation_alignment, owner_proc, owner_data, default_alias);
}

fn rtAllocAligned(size: usize, alignment: usize) ?*anyopaque {
    return rtAllocAlignedOwned(size, alignment, allocator_proc_default, 0, false);
}

fn rtAllocAlignedOwned(size: usize, alignment: usize, owner_proc: i64, owner_data: usize, default_alias: bool) ?*anyopaque {
    const requested_len = @max(size, 1);
    const requested_alignment = normalizeAlignment(alignment);
    const header_len = allocationHeaderLen();
    const mapped_len = header_len + requested_alignment - 1 + requested_len;
    const raw = oj_rt_mmap(mapped_len) orelse return null;
    const raw_addr = @intFromPtr(raw);
    const data_addr = alignForward(raw_addr + header_len, requested_alignment);
    const header_addr = data_addr - header_len;
    const header: *RuntimeAllocationHeader = @ptrFromInt(header_addr);
    header.* = .{
        .magic = runtime_allocation_magic,
        .mapped_addr = raw_addr,
        .mapped_len = mapped_len,
        .requested_len = requested_len,
        .owner_proc = owner_proc,
        .owner_data = owner_data,
        .default_alias = if (default_alias) 1 else 0,
    };
    return @ptrFromInt(data_addr);
}

fn rtRealloc(ptr: ?*anyopaque, old_size: usize, new_size: usize) ?*anyopaque {
    return rtReallocOwned(ptr, old_size, new_size, allocator_proc_default, 0, false);
}

fn rtReallocOwned(ptr: ?*anyopaque, old_size: usize, new_size: usize, owner_proc: i64, owner_data: usize, default_alias: bool) ?*anyopaque {
    const old = ptr orelse return rtAllocOwned(new_size, owner_proc, owner_data, default_alias);
    if (new_size == 0) {
        rtFree(old);
        return null;
    }
    const header = allocationHeader(old);
    const preserved_len = @min(@min(header.requested_len, old_size), new_size);
    const new_ptr = rtAllocOwned(new_size, owner_proc, owner_data, default_alias) orelse return null;
    @memcpy(@as([*]u8, @ptrCast(new_ptr))[0..preserved_len], @as([*]const u8, @ptrCast(old))[0..preserved_len]);
    rtFree(old);
    return new_ptr;
}

fn findPoolState(key: usize) ?*OpenJaiPoolState {
    var cursor = pool_states;
    while (cursor) |state| {
        if (state.key == key) return state;
        cursor = state.next;
    }
    return null;
}

fn ensurePoolState(key: usize) ?*OpenJaiPoolState {
    if (findPoolState(key)) |state| return state;
    const raw = rtAlloc(@sizeOf(OpenJaiPoolState)) orelse return null;
    const state: *OpenJaiPoolState = @ptrCast(@alignCast(raw));
    state.* = .{ .key = key, .bytes_left = 0, .next = pool_states };
    pool_states = state;
    return state;
}

fn chargePool(key: usize, size: i64) void {
    const state = ensurePoolState(key) orelse return;
    chargePoolState(state, size);
}

fn chargePoolState(state: *OpenJaiPoolState, size: i64) void {
    const consumed = alignForward(@as(usize, @intCast(@max(size, 0))) + 8, 8);
    if (state.bytes_left <= 0) state.bytes_left = 65536;
    state.bytes_left = @max(state.bytes_left - @as(i64, @intCast(consumed)), 0);
}

fn chargePoolStateRaw(state: *OpenJaiPoolState, size: i64) void {
    const consumed = alignForward(@as(usize, @intCast(@max(size, 0))), 8);
    if (state.bytes_left <= 0) state.bytes_left = 65536;
    state.bytes_left = @max(state.bytes_left - @as(i64, @intCast(consumed)), 0);
}

fn rtFree(ptr: ?*anyopaque) void {
    const p = ptr orelse return;
    const header = allocationHeader(p);
    header.magic = 0;
    oj_rt_munmap(@ptrFromInt(header.mapped_addr), header.mapped_len);
}

fn allocationHeader(ptr: *anyopaque) *RuntimeAllocationHeader {
    return findAllocationHeader(ptr) orelse @panic("free called with pointer not allocated by OpenJai runtime");
}

fn findAllocationHeader(ptr: *anyopaque) ?*RuntimeAllocationHeader {
    const ptr_addr = @intFromPtr(ptr);
    const header_len = allocationHeaderLen();
    const exact_addr = ptr_addr -% header_len;
    if (candidateAllocationHeader(exact_addr, ptr_addr)) |header| return header;

    const page_start = ptr_addr & ~(@as(usize, std.heap.page_size_min) - 1);
    var candidate = exact_addr & ~(@as(usize, runtime_allocation_alignment) - 1);
    while (candidate >= page_start) : (candidate -%= runtime_allocation_alignment) {
        if (candidateAllocationHeader(candidate, ptr_addr)) |header| return header;
        if (candidate < page_start + runtime_allocation_alignment) break;
    }
    return null;
}

fn candidateAllocationHeader(candidate_addr: usize, ptr_addr: usize) ?*RuntimeAllocationHeader {
    if (candidate_addr == 0 or candidate_addr % @alignOf(RuntimeAllocationHeader) != 0) return null;
    const header: *RuntimeAllocationHeader = @ptrFromInt(candidate_addr);
    if (header.magic != runtime_allocation_magic) return null;
    const data_start = candidate_addr + allocationHeaderLen();
    const data_end = data_start + header.requested_len;
    if (ptr_addr < data_start or ptr_addr > data_end) return null;
    if (ptr_addr < header.mapped_addr or ptr_addr >= header.mapped_addr + header.mapped_len) return null;
    return header;
}

fn allocationHeaderLen() usize {
    return alignForward(@sizeOf(RuntimeAllocationHeader), runtime_allocation_alignment);
}

fn alignForward(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(alignment - 1);
}

fn normalizeAlignment(alignment: usize) usize {
    var normalized = @max(alignment, runtime_allocation_alignment);
    if (!std.math.isPowerOfTwo(normalized)) normalized = std.math.ceilPowerOfTwoAssert(usize, normalized);
    return normalized;
}

var type_info_table: ?[*]const TypeInfoEntry = null;
var type_info_count: usize = 0;

const TypeInfoMemberEntry = extern struct {
    name_ptr: [*]const u8,
    name_len: u64,
    type_name_ptr: [*]const u8,
    type_name_len: u64,
    flags: u64,
};

const TypeInfoEntry = extern struct {
    name_ptr: [*]const u8,
    name_len: u64,
    tag: u64,
    member_count: u64,
    members: [*]const TypeInfoMemberEntry,
};

export fn __openjai_set_type_info_table(table: [*]const TypeInfoEntry, count: usize) void {
    type_info_table = table;
    type_info_count = count;
}

export fn __openjai_type_info_name(type_id: i64) ?*OpenJaiRuntimeString {
    if (type_id < 0 or @as(usize, @intCast(type_id)) >= type_info_count) return makeRuntimeString("<?>");
    const idx: usize = @intCast(type_id);
    const entry = type_info_table.?[idx];
    return makeRuntimeString(entry.name_ptr[0..entry.name_len]);
}

export fn __openjai_type_info_tag_name(type_id: i64) ?*OpenJaiRuntimeString {
    if (type_id < 0 or @as(usize, @intCast(type_id)) >= type_info_count) return makeRuntimeString("<type>");
    const idx: usize = @intCast(type_id);
    const entry = type_info_table.?[idx];
    return makeRuntimeString(tagNameFromId(entry.tag));
}

fn tagNameFromId(tag: u64) []const u8 {
    // Must match typeInfoTagValue() in bytecode_gen.zig
    return switch (tag) {
        1 => "INTEGER",
        2 => "FLOAT",
        3 => "BOOL",
        4 => "POINTER",
        5 => "ARRAY",
        6 => "STRUCT",
        7 => "ENUM",
        8 => "PROCEDURE",
        9 => "STRING",
        else => "<type>",
    };
}

export fn auto_release_temp() void {}

export fn __openjai_type_info_lookup(name_ptr: [*]const u8, name_len: usize) i64 {
    const name = name_ptr[0..name_len];
    const table = type_info_table orelse return -1;
    for (0..type_info_count) |i| {
        const entry = table[i];
        if (entry.name_len == name_len and std.mem.eql(u8, entry.name_ptr[0..entry.name_len], name)) return @intCast(i);
    }
    return -1;
}

export fn __openjai_type_info_get_members(type_id: i64) ?*OpenJaiArray {
    if (type_id < 0 or @as(usize, @intCast(type_id)) >= type_info_count) return null;
    const idx: usize = @intCast(type_id);
    const entry = type_info_table.?[idx];
    const members_ptr = entry.members;
    const count = entry.member_count;
    // Allocate a dynamic array and populate it with copies of member entries
    const array_raw = rtAlloc(@sizeOf(OpenJaiArray)) orelse return null;
    const array: *OpenJaiArray = @ptrCast(@alignCast(array_raw));
    if (count == 0) {
        array.* = .{ .count = 0, .capacity = 0, .data = null };
        return array;
    }
    // Each element is a full TypeInfoMemberEntry (40 bytes on 64-bit)
    const elem_size = @sizeOf(TypeInfoMemberEntry);
    const data_size = count * elem_size;
    const data = rtAlloc(data_size) orelse return null;
    const entries: [*]TypeInfoMemberEntry = @ptrCast(@alignCast(data));
    for (0..count) |i| {
        entries[i] = members_ptr[i];
    }
    array.* = .{ .count = count, .capacity = count, .data = data };
    return array;
}

export fn __openjai_type_info_member_name(member_ptr: ?*const TypeInfoMemberEntry) ?*OpenJaiRuntimeString {
    const member = member_ptr orelse return makeRuntimeString("");
    return makeRuntimeString(member.name_ptr[0..member.name_len]);
}

export fn __openjai_type_info_member_type_name(member_ptr: ?*const TypeInfoMemberEntry) ?*OpenJaiRuntimeString {
    const member = member_ptr orelse return makeRuntimeString("");
    return makeRuntimeString(member.type_name_ptr[0..member.type_name_len]);
}

export fn __openjai_type_info_member_int_field(member_ptr: ?*const TypeInfoMemberEntry, field_id: i64) i64 {
    const member = member_ptr orelse return 0;
    return switch (field_id) {
        0 => @intCast(member.flags), // flags
        1 => 0, // offset_in_bytes (placeholder)
        else => 0,
    };
}

export fn __openjai_type_info_int_field(type_id: i64, field_id: i64) i64 {
    if (type_id < 0 or @as(usize, @intCast(type_id)) >= type_info_count) return 0;
    const idx: usize = @intCast(type_id);
    const entry = type_info_table.?[idx];
    return switch (field_id) {
        1 => 0, // runtime_size (placeholder)
        2 => @intCast(entry.tag),
        3 => @intCast(entry.member_count), // count (members count)
        4 => 0, // signed
        5 => 0, // enum_type_flags
        6 => 0, // internal_type
        else => 0,
    };
}

