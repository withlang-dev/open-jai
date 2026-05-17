const std = @import("std");

pub const Diagnostic = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    source: []const u8,
    silent: bool = false,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8, source: []const u8) Diagnostic {
        return .{ .allocator = allocator, .file_path = file_path, .source = source };
    }

    pub fn asSilent(d: Diagnostic) Diagnostic {
        return .{ .allocator = d.allocator, .file_path = d.file_path, .source = d.source, .silent = true };
    }

    pub fn nop() Diagnostic {
        return .{ .allocator = std.heap.page_allocator, .file_path = "", .source = "", .silent = true };
    }

    pub fn failAt(d: Diagnostic, offset: usize, comptime fmt: []const u8, args: anytype) Error {
        if (!d.silent) {
            const lc = d.lineCol(offset);
            std.debug.print("{s}:{d}:{d}: error: ", .{ d.file_path, lc.line, lc.col });
            std.debug.print(fmt, args);
            std.debug.print("\n", .{});
            d.printLine(lc.line, lc.line_start, lc.line_end, offset);
        }
        return error.CompilationFailed;
    }

    pub fn noteAt(d: Diagnostic, offset: usize, comptime fmt: []const u8, args: anytype) void {
        if (d.silent) return;
        const lc = d.lineCol(offset);
        std.debug.print("{s}:{d}:{d}: note: ", .{ d.file_path, lc.line, lc.col });
        std.debug.print(fmt, args);
        std.debug.print("\n", .{});
    }

    const LineCol = struct { line: usize, col: usize, line_start: usize, line_end: usize };

    pub fn lineCol(d: Diagnostic, offset_raw: usize) LineCol {
        const offset = @min(offset_raw, d.source.len);
        var line: usize = 1;
        var line_start: usize = 0;
        var i: usize = 0;
        while (i < offset) : (i += 1) {
            if (d.source[i] == '\n') {
                line += 1;
                line_start = i + 1;
            }
        }
        var line_end = line_start;
        while (line_end < d.source.len and d.source[line_end] != '\n') : (line_end += 1) {}
        return .{ .line = line, .col = offset - line_start + 1, .line_start = line_start, .line_end = line_end };
    }

    fn printLine(d: Diagnostic, line: usize, start: usize, end: usize, offset: usize) void {
        _ = line;
        if (start > d.source.len or end > d.source.len or start > end) return;
        const text = d.source[start..end];
        std.debug.print("    {s}\n    ", .{text});
        const caret_col = @min(offset, end) - start;
        var i: usize = 0;
        while (i < caret_col) : (i += 1) {
            const c = if (i < text.len) text[i] else ' ';
            const ch: u8 = if (c == '\t') '\t' else ' ';
            std.debug.print("{c}", .{ch});
        }
        std.debug.print("^\n", .{});
    }
};

pub const Error = error{CompilationFailed};
