const std = @import("std");
const Dir = std.Io.Dir;

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const Ast = @import("Ast.zig").Ast;
const Node = @import("Ast.zig").Node;
const NodeIndex = @import("Ast.zig").NodeIndex;
const Diagnostic = @import("diagnostics.zig").Diagnostic;

const TestKind = union(enum) {
    dynamic_compile_success: []const u8,
    proc: ProcTest,
};

const ProcTest = struct {
    file_path: []const u8,
    source: []const u8,
    proc_name: []const u8,
    proc_node: NodeIndex,
    ast: *Ast,
};

const TestCase = struct {
    display_name: []const u8,
    kind: TestKind,
};

const TestOutcome = struct {
    passed: bool,
    asserts: usize,
    message: []const u8 = "",
};

const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    compiler_path: []const u8,
    runtime_path: []const u8,
    repo_root: []const u8,
    output_dir: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_it.next();
    const compiler_path = args_it.next() orelse fatal("usage: openjai_test_runner <compiler> <runtime.o> <repo-root>");
    const runtime_path = args_it.next() orelse fatal("usage: openjai_test_runner <compiler> <runtime.o> <repo-root>");
    const repo_root = args_it.next() orelse fatal("usage: openjai_test_runner <compiler> <runtime.o> <repo-root>");

    const output_dir = try std.fs.path.join(allocator, &.{ repo_root, "out", "test", "openjai" });
    defer allocator.free(output_dir);
    const reports_dir = try std.fs.path.join(allocator, &.{ repo_root, "test", "reports" });
    defer allocator.free(reports_dir);
    try Dir.cwd().createDirPath(io, output_dir);
    try Dir.cwd().createDirPath(io, reports_dir);

    var ctx = Context{
        .allocator = allocator,
        .io = io,
        .compiler_path = compiler_path,
        .runtime_path = runtime_path,
        .repo_root = repo_root,
        .output_dir = output_dir,
    };

    var parsed_files: std.ArrayList(ParsedFile) = .empty;
    defer {
        for (parsed_files.items) |*pf| pf.deinit(allocator);
        parsed_files.deinit(allocator);
    }

    var tests: std.ArrayList(TestCase) = .empty;
    defer {
        for (tests.items) |test_case| allocator.free(test_case.display_name);
        tests.deinit(allocator);
    }

    const test_examples_dir = try std.fs.path.join(allocator, &.{ repo_root, "test", "examples" });
    defer allocator.free(test_examples_dir);
    var test_files: std.ArrayList([]u8) = .empty;
    defer freeStringList(allocator, &test_files);
    try collectJaiFiles(allocator, io, test_examples_dir, &test_files);
    sortStrings(test_files.items);
    try parsed_files.ensureTotalCapacity(allocator, test_files.items.len);
    for (test_files.items) |path| try discoverProcTests(allocator, io, path, &parsed_files, &tests);

    const examples_dir = try std.fs.path.join(allocator, &.{ repo_root, "examples" });
    defer allocator.free(examples_dir);
    var example_files: std.ArrayList([]u8) = .empty;
    defer freeStringList(allocator, &example_files);
    try collectJaiFiles(allocator, io, examples_dir, &example_files);
    sortStrings(example_files.items);
    var loaded_example_files: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var key_it = loaded_example_files.keyIterator();
        while (key_it.next()) |key| allocator.free(key.*);
        loaded_example_files.deinit(allocator);
    }
    try collectLoadedExampleFiles(allocator, io, example_files.items, &loaded_example_files);
    for (example_files.items) |path| {
        if (!isSupportedExamplePath(path)) continue;
        if (loaded_example_files.contains(path) and !try sourceHasMainEntry(io, path, allocator)) continue;
        const rel = try relativeToRoot(allocator, repo_root, path);
        defer allocator.free(rel);
        const display = try std.fmt.allocPrint(allocator, "{s}::compiles", .{rel});
        try tests.append(allocator, .{ .display_name = display, .kind = .{ .dynamic_compile_success = path } });
    }

    var report = std.ArrayList(u8).empty;
    defer report.deinit(allocator);
    try report.print(allocator, "OpenJai tests\n\n", .{});

    std.debug.print("OpenJai tests\n", .{});
    var passed: usize = 0;
    var failed: usize = 0;
    var asserts: usize = 0;
    for (tests.items) |test_case| {
        const outcome = runTest(&ctx, test_case) catch |err| blk: {
            const msg = try std.fmt.allocPrint(allocator, "internal error: {s}", .{@errorName(err)});
            break :blk TestOutcome{ .passed = false, .asserts = 1, .message = msg };
        };
        defer if (outcome.message.len != 0) allocator.free(outcome.message);
        asserts += outcome.asserts;
        if (outcome.passed) {
            passed += 1;
            std.debug.print("  PASS {s} ({d} assert{s})\n", .{ test_case.display_name, outcome.asserts, if (outcome.asserts == 1) "" else "s" });
            try report.print(allocator, "PASS {s} ({d} assert{s})\n", .{ test_case.display_name, outcome.asserts, if (outcome.asserts == 1) "" else "s" });
        } else {
            failed += 1;
            std.debug.print("  FAIL {s} ({d} assert{s})\n", .{ test_case.display_name, outcome.asserts, if (outcome.asserts == 1) "" else "s" });
            if (outcome.message.len != 0) std.debug.print("       {s}\n", .{outcome.message});
            try report.print(allocator, "FAIL {s} ({d} assert{s})\n", .{ test_case.display_name, outcome.asserts, if (outcome.asserts == 1) "" else "s" });
            if (outcome.message.len != 0) try report.print(allocator, "     {s}\n", .{outcome.message});
        }
    }

    const total = passed + failed;
    std.debug.print("\nSummary: {d} tests, {d} asserts, {d} failed\n", .{ total, asserts, failed });
    std.debug.print("Report: test/reports/latest.txt\n", .{});
    try report.print(allocator, "\nSummary: {d} tests, {d} asserts, {d} failed\n", .{ total, asserts, failed });
    const report_path = try std.fs.path.join(allocator, &.{ reports_dir, "latest.txt" });
    defer allocator.free(report_path);
    try Dir.cwd().writeFile(io, .{ .sub_path = report_path, .data = report.items });

    if (failed != 0) std.process.exit(1);
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("{s}\n", .{msg});
    std.process.exit(64);
}

const ParsedFile = struct {
    path: []u8,
    source: []u8,
    ast: Ast,

    fn deinit(pf: *ParsedFile, allocator: std.mem.Allocator) void {
        allocator.free(pf.path);
        allocator.free(pf.source);
        allocator.free(pf.ast.tokens);
        pf.ast.deinit();
    }
};

fn discoverProcTests(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    parsed_files: *std.ArrayList(ParsedFile),
    tests: *std.ArrayList(TestCase),
) !void {
    const source = try Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024));
    errdefer allocator.free(source);
    const diag = Diagnostic.init(allocator, path, source);
    var tokens = try lexer.tokenize(allocator, source, diag);
    defer tokens.deinit(allocator);
    const slice = tokens.slice();
    var ast = try parser.parse(allocator, source, slice.items(.tag), slice.items(.start), slice.items(.end), diag);
    errdefer {
        allocator.free(ast.tokens);
        ast.deinit();
    }
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    try parsed_files.append(allocator, .{ .path = owned_path, .source = source, .ast = ast });
    const pf = &parsed_files.items[parsed_files.items.len - 1];

    const decls = pf.ast.extraSlice(pf.ast.data(pf.ast.root).lhs);
    for (decls) |decl_idx| {
        const decl: NodeIndex = @intCast(decl_idx);
        if (pf.ast.tag(decl) != .proc_decl or !pf.ast.hasNote(decl, "TestProcedure")) continue;
        const sig = pf.ast.extraSlice(pf.ast.data(decl).rhs);
        const params = if (sig.len >= 1) pf.ast.extraSlice(sig[0]) else &.{};
        const name = pf.ast.tokenSlice(pf.ast.mainToken(decl));
        if (params.len != 0) {
            std.debug.print("[Test Suite] WARNING: {s}::{s} tagged @TestProcedure but takes arguments; skipping.\n", .{ path, name });
            continue;
        }
        const display = try std.fmt.allocPrint(allocator, "{s}::{s}", .{ path, name });
        try tests.append(allocator, .{
            .display_name = display,
            .kind = .{ .proc = .{
                .file_path = pf.path,
                .source = pf.source,
                .proc_name = name,
                .proc_node = decl,
                .ast = &pf.ast,
            } },
        });
    }
}

fn runTest(ctx: *Context, test_case: TestCase) !TestOutcome {
    return switch (test_case.kind) {
        .dynamic_compile_success => |path| try expectCompileSuccess(ctx, path),
        .proc => |proc_test| try runProcTest(ctx, proc_test),
    };
}

fn runProcTest(ctx: *Context, proc_test: ProcTest) !TestOutcome {
    const ast = proc_test.ast;
    const body = ast.data(proc_test.proc_node).lhs;
    var asserts: usize = 0;
    var failures = std.ArrayList(u8).empty;
    defer failures.deinit(ctx.allocator);
    for (ast.extraSlice(ast.data(body).lhs)) |stmt_idx| {
        const stmt: NodeIndex = @intCast(stmt_idx);
        if (ast.tag(stmt) != .expr_stmt) {
            try failures.print(ctx.allocator, "{}: unsupported statement in test procedure\n", .{sourceLocation(ast, proc_test.file_path, stmt)});
            asserts += 1;
            continue;
        }
        const expr = ast.data(stmt).lhs;
        if (ast.tag(expr) != .call_expr) {
            try failures.print(ctx.allocator, "{}: unsupported expression in test procedure\n", .{sourceLocation(ast, proc_test.file_path, expr)});
            asserts += 1;
            continue;
        }
        const callee = ast.data(expr).lhs;
        if (ast.tag(callee) != .identifier) {
            try failures.print(ctx.allocator, "{}: unsupported callee in test procedure\n", .{sourceLocation(ast, proc_test.file_path, expr)});
            asserts += 1;
            continue;
        }
        const name = ast.tokenSlice(ast.mainToken(callee));
        const args = ast.extraSlice(ast.data(expr).rhs);
        if (std.mem.eql(u8, name, "expect_compile_success")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const result = try expectCompileSuccess(ctx, full_path);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_compile_failure")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const expected = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(expected);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const result = try expectCompileFailure(ctx, full_path, expected);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_compile_output")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const expected = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(expected);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const result = try expectCompileOutput(ctx, full_path, expected, .exact);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_compile_output_contains")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const needle = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(needle);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const result = try expectCompileOutput(ctx, full_path, needle, .contains);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_compile_output_contains_with_arg")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const arg = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(arg);
            const needle = try stringArg(ctx.allocator, ast, args, 2, expr);
            defer ctx.allocator.free(needle);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const extra_args = [_][]const u8{arg};
            const result = try expectCompileOutputArgs(ctx, full_path, needle, .contains, extra_args[0..]);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_compile_creates_file")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const output_path = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(output_path);
            const expected = try stringArg(ctx.allocator, ast, args, 2, expr);
            defer ctx.allocator.free(expected);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const full_output_path = try pathFromRepo(ctx.allocator, ctx.repo_root, output_path);
            defer ctx.allocator.free(full_output_path);
            const result = try expectCompileCreatesFile(ctx, full_path, full_output_path, expected);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_compile_creates_program_output")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const program_path = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(program_path);
            const expected = try stringArg(ctx.allocator, ast, args, 2, expr);
            defer ctx.allocator.free(expected);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const full_program_path = try pathFromRepo(ctx.allocator, ctx.repo_root, program_path);
            defer ctx.allocator.free(full_program_path);
            const result = try expectCompileCreatesProgramOutput(ctx, full_path, full_program_path, expected);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_program_output")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const expected = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(expected);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const result = try expectProgramOutput(ctx, full_path, expected, .exact);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_program_output_contains")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const needle = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(needle);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const result = try expectProgramOutput(ctx, full_path, needle, .contains);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_example_annotations")) {
            asserts += 1;
            const path = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(path);
            const full_path = try pathFromRepo(ctx.allocator, ctx.repo_root, path);
            defer ctx.allocator.free(full_path);
            const result = try expectExampleAnnotations(ctx, full_path);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "expect_compiler_command_output")) {
            asserts += 1;
            const arg = try stringArg(ctx.allocator, ast, args, 0, expr);
            defer ctx.allocator.free(arg);
            const expected = try stringArg(ctx.allocator, ast, args, 1, expr);
            defer ctx.allocator.free(expected);
            const result = try expectCompilerCommandOutput(ctx, arg, expected);
            if (!result.passed) try failures.print(ctx.allocator, "{s}", .{result.message});
            if (result.message.len != 0) ctx.allocator.free(result.message);
        } else if (std.mem.eql(u8, name, "assert")) {
            asserts += 1;
            if (args.len == 0) {
                try failures.print(ctx.allocator, "{}: assert expects a condition\n", .{sourceLocation(ast, proc_test.file_path, expr)});
                continue;
            }
            const value = evalBool(ast, @intCast(args[0])) catch |err| {
                try failures.print(ctx.allocator, "{}: unsupported assert expression: {s}\n", .{ sourceLocation(ast, proc_test.file_path, @intCast(args[0])), @errorName(err) });
                continue;
            };
            if (!value) {
                if (args.len > 1 and ast.tag(@intCast(args[1])) == .string_literal) {
                    const msg = try decodeStringLiteral(ctx.allocator, ast.stringTokenContents(ast.mainToken(@intCast(args[1]))));
                    defer ctx.allocator.free(msg);
                    try failures.print(ctx.allocator, "{}: assert failed: {s}\n", .{ sourceLocation(ast, proc_test.file_path, @intCast(args[0])), msg });
                } else {
                    try failures.print(ctx.allocator, "{}: assert failed\n", .{sourceLocation(ast, proc_test.file_path, @intCast(args[0]))});
                }
            }
        } else {
            asserts += 1;
            try failures.print(ctx.allocator, "{}: unsupported test helper '{s}'\n", .{ sourceLocation(ast, proc_test.file_path, expr), name });
        }
    }
    if (failures.items.len == 0) return .{ .passed = true, .asserts = asserts };
    return .{ .passed = false, .asserts = asserts, .message = try failures.toOwnedSlice(ctx.allocator) };
}

fn expectExampleAnnotations(ctx: *Context, path: []const u8) !TestOutcome {
    const source = try Dir.cwd().readFileAlloc(ctx.io, path, ctx.allocator, .limited(64 * 1024 * 1024));
    defer ctx.allocator.free(source);
    var expected: std.ArrayList([]const u8) = .empty;
    defer expected.deinit(ctx.allocator);
    try extractExpectedAnnotations(source, ctx.allocator, &expected);
    if (expected.items.len == 0) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "no // => annotations found in {s}", .{path});
        return .{ .passed = false, .asserts = 1, .message = msg };
    }

    const out = try outputPathFor(ctx, path);
    defer ctx.allocator.free(out);
    const compile_result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = &.{ ctx.compiler_path, path, "-o", out, "--runtime", ctx.runtime_path },
        .cwd = .{ .path = ctx.repo_root },
    });
    defer ctx.allocator.free(compile_result.stdout);
    defer ctx.allocator.free(compile_result.stderr);
    if (!termOk(compile_result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "compile failed for {s} ({}):\n{s}{s}", .{ path, compile_result.term, compile_result.stdout, compile_result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }

    const run_result = try std.process.run(ctx.allocator, ctx.io, .{ .argv = &.{out}, .cwd = .{ .path = ctx.repo_root } });
    defer ctx.allocator.free(run_result.stdout);
    defer ctx.allocator.free(run_result.stderr);
    if (!termOk(run_result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "program {s} exited with {}:\n{s}{s}", .{ path, run_result.term, run_result.stdout, run_result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }

    var actual_lines: std.ArrayList([]const u8) = .empty;
    defer actual_lines.deinit(ctx.allocator);
    var line_it = std.mem.splitScalar(u8, run_result.stdout, '\n');
    while (line_it.next()) |line| {
        if (line_it.rest().len == 0 and line.len == 0) break;
        try actual_lines.append(ctx.allocator, line);
    }

    var actual_idx: usize = 0;
    var mismatches = std.ArrayList(u8).empty;
    defer mismatches.deinit(ctx.allocator);
    for (expected.items) |exp_line| {
        var found = false;
        const saved_idx = actual_idx;
        while (actual_idx < actual_lines.items.len) {
            if (std.mem.indexOf(u8, actual_lines.items[actual_idx], exp_line) != null) {
                found = true;
                break;
            }
            actual_idx += 1;
        }
        if (!found) {
            actual_idx = saved_idx;
            try mismatches.print(ctx.allocator, "expected annotation not found in output: \"{s}\"\n", .{exp_line});
        }
    }
    if (mismatches.items.len == 0) return .{ .passed = true, .asserts = 1 };

    var msg = std.ArrayList(u8).empty;
    try msg.appendSlice(ctx.allocator, mismatches.items);
    try msg.print(ctx.allocator, "actual stdout:\n{s}", .{run_result.stdout});
    return .{ .passed = false, .asserts = 1, .message = try msg.toOwnedSlice(ctx.allocator) };
}

fn extractExpectedAnnotations(source: []const u8, allocator: std.mem.Allocator, out: *std.ArrayList([]const u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const marker = "// =>";
        const pos = std.mem.indexOf(u8, line, marker) orelse continue;
        const before = line[0..pos];
        if (std.mem.indexOf(u8, before, "//") != null) continue;
        const after_marker = line[pos + marker.len ..];
        const text = if (after_marker.len > 0 and after_marker[0] == ' ') after_marker[1..] else after_marker;
        if (text.len == 0) continue;
        if (std.mem.startsWith(u8, text, "Error:")) continue;
        if (std.mem.startsWith(u8, text, "(")) continue;
        try out.append(allocator, text);
    }
}

fn expectCompilerCommandOutput(ctx: *Context, arg: []const u8, expected: []const u8) !TestOutcome {
    const result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = &.{ ctx.compiler_path, arg },
        .cwd = .{ .path = ctx.repo_root },
    });
    defer ctx.allocator.free(result.stdout);
    defer ctx.allocator.free(result.stderr);
    if (!termOk(result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "compiler command '{s}' failed ({}):\n{s}{s}", .{ arg, result.term, result.stdout, result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }
    const actual = try std.fmt.allocPrint(ctx.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer ctx.allocator.free(actual);
    if (std.mem.eql(u8, actual, expected)) return .{ .passed = true, .asserts = 1 };
    const msg = try std.fmt.allocPrint(ctx.allocator, "compiler command output mismatch for '{s}'\nexpected: \"{s}\"\nactual:   \"{s}\"", .{ arg, expected, actual });
    return .{ .passed = false, .asserts = 1, .message = msg };
}

fn expectCompileSuccess(ctx: *Context, path: []const u8) !TestOutcome {
    const out = try outputPathFor(ctx, path);
    defer ctx.allocator.free(out);
    const argv_with_target = [_][]const u8{ ctx.compiler_path, path, "--check", "-o", out, "--runtime", ctx.runtime_path, "--", "main8" };
    const argv_default = [_][]const u8{ ctx.compiler_path, path, "--check", "-o", out, "--runtime", ctx.runtime_path };
    const argv: []const []const u8 = if (std.mem.endsWith(u8, path, "examples/30/30.14_build_inlining.jai"))
        argv_with_target[0..]
    else
        argv_default[0..];
    const result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = argv,
        .cwd = .{ .path = ctx.repo_root },
    });
    defer ctx.allocator.free(result.stdout);
    defer ctx.allocator.free(result.stderr);
    if (termOk(result.term)) return .{ .passed = true, .asserts = 1 };
    const msg = try std.fmt.allocPrint(ctx.allocator, "compile failed for {s} ({}):\n{s}{s}", .{ path, result.term, result.stdout, result.stderr });
    return .{ .passed = false, .asserts = 1, .message = msg };
}

fn expectCompileFailure(ctx: *Context, path: []const u8, expected: []const u8) !TestOutcome {
    const out = try outputPathFor(ctx, path);
    defer ctx.allocator.free(out);
    const result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = &.{ ctx.compiler_path, path, "--check", "-o", out, "--runtime", ctx.runtime_path },
        .cwd = .{ .path = ctx.repo_root },
    });
    defer ctx.allocator.free(result.stdout);
    defer ctx.allocator.free(result.stderr);
    if (termOk(result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "expected compile failure for {s}, but compilation succeeded", .{path});
        return .{ .passed = false, .asserts = 1, .message = msg };
    }
    if (std.mem.indexOf(u8, result.stdout, expected) != null or std.mem.indexOf(u8, result.stderr, expected) != null) return .{ .passed = true, .asserts = 1 };
    const msg = try std.fmt.allocPrint(ctx.allocator, "compile failed for {s}, but diagnostic did not contain \"{s}\":\n{s}{s}", .{ path, expected, result.stdout, result.stderr });
    return .{ .passed = false, .asserts = 1, .message = msg };
}

fn expectCompileOutput(ctx: *Context, path: []const u8, expected: []const u8, mode: OutputMode) !TestOutcome {
    return try expectCompileOutputArgs(ctx, path, expected, mode, &.{});
}

fn expectCompileOutputArgs(ctx: *Context, path: []const u8, expected: []const u8, mode: OutputMode, extra_args: []const []const u8) !TestOutcome {
    const out = try outputPathFor(ctx, path);
    defer ctx.allocator.free(out);
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(ctx.allocator);
    try argv.appendSlice(ctx.allocator, &.{ ctx.compiler_path, path, "-o", out, "--runtime", ctx.runtime_path });
    if (extra_args.len != 0) {
        try argv.append(ctx.allocator, "--");
        try argv.appendSlice(ctx.allocator, extra_args);
    }
    const result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = argv.items,
        .cwd = .{ .path = ctx.repo_root },
    });
    defer ctx.allocator.free(result.stdout);
    defer ctx.allocator.free(result.stderr);
    if (!termOk(result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "compile failed for {s} ({}):\n{s}{s}", .{ path, result.term, result.stdout, result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }
    const actual = try std.fmt.allocPrint(ctx.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer ctx.allocator.free(actual);
    const pass = switch (mode) {
        .exact => std.mem.eql(u8, actual, expected),
        .contains => std.mem.indexOf(u8, actual, expected) != null,
    };
    if (pass) return .{ .passed = true, .asserts = 1 };
    const msg = try std.fmt.allocPrint(ctx.allocator, "compile output mismatch for {s}\nexpected: \"{s}\"\nactual:   \"{s}\"", .{ path, expected, actual });
    return .{ .passed = false, .asserts = 1, .message = msg };
}

fn expectCompileCreatesFile(ctx: *Context, path: []const u8, output_path: []const u8, expected: []const u8) !TestOutcome {
    Dir.cwd().deleteFile(ctx.io, output_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const out = try outputPathFor(ctx, path);
    defer ctx.allocator.free(out);
    const compile_result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = &.{ ctx.compiler_path, path, "-o", out, "--runtime", ctx.runtime_path },
        .cwd = .{ .path = ctx.repo_root },
    });
    defer ctx.allocator.free(compile_result.stdout);
    defer ctx.allocator.free(compile_result.stderr);
    if (!termOk(compile_result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "compile failed for {s} ({}):\n{s}{s}", .{ path, compile_result.term, compile_result.stdout, compile_result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }

    const actual = Dir.cwd().readFileAlloc(ctx.io, output_path, ctx.allocator, .limited(1024 * 1024)) catch |err| {
        const msg = try std.fmt.allocPrint(ctx.allocator, "expected compile of {s} to create {s}: {s}", .{ path, output_path, @errorName(err) });
        return .{ .passed = false, .asserts = 1, .message = msg };
    };
    defer ctx.allocator.free(actual);

    if (std.mem.eql(u8, actual, expected)) return .{ .passed = true, .asserts = 1 };
    const msg = try std.fmt.allocPrint(ctx.allocator, "file output mismatch for {s}\nexpected: \"{s}\"\nactual:   \"{s}\"", .{ output_path, expected, actual });
    return .{ .passed = false, .asserts = 1, .message = msg };
}

fn expectCompileCreatesProgramOutput(ctx: *Context, path: []const u8, program_path: []const u8, expected: []const u8) !TestOutcome {
    Dir.cwd().deleteFile(ctx.io, program_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const out = try outputPathFor(ctx, path);
    defer ctx.allocator.free(out);
    const compile_result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = &.{ ctx.compiler_path, path, "-o", out, "--runtime", ctx.runtime_path },
        .cwd = .{ .path = ctx.repo_root },
    });
    defer ctx.allocator.free(compile_result.stdout);
    defer ctx.allocator.free(compile_result.stderr);
    if (!termOk(compile_result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "compile failed for {s} ({}):\n{s}{s}", .{ path, compile_result.term, compile_result.stdout, compile_result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }

    const run_result = try std.process.run(ctx.allocator, ctx.io, .{ .argv = &.{program_path}, .cwd = .{ .path = ctx.repo_root } });
    defer ctx.allocator.free(run_result.stdout);
    defer ctx.allocator.free(run_result.stderr);
    if (!termOk(run_result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "program {s} exited with {}:\n{s}{s}", .{ program_path, run_result.term, run_result.stdout, run_result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }
    if (std.mem.eql(u8, run_result.stdout, expected)) return .{ .passed = true, .asserts = 1 };
    const msg = try std.fmt.allocPrint(ctx.allocator, "program output mismatch for {s}\nexpected: \"{s}\"\nactual:   \"{s}\"", .{ program_path, expected, run_result.stdout });
    return .{ .passed = false, .asserts = 1, .message = msg };
}

const OutputMode = enum { exact, contains };

fn expectProgramOutput(ctx: *Context, path: []const u8, expected: []const u8, mode: OutputMode) !TestOutcome {
    const out = try outputPathFor(ctx, path);
    defer ctx.allocator.free(out);
    const compile_result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = &.{ ctx.compiler_path, path, "-o", out, "--runtime", ctx.runtime_path },
        .cwd = .{ .path = ctx.repo_root },
    });
    defer ctx.allocator.free(compile_result.stdout);
    defer ctx.allocator.free(compile_result.stderr);
    if (!termOk(compile_result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "compile failed for {s} ({}):\n{s}{s}", .{ path, compile_result.term, compile_result.stdout, compile_result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }
    const run_result = try std.process.run(ctx.allocator, ctx.io, .{ .argv = &.{out}, .cwd = .{ .path = ctx.repo_root } });
    defer ctx.allocator.free(run_result.stdout);
    defer ctx.allocator.free(run_result.stderr);
    if (!termOk(run_result.term)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "program {s} exited with {}:\n{s}{s}", .{ path, run_result.term, run_result.stdout, run_result.stderr });
        return .{ .passed = false, .asserts = 1, .message = msg };
    }
    const pass = switch (mode) {
        .exact => std.mem.eql(u8, run_result.stdout, expected),
        .contains => std.mem.indexOf(u8, run_result.stdout, expected) != null,
    };
    if (pass) return .{ .passed = true, .asserts = 1 };
    const msg = try std.fmt.allocPrint(ctx.allocator, "program output mismatch for {s}\nexpected: \"{s}\"\nactual:   \"{s}\"", .{ path, expected, run_result.stdout });
    return .{ .passed = false, .asserts = 1, .message = msg };
}

fn termOk(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn outputPathFor(ctx: *Context, source_path: []const u8) ![]u8 {
    const stem = std.fs.path.stem(std.fs.path.basename(source_path));
    return try std.fs.path.join(ctx.allocator, &.{ ctx.output_dir, stem });
}

fn collectJaiFiles(allocator: std.mem.Allocator, io: std.Io, dir_path: []const u8, out: *std.ArrayList([]u8)) !void {
    const dir = try Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    var walker = try Dir.walk(dir, allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".jai")) continue;
        const full = try std.fs.path.join(allocator, &.{ dir_path, entry.path });
        try out.append(allocator, full);
    }
}

fn collectLoadedExampleFiles(allocator: std.mem.Allocator, io: std.Io, files: []const []const u8, out: *std.StringHashMapUnmanaged(void)) !void {
    for (files) |path| {
        const source = Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024)) catch continue;
        defer allocator.free(source);
        const dir = std.fs.path.dirname(path) orelse ".";
        var rest = source;
        while (std.mem.indexOf(u8, rest, "#load \"")) |idx| {
            const start = idx + "#load \"".len;
            const end_rel = std.mem.indexOfScalar(u8, rest[start..], '"') orelse break;
            const load_name = rest[start .. start + end_rel];
            if (!std.mem.endsWith(u8, load_name, ".jai")) {
                rest = rest[start + end_rel + 1 ..];
                continue;
            }
            const loaded_path = try std.fs.path.join(allocator, &.{ dir, load_name });
            errdefer allocator.free(loaded_path);
            const entry = try out.getOrPut(allocator, loaded_path);
            if (entry.found_existing) allocator.free(loaded_path);
            rest = rest[start + end_rel + 1 ..];
        }
    }
}

fn sourceHasMainEntry(io: std.Io, path: []const u8, allocator: std.mem.Allocator) !bool {
    const source = Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024)) catch return false;
    defer allocator.free(source);
    return std.mem.indexOf(u8, source, "main ::") != null;
}

fn isSupportedExamplePath(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "/raylib/extras/") == null and
        std.mem.indexOf(u8, path, "\\raylib\\extras\\") == null;
}

fn sortStrings(items: [][]u8) void {
    std.mem.sort([]u8, items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);
}

fn freeStringList(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

fn relativeToRoot(allocator: std.mem.Allocator, repo_root: []const u8, path: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, path, repo_root)) {
        var rel = path[repo_root.len..];
        while (rel.len > 0 and (rel[0] == '/' or rel[0] == '\\')) rel = rel[1..];
        return try allocator.dupe(u8, rel);
    }
    return try allocator.dupe(u8, path);
}

fn pathFromRepo(allocator: std.mem.Allocator, repo_root: []const u8, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return try allocator.dupe(u8, path);
    return try std.fs.path.join(allocator, &.{ repo_root, path });
}

fn stringArg(allocator: std.mem.Allocator, ast: *const Ast, args: []const u32, index: usize, call: NodeIndex) ![]u8 {
    if (index >= args.len) return error.MissingArgument;
    _ = call;
    const node: NodeIndex = @intCast(args[index]);
    if (ast.tag(node) != .string_literal) return error.ExpectedStringLiteral;
    return try decodeStringLiteral(allocator, ast.stringTokenContents(ast.mainToken(node)));
}

fn decodeStringLiteral(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] != '\\' or i + 1 >= raw.len) {
            try out.append(allocator, raw[i]);
            continue;
        }
        i += 1;
        try out.append(allocator, switch (raw[i]) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '\\' => '\\',
            '"' => '"',
            else => raw[i],
        });
    }
    return try out.toOwnedSlice(allocator);
}

const EvalValue = union(enum) { int: i64, bool: bool, string: []const u8 };

fn evalBool(ast: *const Ast, node: NodeIndex) anyerror!bool {
    const value = try evalValue(ast, node);
    return switch (value) {
        .bool => |v| v,
        .int => |v| v != 0,
        .string => |v| v.len != 0,
    };
}

fn evalValue(ast: *const Ast, node: NodeIndex) anyerror!EvalValue {
    return switch (ast.tag(node)) {
        .bool_literal => .{ .bool = std.mem.eql(u8, ast.tokenSlice(ast.mainToken(node)), "true") },
        .integer_literal => .{ .int = try parseIntLiteral(ast.tokenSlice(ast.mainToken(node))) },
        .string_literal => .{ .string = ast.stringTokenContents(ast.mainToken(node)) },
        .unary_expr => blk: {
            const op = ast.tokens[ast.mainToken(node)].tag;
            if (op == .bang) break :blk .{ .bool = !(try evalBool(ast, ast.data(node).lhs)) };
            if (op == .minus) {
                const v = try evalValue(ast, ast.data(node).lhs);
                switch (v) {
                    .int => |int_value| break :blk .{ .int = -int_value },
                    else => return error.UnsupportedExpression,
                }
            }
            return error.UnsupportedExpression;
        },
        .binary_expr => try evalBinary(ast, node),
        else => error.UnsupportedExpression,
    };
}

fn evalBinary(ast: *const Ast, node: NodeIndex) anyerror!EvalValue {
    const lhs = try evalValue(ast, ast.data(node).lhs);
    const rhs = try evalValue(ast, ast.data(node).rhs);
    return switch (ast.tokens[ast.mainToken(node)].tag) {
        .plus => .{ .int = try valueInt(lhs) + try valueInt(rhs) },
        .minus => .{ .int = try valueInt(lhs) - try valueInt(rhs) },
        .star => .{ .int = try valueInt(lhs) * try valueInt(rhs) },
        .slash => .{ .int = @divTrunc(try valueInt(lhs), try valueInt(rhs)) },
        .equal_equal => .{ .bool = valuesEqual(lhs, rhs) },
        .bang_equal => .{ .bool = !valuesEqual(lhs, rhs) },
        .less_than => .{ .bool = try valueInt(lhs) < try valueInt(rhs) },
        .less_equal => .{ .bool = try valueInt(lhs) <= try valueInt(rhs) },
        .greater_than => .{ .bool = try valueInt(lhs) > try valueInt(rhs) },
        .greater_equal => .{ .bool = try valueInt(lhs) >= try valueInt(rhs) },
        .ampersand_ampersand => .{ .bool = try valueBool(lhs) and try valueBool(rhs) },
        .pipe_pipe => .{ .bool = try valueBool(lhs) or try valueBool(rhs) },
        else => error.UnsupportedExpression,
    };
}

fn parseIntLiteral(raw: []const u8) !i64 {
    var buf: [128]u8 = undefined;
    var len: usize = 0;
    for (raw) |c| {
        if (c == '_') continue;
        if (len >= buf.len) return error.IntLiteralTooLong;
        buf[len] = c;
        len += 1;
    }
    return try std.fmt.parseInt(i64, buf[0..len], 0);
}

fn valueInt(value: EvalValue) !i64 {
    return switch (value) {
        .int => |v| v,
        .bool => |v| if (v) 1 else 0,
        .string => error.ExpectedInteger,
    };
}

fn valueBool(value: EvalValue) !bool {
    return switch (value) {
        .bool => |v| v,
        .int => |v| v != 0,
        .string => |v| v.len != 0,
    };
}

fn valuesEqual(lhs: EvalValue, rhs: EvalValue) bool {
    return switch (lhs) {
        .int => |l| switch (rhs) {
            .int => |r| l == r,
            .bool => |r| (l != 0) == r,
            else => false,
        },
        .bool => |l| switch (rhs) {
            .bool => |r| l == r,
            .int => |r| l == (r != 0),
            else => false,
        },
        .string => |l| switch (rhs) {
            .string => |r| std.mem.eql(u8, l, r),
            else => false,
        },
    };
}

fn sourceLocation(ast: *const Ast, path: []const u8, node: NodeIndex) SourceLocation {
    const offset = ast.tokens[ast.mainToken(node)].start;
    var line: usize = 1;
    for (ast.source[0..offset]) |c| {
        if (c == '\n') line += 1;
    }
    return .{ .path = path, .line = line };
}

const SourceLocation = struct {
    path: []const u8,
    line: usize,

    pub fn format(loc: SourceLocation, writer: *std.Io.Writer) !void {
        try writer.print("{s}:{d}", .{ loc.path, loc.line });
    }
};
