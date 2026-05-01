const std = @import("std");
const lexer = @import("src/lexer.zig");
const Diagnostic = @import("src/diagnostics.zig").Diagnostic;
pub fn main() !void {
    const source = "print(\"%\\n\", #char \"1\");";
    const diag = Diagnostic.init(std.heap.page_allocator, "snippet.jai", source);
    var tokens = try lexer.tokenize(std.heap.page_allocator, source, diag);
    defer tokens.deinit(std.heap.page_allocator);
    for (tokens.items(.tag), tokens.items(.start), tokens.items(.end)) |tag, start, end| {
        std.debug.print("{s} '{s}'\n", .{ @tagName(tag), source[start..end] });
    }
}
