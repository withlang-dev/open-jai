const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const resolve_mod = @import("resolve.zig");
const sema = @import("Sema.zig");
const bytecode_gen = @import("bytecode_gen.zig");
const llvm = @import("codegen/llvm.zig");
const link_mod = @import("link.zig");
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const InternPool = @import("InternPool.zig").InternPool;

pub const Options = struct {
    input_path: []const u8,
    output_path: []const u8,
    runtime_path: []const u8 = "zig-out/lib/openjai_runtime.o",
};

pub const Compilation = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) Compilation {
        return .{ .allocator = allocator, .io = io, .options = options };
    }

    pub fn compile(comp: *Compilation) !void {
        const source = std.Io.Dir.cwd().readFileAlloc(
            comp.io,
            comp.options.input_path,
            comp.allocator,
            .limited(64 * 1024 * 1024),
        ) catch |err| {
            std.debug.print("{s}: error: unable to read source file: {s}\n", .{ comp.options.input_path, @errorName(err) });
            return error.SourceReadFailed;
        };
        defer comp.allocator.free(source);
        if (source.len == 0) return Diagnostic.init(comp.allocator, comp.options.input_path, source).failAt(0, "source file is empty", .{});

        const diag = Diagnostic.init(comp.allocator, comp.options.input_path, source);
        var tokens = try lexer.tokenize(comp.allocator, source, diag);
        defer tokens.deinit(comp.allocator);

        const token_slice = tokens.slice();
        var ast = try parser.parse(comp.allocator, source, token_slice.items(.tag), token_slice.items(.start), token_slice.items(.end), diag);
        defer {
            comp.allocator.free(ast.tokens);
            ast.deinit();
        }

        var resolved = try resolve_mod.resolve(comp.allocator, &ast, diag);
        defer resolved.deinit();

        var ip = try InternPool.init(comp.allocator);
        defer ip.deinit();

        var typed = try sema.analyze(comp.allocator, &ast, &resolved, &ip, diag);
        defer typed.deinit();

        var bytecode = try bytecode_gen.generate(comp.allocator, &ast, &typed, diag);
        defer bytecode.deinit();

        const object_path = try std.fmt.allocPrint(comp.allocator, "{s}.o", .{comp.options.output_path});
        defer comp.allocator.free(object_path);
        try llvm.emitObject(comp.allocator, &bytecode, object_path, diag);

        try link_mod.link(comp.allocator, comp.io, object_path, comp.options.runtime_path, comp.options.output_path, diag);
    }
};

test "Compilation reports missing source" {
    var comp = Compilation.init(std.testing.allocator, std.testing.io, .{ .input_path = "definitely_missing.jai", .output_path = "hello" });
    try std.testing.expectError(error.SourceReadFailed, comp.compile());
}
