const std = @import("std");
const Token = @import("Token.zig").Token;

pub const NodeIndex = u32;
pub const ExtraIndex = u32;
pub const null_node: NodeIndex = std.math.maxInt(NodeIndex);

pub const Node = struct {
    tag: Tag,
    main_token: Token.Index,
    data: Data,

    pub const Tag = enum(u8) {
        root,
        import_decl,
        load_decl,
        scope_decl,
        add_context_decl,
        proc_decl,
        const_decl,
        param_list,
        block,
        expr_stmt,
        var_decl,
        return_stmt,
        stmt_list,
        type_expr,
        pointer_type,
        proc_type,
        if_stmt,
        ifx_expr,
        for_stmt,
        aggregate_literal,
        typed_aggregate_literal,
        field_access,
        call_expr,
        assign_stmt,
        char_literal,
        type_of_expr,
        size_of_expr,
        run_expr,
        is_constant_expr,
        unary_expr,
        binary_expr,
        identifier,
        string_literal,
        integer_literal,
        float_literal,
        bool_literal,
        null_literal,
        undefined_literal,
        unsupported,
    };

    pub const Data = struct { lhs: u32 = 0, rhs: u32 = 0 };
};

pub const Ast = struct {
    allocator: std.mem.Allocator,
    tokens: []const Token,
    source: []const u8,
    node_tags: std.ArrayList(Node.Tag) = .empty,
    node_main_tokens: std.ArrayList(Token.Index) = .empty,
    node_data: std.ArrayList(Node.Data) = .empty,
    extra_data: std.ArrayList(u32) = .empty,
    root: NodeIndex = null_node,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, tokens: []const Token) Ast {
        return .{ .allocator = allocator, .source = source, .tokens = tokens };
    }

    pub fn deinit(ast: *Ast) void {
        ast.node_tags.deinit(ast.allocator);
        ast.node_main_tokens.deinit(ast.allocator);
        ast.node_data.deinit(ast.allocator);
        ast.extra_data.deinit(ast.allocator);
    }

    pub fn addNode(ast: *Ast, node_tag: Node.Tag, main_token: Token.Index, node_data_value: Node.Data) !NodeIndex {
        const idx: NodeIndex = @intCast(ast.node_tags.items.len);
        try ast.node_tags.append(ast.allocator, node_tag);
        try ast.node_main_tokens.append(ast.allocator, main_token);
        try ast.node_data.append(ast.allocator, node_data_value);
        return idx;
    }

    pub fn addExtraSlice(ast: *Ast, values: []const u32) !ExtraIndex {
        const start: ExtraIndex = @intCast(ast.extra_data.items.len);
        try ast.extra_data.append(ast.allocator, @intCast(values.len));
        try ast.extra_data.appendSlice(ast.allocator, values);
        return start;
    }

    pub fn extraSlice(ast: *const Ast, start: ExtraIndex) []const u32 {
        const len = ast.extra_data.items[start];
        return ast.extra_data.items[start + 1 .. start + 1 + len];
    }

    pub fn tag(ast: *const Ast, node: NodeIndex) Node.Tag { return ast.node_tags.items[node]; }
    pub fn mainToken(ast: *const Ast, node: NodeIndex) Token.Index { return ast.node_main_tokens.items[node]; }
    pub fn data(ast: *const Ast, node: NodeIndex) Node.Data { return ast.node_data.items[node]; }

    pub fn tokenSlice(ast: *const Ast, token_index: Token.Index) []const u8 {
        const tok = ast.tokens[token_index];
        return ast.source[tok.start..tok.end];
    }

    pub fn stringTokenContents(ast: *const Ast, token_index: Token.Index) []const u8 {
        const text = ast.tokenSlice(token_index);
        if (text.len >= 2 and text[0] == '"') return text[1 .. text.len - 1];
        if (text.len > 0 and text[text.len - 1] == '\n') return text[0 .. text.len - 1];
        return text;
    }
};

test "construct basic ast" {
    const toks = [_]Token{.{ .tag = .eof, .start = 0, .end = 0 }};
    var ast = Ast.init(std.testing.allocator, "", &toks);
    defer ast.deinit();
    const n = try ast.addNode(.root, 0, .{});
    ast.root = n;
    try std.testing.expectEqual(Node.Tag.root, ast.tag(n));
}
