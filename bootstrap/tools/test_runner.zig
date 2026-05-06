/// Integration test runner for the OpenJai bootstrap compiler.
///
/// Usage:
///   test_runner <compiler> <runtime.o> <examples_dir> [--filter <substring>]
///
/// For each .jai file under examples_dir that contains at least one `// =>`
/// annotation, the runner:
///   1. Extracts expected output lines from `// => <text>` comments (one line each).
///   2. Compiles the file with <compiler> --runtime <runtime.o>.
///   3. Runs the resulting binary and captures stdout.
///   4. Compares actual stdout lines against expected lines (in order).
///   5. Prints PASS or FAIL with a diff on mismatch.
///
/// Exit code: 0 if all annotated tests pass, 1 if any fail.
const std = @import("std");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_it.next(); // skip argv[0]

    const compiler_path = args_it.next() orelse fatal("usage: test_runner <compiler> <runtime.o> <examples_dir> [--filter <substring>]");
    const runtime_path = args_it.next() orelse fatal("usage: test_runner <compiler> <runtime.o> <examples_dir> [--filter <substring>]");
    const examples_dir_path = args_it.next() orelse fatal("usage: test_runner <compiler> <runtime.o> <examples_dir> [--filter <substring>]");

    var filter: ?[]const u8 = null;
    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--filter")) {
            filter = args_it.next();
        }
    }

    // Collect .jai files, sorted for deterministic output.
    var jai_files: std.ArrayList([]u8) = .empty;
    defer {
        for (jai_files.items) |f| allocator.free(f);
        jai_files.deinit(allocator);
    }
    try collectJaiFiles(allocator, io, examples_dir_path, &jai_files);
    std.mem.sort([]u8, jai_files.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Create a temporary directory for compiled binaries.
    const tmp_path = try makeTempDir(allocator, io);
    defer {
        Dir.deleteTree(.cwd(), io, tmp_path) catch {};
        allocator.free(tmp_path);
    }

    var pass_count: usize = 0;
    var fail_count: usize = 0;
    var skip_count: usize = 0;

    for (jai_files.items) |jai_path| {
        if (filter) |f| {
            if (std.mem.indexOf(u8, jai_path, f) == null) continue;
        }

        const result = runTest(allocator, io, jai_path, compiler_path, runtime_path, tmp_path) catch |err| {
            std.debug.print("FAIL  {s}\n      internal error: {s}\n", .{ jai_path, @errorName(err) });
            fail_count += 1;
            continue;
        };
        switch (result) {
            .skipped => skip_count += 1,
            .passed => {
                std.debug.print("PASS  {s}\n", .{jai_path});
                pass_count += 1;
            },
            .failed => |msg| {
                std.debug.print("FAIL  {s}\n{s}\n", .{ jai_path, msg });
                allocator.free(msg);
                fail_count += 1;
            },
        }
    }

    std.debug.print("\n{d} passed, {d} failed, {d} skipped\n", .{ pass_count, fail_count, skip_count });
    if (fail_count > 0) std.process.exit(1);
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("{s}\n", .{msg});
    std.process.exit(1);
}

const TestResult = union(enum) {
    skipped,
    passed,
    failed: []u8, // owned diagnostic message
};

fn runTest(
    allocator: std.mem.Allocator,
    io: std.Io,
    jai_path: []const u8,
    compiler: []const u8,
    runtime: []const u8,
    tmp_dir: []const u8,
) !TestResult {
    // Read source and extract expected lines.
    const source = Dir.readFileAlloc(.cwd(), io, jai_path, allocator, .unlimited) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "      could not read file: {s}\n", .{@errorName(err)});
        return .{ .failed = msg };
    };
    defer allocator.free(source);

    var expected: std.ArrayList([]const u8) = .empty;
    defer expected.deinit(allocator);
    try extractExpected(source, allocator, &expected);

    if (expected.items.len == 0) return .skipped;

    // Derive a stable output name from the source path.
    const basename = std.fs.path.stem(std.fs.path.basename(jai_path));
    const bin_path = try std.fs.path.join(allocator, &.{ tmp_dir, basename });
    defer allocator.free(bin_path);

    // Compile.
    {
        const compile_result = try std.process.run(allocator, io, .{
            .argv = &.{ compiler, jai_path, "-o", bin_path, "--runtime", runtime },
        });
        defer allocator.free(compile_result.stdout);
        defer allocator.free(compile_result.stderr);

        const ok = switch (compile_result.term) {
            .exited => |code| code == 0,
            else => false,
        };
        if (!ok) {
            const msg = try std.fmt.allocPrint(allocator,
                "      compile failed ({}):\n{s}{s}",
                .{ compile_result.term, compile_result.stdout, compile_result.stderr },
            );
            return .{ .failed = msg };
        }
    }

    // Run the compiled binary.
    const run_result = try std.process.run(allocator, io, .{
        .argv = &.{bin_path},
    });
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);

    const run_ok = switch (run_result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!run_ok) {
        const msg = try std.fmt.allocPrint(allocator,
            "      binary exited with non-zero status ({}):\n{s}{s}",
            .{ run_result.term, run_result.stdout, run_result.stderr },
        );
        return .{ .failed = msg };
    }

    // Split actual output into lines.
    var actual_lines: std.ArrayList([]const u8) = .empty;
    defer actual_lines.deinit(allocator);
    var line_it = std.mem.splitScalar(u8, run_result.stdout, '\n');
    while (line_it.next()) |line| {
        // The empty string after a trailing newline is not a real line.
        if (line_it.rest().len == 0 and line.len == 0) break;
        try actual_lines.append(allocator, line);
    }

    // Check that every expected annotation text appears somewhere in actual output
    // (as a substring of an actual line), in order. When a line is not found,
    // restore actual_idx so subsequent expected lines can still be found.
    var actual_idx: usize = 0;
    var mismatches: std.ArrayList(u8) = .empty;
    defer mismatches.deinit(allocator);

    for (expected.items) |exp_line| {
        var found = false;
        const saved_idx = actual_idx;
        while (actual_idx < actual_lines.items.len) {
            // Use substring match: annotation text may be a suffix/part of the full output line.
            if (std.mem.indexOf(u8, actual_lines.items[actual_idx], exp_line) != null) {
                actual_idx += 1;
                found = true;
                break;
            }
            actual_idx += 1;
        }
        if (!found) {
            // Restore position so subsequent expected lines can still be found.
            actual_idx = saved_idx;
            try mismatches.print(allocator,
                "      expected annotation not found in output: \"{s}\"\n",
                .{exp_line},
            );
        }
    }

    if (mismatches.items.len > 0) {
        var msg_buf: std.ArrayList(u8) = .empty;
        try msg_buf.appendSlice(allocator, mismatches.items);
        try msg_buf.print(allocator, "      actual stdout:\n", .{});
        for (actual_lines.items) |line| {
            try msg_buf.print(allocator, "        \"{s}\"\n", .{line});
        }
        return .{ .failed = try msg_buf.toOwnedSlice(allocator) };
    }

    return .passed;
}

/// Extract expected output lines from `// =>` annotations in source.
/// Each annotation contributes exactly one expected line (text after `=> `).
/// Skips annotations that appear inside already-commented-out code lines
/// (i.e., lines where `//` appears before the `// =>` marker).
fn extractExpected(source: []const u8, allocator: std.mem.Allocator, out: *std.ArrayList([]const u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const marker = "// =>";
        const pos = std.mem.indexOf(u8, line, marker) orelse continue;
        // Skip if there is another `//` before this `// =>` on the same line.
        // That means the annotation is inside a commented-out code line.
        const before = line[0..pos];
        if (std.mem.indexOf(u8, before, "//") != null) continue;
        const after_marker = line[pos + marker.len ..];
        // Strip exactly one leading space if present.
        const text = if (after_marker.len > 0 and after_marker[0] == ' ')
            after_marker[1..]
        else
            after_marker;
        // Skip empty annotations and Error: annotations (compile-time error docs).
        if (text.len == 0) continue;
        if (std.mem.startsWith(u8, text, "Error:")) continue;
        if (std.mem.startsWith(u8, text, "(")) continue; // e.g. "(4) Error: ..."
        try out.append(allocator, text);
    }
}

/// Recursively collect all `.jai` files under `dir_path`.
fn collectJaiFiles(allocator: std.mem.Allocator, io: std.Io, dir_path: []const u8, out: *std.ArrayList([]u8)) !void {
    const dir = try Dir.openDir(.cwd(), io, dir_path, .{ .iterate = true });
    var walker = try Dir.walk(dir, allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".jai")) continue;
        const full = try std.fs.path.join(allocator, &.{ dir_path, entry.path });
        try out.append(allocator, full);
    }
}

/// Create a temporary directory with a unique name and return its path (caller owns).
fn makeTempDir(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    const pid = std.c.getpid();
    const tmp_path = try std.fmt.allocPrint(allocator, "/tmp/openjai_test_{d}", .{pid});
    errdefer allocator.free(tmp_path);
    Dir.createDirPath(.cwd(), io, tmp_path) catch {};
    return tmp_path;
}
