const std = @import("std");
const Bytecode = @import("Bytecode.zig");
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const time_c = @cImport({
    @cInclude("time.h");
});

pub const CodeValue = struct {
    text: []const u8,
    path: []const u8 = "",
    line_number: i64 = 1,
};

pub const Value = union(enum) {
    void,
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
    bytes: []const u8,
    code: CodeValue,
    source_location: SourceLocation,
    type_text: []const u8,
};

const Pointer = struct {
    block: u32,
    offset: usize,
};

const allocator_proc_default: u32 = 1;
const allocator_proc_pool: u32 = 2;
const allocator_proc_flat_pool: u32 = 3;
const allocator_proc_rpmalloc: u32 = 4;

const CodeNode = struct {
    tree: u32 = std.math.maxInt(u32),
    index: u32 = std.math.maxInt(u32),
    kind: []const u8,
    flags: []const u8,
    text: []const u8,
    name: []const u8 = "",
    path: []const u8 = "",
    line_number: i64 = 1,
    type_text: []const u8 = "",
    start: usize = 0,
    end: usize = 0,
    s64: ?i64 = null,
    string_value: ?[]const u8 = null,
    arg_start: u32 = 0,
    arg_count: u32 = 0,
    note_start: usize = 0,
    note_count: usize = 0,
    subexpression_start: usize = 0,
    subexpression_count: usize = 0,
    expression_index: ?u32 = null,
};

const CodeArgument = struct {
    tree: u32 = std.math.maxInt(u32),
    expression_index: u32 = std.math.maxInt(u32),
};

const CodeNote = struct {
    text: []const u8,
};

const CodeTree = struct {
    source: []const u8,
    path: []const u8,
    line_number: i64,
    root: CodeNode,
    nodes: []CodeNode,
    arguments: []CodeArgument,
};

pub const SourceLocation = struct {
    fully_pathed_filename: []const u8,
    line_number: i64,
};

const CalendarValue = struct {
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

const CompilerMessage = struct {
    kind: []const u8,
    workspace: i64,
    phase: []const u8 = "",
    fully_pathed_filename: []const u8 = "",
    module_name: []const u8 = "",
    module_type: []const u8 = "",
    executable_name: []const u8 = "",
    executable_write_failed: bool = false,
    linker_exit_code: i64 = 0,
    all_start: usize = 0,
    all_count: usize = 0,
    declaration_start: usize = 0,
    declaration_count: usize = 0,
    dump_text: []const u8 = "",
    error_code: i64 = 0,
};

pub const WorkspaceSourceSnapshot = struct {
    workspace: i64,
    path: []const u8,
    source: []const u8,
};

pub const BuildOptionsSnapshot = struct {
    output_executable_name: []const u8 = "",
    output_path: []const u8 = "",
    output_type: []const u8 = "EXECUTABLE",
    backend: []const u8 = "LLVM",
    llvm_output_bitcode: bool = false,
};

const WorkspaceSource = WorkspaceSourceSnapshot;

const RunCommandResult = struct {
    exit_code: i64,
    stdout: []const u8,
    stderr: []const u8,
    timeout_reached: bool = false,
};

const RegisterValue = union(enum) {
    empty,
    string: []const u8,
    bytes: []const u8,
    code: CodeValue,
    code_node: CodeNode,
    code_nodes: []const CodeNode,
    code_note: CodeNote,
    code_notes: []const CodeNote,
    code_arg: CodeArgument,
    code_args: []const CodeArgument,
    source_location: SourceLocation,
    calendar: CalendarValue,
    message: usize,
    build_options: usize,
    build_llvm_options: usize,
    type_id: u32,
    type_text: []const u8,
    type_info_member: Bytecode.TypeInfoMember,
    tuple: []const RegisterValue,
    ptr: Pointer,
    int: i64,
    float: f64,
    bool: bool,
};

const BuildOptions = struct {
    output_executable_name: []const u8 = "",
    output_path: []const u8 = "",
    intermediate_path: []const u8 = ".build/",
    output_type: []const u8 = "EXECUTABLE",
    backend: []const u8 = "LLVM",
    write_added_strings: bool = true,
    stack_trace: bool = true,
    backtrace_on_crash: []const u8 = "ON",
    array_bounds_check: []const u8 = "ON",
    cast_bounds_check: []const u8 = "NONFATAL",
    null_pointer_check: []const u8 = "ON",
    enable_bytecode_inliner: bool = false,
    runtime_storageless_type_info: bool = false,
    use_custom_link_command: bool = false,
    llvm_output_bitcode: bool = false,
    import_path: ?usize = null,
    compile_time_command_line: ?usize = null,
};

const DynamicArray = struct {
    header: ?Pointer = null,
    slot: ?Pointer = null,
    data: ?Pointer = null,
    elem_size: usize = 1,
    elems: std.ArrayList(RegisterValue) = .empty,
};

const HostFile = struct {
    path: []const u8,
    contents: std.ArrayList(u8) = .empty,
    cursor: usize = 0,
    writable: bool = false,
    dirty: bool = false,
    open: bool = true,
};

const HostFileOpenResult = struct {
    handle: i64,
    ok: bool,
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    program: *const Bytecode.Program,
    memory_blocks: std.ArrayList([]u8) = .empty,
    allocation_owners: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    global_ptrs: std.ArrayList(?Pointer) = .empty,
    string_builders: std.AutoHashMapUnmanaged(u64, std.ArrayList(u8)) = .empty,
    string_slots: std.AutoHashMapUnmanaged(u64, []const u8) = .empty,
    dynamic_arrays: std.ArrayList(DynamicArray) = .empty,
    dynamic_array_refs: std.AutoHashMapUnmanaged(u64, usize) = .empty,
    code_trees: std.ArrayList(CodeTree) = .empty,
    rendered_code_strings: std.ArrayList([]const u8) = .empty,
    build_options: std.ArrayList(BuildOptions) = .empty,
    workspace_build_options: std.AutoHashMapUnmanaged(i64, usize) = .empty,
    workspace_status: std.AutoHashMapUnmanaged(i64, i64) = .empty,
    compiler_messages: std.ArrayList(CompilerMessage) = .empty,
    compiler_message_queue: std.ArrayList(usize) = .empty,
    compiler_message_nodes: std.ArrayList(CodeNode) = .empty,
    compiler_message_declarations: std.ArrayList(CodeNode) = .empty,
    compiler_message_notes: std.ArrayList(CodeNote) = .empty,
    workspace_sources: std.ArrayList(WorkspaceSource) = .empty,
    open_files: std.ArrayList(HostFile) = .empty,
    intercepted_workspace: i64 = 0,
    io: ?std.Io = null,
    base_dir: []const u8 = ".",
    command_line: []const []const u8 = &.{},
    current_workspace_build_strings: ?*std.ArrayList([]const u8) = null,
    next_workspace_id: ?*i64 = null,
    current_workspace_id: i64 = 2,
    start_monotonic_ns: ?i64 = null,
    random_state: u64 = 0x4d595df4d0f33173,

    pub fn init(allocator: std.mem.Allocator, program: *const Bytecode.Program) VM {
        return .{ .allocator = allocator, .program = program };
    }

    pub fn initWithContext(allocator: std.mem.Allocator, program: *const Bytecode.Program, io: std.Io, base_dir: []const u8) VM {
        return .{ .allocator = allocator, .program = program, .io = io, .base_dir = base_dir };
    }

    pub fn exportWorkspaceBuildState(
        vm: *VM,
        allocator: std.mem.Allocator,
        sources: *std.ArrayList(WorkspaceSourceSnapshot),
        options: *std.AutoHashMapUnmanaged(i64, BuildOptionsSnapshot),
    ) !void {
        for (vm.workspace_sources.items) |source| {
            if (source.workspace <= 2) continue;
            try sources.append(allocator, .{
                .workspace = source.workspace,
                .path = try allocator.dupe(u8, source.path),
                .source = try allocator.dupe(u8, source.source),
            });
        }
        var it = vm.workspace_build_options.iterator();
        while (it.next()) |entry| {
            const workspace = entry.key_ptr.*;
            const snapshot = try vm.buildOptionsSnapshot(allocator, entry.value_ptr.*);
            if (try options.fetchPut(allocator, workspace, snapshot)) |old| {
                freeBuildOptionsSnapshot(allocator, old.value);
            }
        }
    }

    pub fn freeWorkspaceSourceSnapshot(allocator: std.mem.Allocator, source: WorkspaceSourceSnapshot) void {
        allocator.free(source.path);
        allocator.free(source.source);
    }

    pub fn freeBuildOptionsSnapshot(allocator: std.mem.Allocator, options: BuildOptionsSnapshot) void {
        allocator.free(options.output_executable_name);
        allocator.free(options.output_path);
        allocator.free(options.output_type);
        allocator.free(options.backend);
    }

    pub fn deinit(vm: *VM) void {
        for (vm.memory_blocks.items) |block| vm.allocator.free(block);
        vm.memory_blocks.deinit(vm.allocator);
        vm.allocation_owners.deinit(vm.allocator);
        vm.global_ptrs.deinit(vm.allocator);
        var builder_it = vm.string_builders.iterator();
        while (builder_it.next()) |entry| entry.value_ptr.deinit(vm.allocator);
        vm.string_builders.deinit(vm.allocator);
        vm.string_slots.deinit(vm.allocator);
        for (vm.dynamic_arrays.items) |*array| array.elems.deinit(vm.allocator);
        vm.dynamic_arrays.deinit(vm.allocator);
        vm.dynamic_array_refs.deinit(vm.allocator);
        for (vm.code_trees.items) |tree| {
            vm.allocator.free(tree.nodes);
            vm.allocator.free(tree.arguments);
        }
        vm.code_trees.deinit(vm.allocator);
        for (vm.rendered_code_strings.items) |text| vm.allocator.free(text);
        vm.rendered_code_strings.deinit(vm.allocator);
        vm.build_options.deinit(vm.allocator);
        vm.workspace_build_options.deinit(vm.allocator);
        vm.workspace_status.deinit(vm.allocator);
        vm.compiler_messages.deinit(vm.allocator);
        vm.compiler_message_queue.deinit(vm.allocator);
        vm.compiler_message_nodes.deinit(vm.allocator);
        vm.compiler_message_declarations.deinit(vm.allocator);
        vm.compiler_message_notes.deinit(vm.allocator);
        for (vm.workspace_sources.items) |source| {
            vm.allocator.free(source.path);
            vm.allocator.free(source.source);
        }
        vm.workspace_sources.deinit(vm.allocator);
        for (vm.open_files.items) |*file| {
            vm.allocator.free(file.path);
            file.contents.deinit(vm.allocator);
        }
        vm.open_files.deinit(vm.allocator);
    }

    pub fn runProc(vm: *VM, proc_index: u32, diag: Diagnostic) !Value {
        return vm.runProcWithArgs(proc_index, &.{}, diag);
    }

    pub fn runProcWithArgs(vm: *VM, proc_index: u32, args: []const Value, diag: Diagnostic) !Value {
        const call_args = try vm.allocator.alloc(RegisterValue, args.len);
        defer vm.allocator.free(call_args);
        for (args, 0..) |arg, i| call_args[i] = try registerValueFromValue(arg, diag);
        const result = try vm.runProcWithRegisterArgs(proc_index, call_args, diag);
        return try registerValueToRunValue(vm, result, diag);
    }

    fn runProcWithRegisterArgs(vm: *VM, proc_index: u32, args: []const RegisterValue, diag: Diagnostic) !RegisterValue {
        if (proc_index >= vm.program.procs.items.len) return diag.failAt(0, "#run target procedure index out of range", .{});
        const proc = &vm.program.procs.items[proc_index];
        var regs = try vm.allocator.alloc(RegisterValue, proc.num_registers);
        defer vm.allocator.free(regs);
        @memset(regs, .empty);
        var local_ptrs = try vm.allocator.alloc(?Pointer, proc.num_registers);
        defer vm.allocator.free(local_ptrs);
        @memset(local_ptrs, null);
        if (args.len > regs.len) return diag.failAt(0, "VM #run argument count exceeds register file", .{});
        for (args, 0..) |arg, i| regs[i] = arg;
        var ip: usize = 0;
        while (ip < proc.instructions.items.len) {
            const inst = proc.instructions.items[ip];
            ip += 1;
            switch (inst.opcode) {
                .load_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.strings.items.len) return diag.failAt(0, "VM load_string register/string index out of range", .{});
                    regs[inst.dest] = .{ .string = vm.program.strings.items[inst.arg1] };
                },
                .load_code => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.code_literals.items.len) return diag.failAt(0, "VM load_code register/code index out of range", .{});
                    const literal = vm.program.code_literals.items[inst.arg1];
                    regs[inst.dest] = .{ .code = .{
                        .text = literal.text,
                        .path = literal.path,
                        .line_number = literal.line_number,
                    } };
                },
                .load_source_location => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.strings.items.len) return diag.failAt(0, "VM load_source_location register/string index out of range", .{});
                    regs[inst.dest] = .{ .source_location = .{
                        .fully_pathed_filename = vm.program.strings.items[inst.arg1],
                        .line_number = @intCast(inst.arg2),
                    } };
                },
                .load_bytes => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.byte_arrays.items.len) return diag.failAt(0, "VM load_bytes register/byte-array index out of range", .{});
                    regs[inst.dest] = .{ .bytes = vm.program.byte_arrays.items[inst.arg1] };
                },
                .load_int => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM load_int register out of range", .{});
                    regs[inst.dest] = .{ .int = @as(i64, @as(i32, @bitCast(inst.arg1))) };
                },
                .load_float => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM load_float register out of range", .{});
                    const bits = (@as(u64, inst.arg2) << 32) | inst.arg1;
                    regs[inst.dest] = .{ .float = @bitCast(bits) };
                },
                .load_bool => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM load_bool register out of range", .{});
                    regs[inst.dest] = .{ .bool = inst.arg1 != 0 };
                },
                .load_type => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM load_type register out of range", .{});
                    regs[inst.dest] = .{ .type_id = inst.arg1 };
                },
                .load_type_text => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.strings.items.len) return diag.failAt(0, "VM load_type_text register/string index out of range", .{});
                    regs[inst.dest] = .{ .type_text = vm.program.strings.items[inst.arg1] };
                },
                .type_to_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM type_to_string register out of range", .{});
                    regs[inst.dest] = switch (regs[inst.arg1]) {
                        .type_id => |type_id| .{ .string = typeName(type_id) },
                        .type_text => |type_text| .{ .string = type_text },
                        else => return diag.failAt(0, "VM type_to_string requires a Type value", .{}),
                    };
                },
                .load_null_ptr, .load_const_ref => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM placeholder/reference load register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast(inst.arg1) };
                },
                .global_addr => {
                    if (inst.dest >= regs.len or inst.arg1 >= vm.program.globals.items.len) return diag.failAt(0, "VM global_addr register/global index out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.globalPtr(inst.arg1) };
                },
                .load_undef => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM undefined load register out of range", .{});
                    regs[inst.dest] = .{ .int = 0 };
                },
                .string_len => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_len register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast(switch (regs[inst.arg1]) {
                        .string => |v| v.len,
                        else => return diag.failAt(0, "VM string_len requires string operand", .{}),
                    }) };
                },
                .string_data => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_data register out of range", .{});
                    regs[inst.dest] = .{ .ptr = switch (regs[inst.arg1]) {
                        .string, .bytes => try vm.materializeRegister(regs[inst.arg1], diag),
                        .ptr => |ptr| ptr,
                        else => return diag.failAt(0, "VM string_data requires string operand", .{}),
                    } };
                },
                .string_to_c => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_to_c register out of range", .{});
                    regs[inst.dest] = .{ .ptr = switch (regs[inst.arg1]) {
                        .string => |text| try vm.materializeCString(text, diag),
                        .bytes => |bytes| try vm.materializeCString(bytes, diag),
                        .ptr => |ptr| ptr,
                        else => return diag.failAt(0, "VM to_c_string requires string operand", .{}),
                    } };
                },
                .string_from_parts => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_from_parts register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "to_string data pointer");
                    const len = try registerInt(regs[inst.arg2], diag, "to_string byte count");
                    if (len < 0) return diag.failAt(0, "VM to_string byte count cannot be negative", .{});
                    regs[inst.dest] = .{ .string = try vm.stringFromPointer(ptr, @intCast(len), diag) };
                },
                .string_from_c => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_from_c register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "to_string C string pointer");
                    regs[inst.dest] = .{ .string = try vm.stringFromCString(ptr, diag) };
                },
                .string_copy => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_copy register out of range", .{});
                    const text = try vm.registerText(regs[inst.arg1], diag, "copy_string source");
                    const owned = try vm.allocator.dupe(u8, text);
                    errdefer vm.allocator.free(owned);
                    try vm.rendered_code_strings.append(vm.allocator, owned);
                    regs[inst.dest] = .{ .string = owned };
                },
                .string_slice => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len or inst.arg3 >= regs.len) return diag.failAt(0, "VM string_slice register out of range", .{});
                    const text = try vm.registerText(regs[inst.arg1], diag, "string_slice source");
                    const start = try registerInt(regs[inst.arg2], diag, "string_slice start");
                    const count = try registerInt(regs[inst.arg3], diag, "string_slice count");
                    if (start < 0 or count < 0) return diag.failAt(0, "VM string_slice requires non-negative start and count", .{});
                    const start_usize: usize = @intCast(start);
                    const count_usize: usize = @intCast(count);
                    if (start_usize > text.len or count_usize > text.len - start_usize) return diag.failAt(0, "VM string_slice out of bounds", .{});
                    const owned = try vm.allocator.dupe(u8, text[start_usize .. start_usize + count_usize]);
                    errdefer vm.allocator.free(owned);
                    try vm.rendered_code_strings.append(vm.allocator, owned);
                    regs[inst.dest] = .{ .string = owned };
                },
                .string_compare => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_compare register out of range", .{});
                    const lhs = try vm.registerText(regs[inst.arg1], diag, "compare lhs");
                    const rhs = try vm.registerText(regs[inst.arg2], diag, "compare rhs");
                    regs[inst.dest] = .{ .int = switch (std.mem.order(u8, lhs, rhs)) {
                        .lt => -1,
                        .eq => 0,
                        .gt => 1,
                    } };
                },
                .string_contains, .string_begins_with => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string predicate register out of range", .{});
                    const haystack = try vm.registerText(regs[inst.arg1], diag, "string predicate haystack");
                    const needle = try vm.registerText(regs[inst.arg2], diag, "string predicate needle");
                    regs[inst.dest] = .{ .bool = if (inst.opcode == .string_contains)
                        std.mem.indexOf(u8, haystack, needle) != null
                    else
                        std.mem.startsWith(u8, haystack, needle) };
                },
                .string_find => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_find register out of range", .{});
                    const haystack = try vm.registerText(regs[inst.arg1], diag, "find haystack");
                    const needle = try vm.registerText(regs[inst.arg2], diag, "find needle");
                    const found = if (inst.arg3 == 0) std.mem.indexOf(u8, haystack, needle) else std.mem.lastIndexOf(u8, haystack, needle);
                    regs[inst.dest] = .{ .int = if (found) |idx| @intCast(idx) else -1 };
                },
                .string_trim => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_trim register out of range", .{});
                    const text = try vm.registerText(regs[inst.arg1], diag, "trim source");
                    const trimmed = std.mem.trim(u8, text, " \t\r\n");
                    const owned = try vm.allocator.dupe(u8, trimmed);
                    errdefer vm.allocator.free(owned);
                    try vm.rendered_code_strings.append(vm.allocator, owned);
                    regs[inst.dest] = .{ .string = owned };
                },
                .string_parse_int => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_parse_int register out of range", .{});
                    const text = try vm.registerText(regs[inst.arg1], diag, "string_to_int source");
                    const parsed = std.fmt.parseInt(i64, std.mem.trim(u8, text, " \t\r\n"), 10) catch null;
                    regs[inst.arg2] = .{ .bool = parsed != null };
                    regs[inst.dest] = .{ .int = parsed orelse 0 };
                },
                .string_parse_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_parse_float register out of range", .{});
                    const text = try vm.registerText(regs[inst.arg1], diag, "string_to_float source");
                    const parsed = std.fmt.parseFloat(f64, std.mem.trim(u8, text, " \t\r\n")) catch null;
                    regs[inst.arg2] = .{ .bool = parsed != null };
                    regs[inst.dest] = .{ .float = parsed orelse 0 };
                },
                .string_index => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_index register out of range", .{});
                    const bytes = switch (regs[inst.arg1]) {
                        .string => |v| v,
                        else => return diag.failAt(0, "VM string_index requires string operand", .{}),
                    };
                    const index = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM string_index requires integer index", .{}),
                    };
                    if (index < 0 or index >= bytes.len) return diag.failAt(0, "VM string index out of bounds", .{});
                    regs[inst.dest] = .{ .int = bytes[@intCast(index)] };
                },
                .path_strip_filename => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM path_strip_filename register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "path_strip_filename source");
                    regs[inst.dest] = .{ .string = try vm.pathStripFilename(path) };
                },
                .cmp_lt_int, .cmp_le_int, .cmp_gt_int, .cmp_ge_int => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM integer comparison register out of range", .{});
                    const lhs = try numericAsFloatOrInt(regs[inst.arg1], diag, "numeric comparison lhs");
                    const rhs = try numericAsFloatOrInt(regs[inst.arg2], diag, "numeric comparison rhs");
                    regs[inst.dest] = .{ .bool = switch (inst.opcode) {
                        .cmp_lt_int => lhs < rhs,
                        .cmp_le_int => lhs <= rhs,
                        .cmp_gt_int => lhs > rhs,
                        .cmp_ge_int => lhs >= rhs,
                        else => unreachable,
                    } };
                },
                .cmp_eq, .cmp_ne => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM equality comparison register out of range", .{});
                    const equal = registerValuesEqual(regs[inst.arg1], regs[inst.arg2]);
                    regs[inst.dest] = .{ .bool = if (inst.opcode == .cmp_eq) equal else !equal };
                },
                .jump => {
                    if (inst.arg1 >= proc.instructions.items.len) return diag.failAt(0, "VM jump target out of range", .{});
                    ip = inst.arg1;
                },
                .jump_if_false => {
                    if (inst.arg1 >= regs.len or inst.arg2 > proc.instructions.items.len) return diag.failAt(0, "VM conditional jump out of range", .{});
                    const cond = try registerTruthy(regs[inst.arg1], diag, "conditional jump");
                    if (!cond) ip = inst.arg2;
                },
                .neg_int => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM neg_int register out of range", .{});
                    regs[inst.dest] = .{ .int = -switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM neg_int requires integer operand", .{}),
                    } };
                },
                .neg_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM neg_float register out of range", .{});
                    regs[inst.dest] = .{ .float = -switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM neg_float requires numeric operand", .{}),
                    } };
                },
                .not_bool => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM not_bool register out of range", .{});
                    const value = try registerTruthy(regs[inst.arg1], diag, "not operand");
                    regs[inst.dest] = .{ .bool = !value };
                },
                .bool_to_int_cast => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM bool_to_int_cast register out of range", .{});
                    const value = switch (regs[inst.arg1]) {
                        .bool => |v| v,
                        else => return diag.failAt(0, "VM bool_to_int_cast requires bool operand", .{}),
                    };
                    regs[inst.dest] = .{ .int = if (value) 1 else 0 };
                },
                .int_trunc_cast => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM int_trunc_cast register out of range", .{});
                    const value: i64 = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        .bool => |v| if (v) @as(i64, 1) else @as(i64, 0),
                        .float => |v| @intFromFloat(v),
                        .ptr => 1,
                        else => return diag.failAt(0, "VM int_trunc_cast requires numeric, bool, or pointer operand", .{}),
                    };
                    regs[inst.dest] = .{ .int = truncateIntForType(value, inst.arg2) };
                },
                .int_to_bool_cast => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM int_to_bool_cast register out of range", .{});
                    regs[inst.dest] = .{ .bool = try registerTruthy(regs[inst.arg1], diag, "bool cast") };
                },
                .float_cast => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM float_cast register out of range", .{});
                    regs[inst.dest] = .{ .float = switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        .bool => |v| if (v) @as(i64, 1) else @as(i64, 0),
                        else => return diag.failAt(0, "VM float_cast requires numeric or bool operand", .{}),
                    } };
                },
                .bit_not => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM bit_not register out of range", .{});
                    const value = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM bit_not requires integer operand", .{}),
                    };
                    regs[inst.dest] = .{ .int = ~value };
                },
                .mul_int, .rem_int, .add_int, .sub_int, .div_int, .bit_and, .bit_or, .bit_xor, .shl_int, .shr_int, .rotl_int => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM integer arithmetic register out of range", .{});
                    if (inst.opcode == .sub_int and regs[inst.arg1] == .ptr and regs[inst.arg2] == .ptr) {
                        const lhs_ptr = regs[inst.arg1].ptr;
                        const rhs_ptr = regs[inst.arg2].ptr;
                        if (lhs_ptr.block != rhs_ptr.block) return diag.failAt(0, "VM pointer subtraction requires pointers into the same object", .{});
                        regs[inst.dest] = .{ .int = @as(i64, @intCast(lhs_ptr.offset)) - @as(i64, @intCast(rhs_ptr.offset)) };
                        continue;
                    }
                    if (inst.opcode == .add_int and regs[inst.arg1] == .ptr and regs[inst.arg2] == .int) {
                        const ptr = regs[inst.arg1].ptr;
                        const offset = regs[inst.arg2].int;
                        if (offset < 0 and @as(usize, @intCast(-offset)) > ptr.offset) return diag.failAt(0, "VM pointer addition moved before object start", .{});
                        regs[inst.dest] = .{ .ptr = .{ .block = ptr.block, .offset = if (offset < 0) ptr.offset - @as(usize, @intCast(-offset)) else ptr.offset + @as(usize, @intCast(offset)) } };
                        continue;
                    }
                    if (inst.opcode == .add_int and regs[inst.arg1] == .int and regs[inst.arg2] == .ptr) {
                        const ptr = regs[inst.arg2].ptr;
                        const offset = regs[inst.arg1].int;
                        if (offset < 0 and @as(usize, @intCast(-offset)) > ptr.offset) return diag.failAt(0, "VM pointer addition moved before object start", .{});
                        regs[inst.dest] = .{ .ptr = .{ .block = ptr.block, .offset = if (offset < 0) ptr.offset - @as(usize, @intCast(-offset)) else ptr.offset + @as(usize, @intCast(offset)) } };
                        continue;
                    }
                    if (inst.opcode == .sub_int and regs[inst.arg1] == .ptr and regs[inst.arg2] == .int) {
                        const ptr = regs[inst.arg1].ptr;
                        const offset = regs[inst.arg2].int;
                        if (offset < 0) {
                            regs[inst.dest] = .{ .ptr = .{ .block = ptr.block, .offset = ptr.offset + @as(usize, @intCast(-offset)) } };
                        } else {
                            if (@as(usize, @intCast(offset)) > ptr.offset) return diag.failAt(0, "VM pointer subtraction moved before object start", .{});
                            regs[inst.dest] = .{ .ptr = .{ .block = ptr.block, .offset = ptr.offset - @as(usize, @intCast(offset)) } };
                        }
                        continue;
                    }
                    const lhs = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM {s} requires integer lhs, got {s}", .{ @tagName(inst.opcode), @tagName(regs[inst.arg1]) }),
                    };
                    const rhs = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM {s} requires integer rhs, got {s}", .{ @tagName(inst.opcode), @tagName(regs[inst.arg2]) }),
                    };
                    regs[inst.dest] = .{ .int = switch (inst.opcode) {
                        .mul_int => lhs * rhs,
                        .rem_int => @rem(lhs, rhs),
                        .add_int => lhs + rhs,
                        .sub_int => lhs - rhs,
                        .div_int => @divTrunc(lhs, rhs),
                        .bit_and => lhs & rhs,
                        .bit_or => lhs | rhs,
                        .bit_xor => lhs ^ rhs,
                        .shl_int, .rotl_int => lhs << @intCast(@mod(rhs, @as(i64, @bitSizeOf(i64)))),
                        .shr_int => lhs >> @intCast(@mod(rhs, @as(i64, @bitSizeOf(i64)))),
                        else => unreachable,
                    } };
                },
                .bool_and, .bool_or => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM boolean operator register out of range", .{});
                    const lhs = try registerTruthy(regs[inst.arg1], diag, "boolean lhs");
                    const rhs = try registerTruthy(regs[inst.arg2], diag, "boolean rhs");
                    regs[inst.dest] = .{ .bool = if (inst.opcode == .bool_and) lhs and rhs else lhs or rhs };
                },
                .select_value => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len or inst.arg3 >= regs.len) return diag.failAt(0, "VM select register out of range", .{});
                    const cond = try registerTruthy(regs[inst.arg1], diag, "select condition");
                    regs[inst.dest] = if (cond) regs[inst.arg2] else regs[inst.arg3];
                },
                .mul_float, .add_float, .sub_float, .div_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM float arithmetic register out of range", .{});
                    const lhs = switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM float arithmetic requires numeric lhs", .{}),
                    };
                    const rhs = switch (regs[inst.arg2]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM float arithmetic requires numeric rhs", .{}),
                    };
                    regs[inst.dest] = .{ .float = switch (inst.opcode) {
                        .mul_float => lhs * rhs,
                        .add_float => lhs + rhs,
                        .sub_float => lhs - rhs,
                        .div_float => lhs / rhs,
                        else => unreachable,
                    } };
                },
                .sin_float, .sqrt_float, .cos_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM unary float math register out of range", .{});
                    const arg = switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM {s} requires numeric operand", .{@tagName(inst.opcode)}),
                    };
                    regs[inst.dest] = .{ .float = switch (inst.opcode) {
                        .sin_float => std.math.sin(arg),
                        .sqrt_float => std.math.sqrt(arg),
                        .cos_float => std.math.cos(arg),
                        else => unreachable,
                    } };
                },
                .load => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM load register out of range", .{});
                    regs[inst.dest] = regs[inst.arg1];
                },
                .store => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM store register out of range", .{});
                    regs[inst.dest] = regs[inst.arg1];
                },
                .addr_of_local => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM addr_of_local register out of range", .{});
                    if (regs[inst.arg1] == .build_options or regs[inst.arg1] == .build_llvm_options) {
                        regs[inst.dest] = regs[inst.arg1];
                        continue;
                    }
                    const ptr = local_ptrs[inst.arg1] orelse blk: {
                        const allocated = try vm.materializeRegister(regs[inst.arg1], diag);
                        local_ptrs[inst.arg1] = allocated;
                        break :blk allocated;
                    };
                    regs[inst.dest] = .{ .ptr = ptr };
                },
                .proc_addr => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM proc_addr register out of range", .{});
                    regs[inst.dest] = .{ .int = 1 };
                },
                .call_extern => {
                    if (inst.dest != @intFromEnum(Bytecode.ExternSymbol.openjai_print)) return diag.failAt(0, "VM only supports compile-time print extern calls", .{});
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM print argument register out of range", .{});
                    try vm.printValue(regs[inst.arg1], diag, "compile-time print");
                },
                .call => {
                    if (inst.arg1 >= vm.program.procs.items.len) return diag.failAt(0, "VM call target procedure index out of range", .{});
                    if (inst.arg3 + inst.arg2 > vm.program.call_args.items.len) return diag.failAt(0, "VM call argument table out of range", .{});
                    const call_args = try vm.allocator.alloc(RegisterValue, inst.arg2);
                    defer vm.allocator.free(call_args);
                    for (call_args, 0..) |*arg, arg_index| {
                        const reg_index = vm.program.call_args.items[inst.arg3 + arg_index];
                        if (reg_index >= regs.len) return diag.failAt(0, "VM call argument register out of range", .{});
                        if (regs[reg_index] == .empty) return diag.failAt(0, "VM call argument register was not initialized", .{});
                        arg.* = regs[reg_index];
                    }
                    const result = try vm.runProcWithRegisterArgs(inst.arg1, call_args, diag);
                    if (result != .empty) {
                        if (inst.dest >= regs.len) return diag.failAt(0, "VM call result register out of range", .{});
                        regs[inst.dest] = result;
                    }
                },
                .call_foreign => {
                    if (inst.arg1 >= vm.program.foreign_functions.items.len) return diag.failAt(0, "VM foreign call target out of range", .{});
                    const foreign = vm.program.foreign_functions.items[inst.arg1];
                    return diag.failAt(0, "compile-time execution cannot call foreign procedure '{s}'", .{foreign.name});
                },
                .format_print => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM format_print register out of range", .{});
                    try vm.printValue(regs[inst.arg1], diag, "format_print");
                },
                .current_time_consensus_low => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM time destination register out of range", .{});
                    regs[inst.dest] = .{ .int = try vm.hostRealtimeNs(diag) };
                },
                .current_time_monotonic_low => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM time destination register out of range", .{});
                    regs[inst.dest] = .{ .int = try vm.hostMonotonicNs(diag) };
                },
                .get_time_seconds => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM time float destination register out of range", .{});
                    regs[inst.dest] = .{ .float = @as(f64, @floatFromInt(try vm.hostRealtimeNs(diag))) / @as(f64, @floatFromInt(std.time.ns_per_s)) };
                },
                .seconds_since_init => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM time float destination register out of range", .{});
                    const now = try vm.hostMonotonicNs(diag);
                    const start = vm.start_monotonic_ns orelse blk: {
                        vm.start_monotonic_ns = now;
                        break :blk now;
                    };
                    regs[inst.dest] = .{ .float = @as(f64, @floatFromInt(now - start)) / @as(f64, @floatFromInt(std.time.ns_per_s)) };
                },
                .to_float64_seconds => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM to_float64_seconds register out of range", .{});
                    const low = try registerInt(regs[inst.arg1], diag, "to_float64_seconds");
                    regs[inst.dest] = .{ .float = @as(f64, @floatFromInt(low)) / @as(f64, @floatFromInt(std.time.ns_per_s)) };
                },
                .random_seed => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM random_seed seed register out of range", .{});
                    const seed = try registerInt(regs[inst.arg1], diag, "random_seed seed");
                    const bits: u64 = @bitCast(seed);
                    vm.random_state = if (bits == 0) 0x9e3779b97f4a7c15 else bits;
                },
                .random_get => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM random_get destination register out of range", .{});
                    regs[inst.dest] = .{ .int = @bitCast(vm.nextRandom()) };
                },
                .random_get_zero_to_one => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM random_get_zero_to_one destination register out of range", .{});
                    regs[inst.dest] = .{ .float = vm.nextRandomZeroToOne() };
                },
                .random_get_within_range => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM random_get_within_range register out of range", .{});
                    const min = try numericAsFloatOrInt(regs[inst.arg1], diag, "random_get_within_range minimum");
                    const max = try numericAsFloatOrInt(regs[inst.arg2], diag, "random_get_within_range maximum");
                    regs[inst.dest] = .{ .float = min + (max - min) * vm.nextRandomZeroToOne() };
                },
                .to_calendar => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM to_calendar register out of range", .{});
                    const low = try registerInt(regs[inst.arg1], diag, "to_calendar time");
                    if (low < 0) return diag.failAt(0, "VM to_calendar requires nonnegative Apollo_Time.low", .{});
                    regs[inst.dest] = .{ .calendar = try vm.hostToCalendar(@intCast(low), inst.arg2, diag) };
                },
                .load_calendar_field => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM load_calendar_field register out of range", .{});
                    const calendar = switch (regs[inst.arg1]) {
                        .calendar => |value| value,
                        else => return diag.failAt(0, "Calendar field access requires Calendar value", .{}),
                    };
                    regs[inst.dest] = .{ .int = try calendarFieldValue(calendar, inst.arg2, diag) };
                },
                .calendar_to_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM calendar_to_string register out of range", .{});
                    const calendar = switch (regs[inst.arg1]) {
                        .calendar => |value| value,
                        else => return diag.failAt(0, "calendar_to_string requires Calendar value", .{}),
                    };
                    regs[inst.dest] = .{ .string = try vm.calendarToString(calendar) };
                },
                .ret => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM return register out of range", .{});
                    return switch (regs[inst.arg1]) {
                        .empty => diag.failAt(0, "VM #run return register was not initialized", .{}),
                        else => regs[inst.arg1],
                    };
                },
                .ret_multi => {
                    if (inst.arg2 == 0) return .empty;
                    if (inst.arg1 + inst.arg2 > vm.program.call_args.items.len) return diag.failAt(0, "VM multi-return register table out of range", .{});
                    const values = try vm.allocator.alloc(RegisterValue, inst.arg2);
                    for (values, 0..) |*value, value_index| {
                        const reg_index = vm.program.call_args.items[inst.arg1 + value_index];
                        if (reg_index >= regs.len) return diag.failAt(0, "VM multi-return register out of range", .{});
                        if (regs[reg_index] == .empty) return diag.failAt(0, "VM multi-return register was not initialized", .{});
                        value.* = regs[reg_index];
                    }
                    return .{ .tuple = values };
                },
                .assert_true => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM assert register out of range", .{});
                    if (!try registerTruthy(regs[inst.arg1], diag, "assert condition")) {
                        return diag.failAt(inst.source_node, "compile-time assert failed", .{});
                    }
                },
                .ret_void => return .empty,
                .tuple_extract => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM tuple_extract register out of range", .{});
                    const tuple = switch (regs[inst.arg1]) {
                        .tuple => |values| values,
                        else => return diag.failAt(0, "multi-return destructuring requires a tuple result", .{}),
                    };
                    if (inst.arg2 >= tuple.len) return diag.failAt(0, "multi-return destructuring index out of range", .{});
                    regs[inst.dest] = tuple[inst.arg2];
                },
                .exit_process => return .empty,
                .alloc_heap => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM alloc_heap destination register out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.allocOwnedBlock(@max(inst.arg1, 1), allocator_proc_default) };
                },
                .alloc_heap_reg, .alloc_heap_owned => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM allocator allocation register out of range", .{});
                    if (inst.opcode == .alloc_heap_owned and inst.arg2 >= regs.len) return diag.failAt(0, "VM owned allocator register out of range", .{});
                    const size = try registerInt(regs[inst.arg1], diag, "allocation size");
                    var owner = allocator_proc_default;
                    if (inst.opcode == .alloc_heap_owned) {
                        const allocator_value = try vm.readAllocatorValue(regs[inst.arg2], diag);
                        owner = allocator_value.proc_id;
                        if (allocator_value.proc_id == allocator_proc_pool or allocator_value.proc_id == allocator_proc_flat_pool) {
                            try vm.chargePoolAllocation(allocator_value.data, @intCast(@max(size, 1)), false, diag);
                        }
                    }
                    regs[inst.dest] = .{ .ptr = try vm.allocOwnedBlock(@intCast(@max(size, 1)), owner) };
                },
                .allocator_proc_call => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM allocator_proc_call destination register out of range", .{});
                    regs[inst.dest] = .{ .int = 0 };
                },
                .allocator_owns => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM allocator_owns destination register out of range", .{});
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM allocator_owns argument register out of range", .{});
                    const allocator_value = try vm.readAllocatorValue(regs[inst.arg1], diag);
                    const memory = try registerPointer(regs[inst.arg2], diag, "allocator ownership query pointer");
                    regs[inst.dest] = .{ .bool = (vm.allocation_owners.get(memory.block) orelse allocator_proc_default) == allocator_value.proc_id };
                },
                .allocator_cap_flags => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM allocator_cap_flags destination register out of range", .{});
                    regs[inst.dest] = .{ .int = 8 };
                },
                .allocator_cap_name => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM allocator_cap_name destination register out of range", .{});
                    const name = if (inst.arg1 < regs.len) blk: {
                        const allocator_value = vm.readAllocatorValue(regs[inst.arg1], diag) catch break :blk "OpenJai allocator";
                        break :blk allocatorName(allocator_value.proc_id);
                    } else "OpenJai allocator";
                    regs[inst.dest] = .{ .string = name };
                },
                .pool_get => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM pool_get register out of range", .{});
                    const size = try registerInt(regs[inst.arg2], diag, "pool allocation size");
                    const pool = try registerPointer(regs[inst.arg1], diag, "pool_get pool pointer");
                    try vm.chargePoolAllocation(pool, @intCast(@max(size, 1)), true, diag);
                    const owner = if (inst.arg3 == 1) allocator_proc_flat_pool else allocator_proc_pool;
                    regs[inst.dest] = .{ .ptr = try vm.allocOwnedBlock(@intCast(@max(size, 1)), owner) };
                },
                .pool_release => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM pool_release register out of range", .{});
                    try vm.setPoolReleased(try registerPointer(regs[inst.arg1], diag, "pool release pointer"), diag);
                },
                .pool_reset => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM pool_reset register out of range", .{});
                    try vm.resetPool(try registerPointer(regs[inst.arg1], diag, "pool reset pointer"), diag);
                },
                .pool_bytes_left => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM pool_bytes_left destination register out of range", .{});
                    regs[inst.dest] = .{ .int = try vm.poolBytesLeft(try registerPointer(regs[inst.arg1], diag, "pool bytes_left pointer"), diag) };
                },
                .load_ptr, .load_ptr_byte, .load_ptr_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM load_ptr register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "load_ptr");
                    regs[inst.dest] = if (inst.opcode == .load_ptr_byte)
                        .{ .int = try vm.loadByte(ptr, diag) }
                    else if (inst.opcode == .load_ptr_float)
                        .{ .float = if (inst.arg2 == 4) @as(f64, @floatCast(try vm.loadF32(ptr, diag))) else @bitCast(try vm.loadU64(ptr, diag)) }
                    else
                        .{ .int = @bitCast(try vm.loadU64(ptr, diag)) };
                },
                .ptr_offset => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM ptr_offset register out of range", .{});
                    var ptr = try registerPointer(regs[inst.arg1], diag, "ptr_offset");
                    ptr.offset += inst.arg2;
                    regs[inst.dest] = .{ .ptr = ptr };
                },
                .ptr_offset_reg => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM ptr_offset_reg register out of range", .{});
                    var ptr = try registerPointer(regs[inst.arg1], diag, "ptr_offset_reg");
                    const offset = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM ptr_offset_reg requires integer offset", .{}),
                    };
                    if (offset < 0) return diag.failAt(0, "VM ptr_offset_reg does not support negative offsets yet", .{});
                    ptr.offset += @intCast(offset);
                    regs[inst.dest] = .{ .ptr = ptr };
                },
                .alloc_local_bytes => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM pointer/array destination register out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.allocBlock(@max(inst.arg1, 1)) };
                },
                .new_array => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM new_array destination register out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.newDynamicArray(@intCast(inst.arg1), @intCast(@max(inst.arg2, 1)), diag) };
                },
                .array_add => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM array_add register out of range", .{});
                    const slot = try registerPointer(regs[inst.arg1], diag, "array_add slot");
                    regs[inst.dest] = .{ .ptr = if (inst.arg5 != 0)
                        try vm.dynamicArrayAddSpread(slot, regs[inst.arg2], @intCast(@max(inst.arg3, 1)), diag)
                    else
                        try vm.dynamicArrayAdd(slot, regs[inst.arg2], @intCast(@max(inst.arg3, 1)), diag) };
                },
                .array_pop => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM array_pop register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "array_pop array");
                    regs[inst.dest] = try vm.dynamicArrayPop(ptr, @intCast(@max(inst.arg3, 1)), inst.arg4, diag);
                },
                .array_reset => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM array_reset register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "array_reset array");
                    try vm.dynamicArrayReset(ptr, @intCast(@max(inst.arg3, 1)), diag);
                },
                .array_reserve => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM array_reserve register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "array_reserve array");
                    const capacity = switch (regs[inst.arg2]) {
                        .int => |value| value,
                        else => return diag.failAt(0, "VM array_reserve capacity must be integer", .{}),
                    };
                    if (capacity < 0) return diag.failAt(0, "VM array_reserve capacity cannot be negative", .{});
                    try vm.dynamicArrayReserve(ptr, @intCast(capacity), @intCast(@max(inst.arg3, 1)), diag);
                },
                .array_ordered_remove_by_index => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM array_ordered_remove_by_index register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "array_ordered_remove_by_index array");
                    const index = switch (regs[inst.arg2]) {
                        .int => |value| value,
                        else => return diag.failAt(0, "VM array_ordered_remove_by_index index must be integer", .{}),
                    };
                    if (index < 0) return diag.failAt(0, "VM array_ordered_remove_by_index index cannot be negative", .{});
                    try vm.dynamicArrayOrderedRemove(ptr, @intCast(index), @intCast(@max(inst.arg3, 1)), diag);
                },
                .array_find => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM array_find register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "array_find array");
                    regs[inst.dest] = .{ .bool = try vm.dynamicArrayFind(ptr, regs[inst.arg2], @intCast(@max(inst.arg3, 1)), inst.arg4, diag) };
                },
                .array_copy => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM array_copy register out of range", .{});
                    const source = try registerPointer(regs[inst.arg1], diag, "array_copy source");
                    if (inst.arg5 != 0) {
                        if (inst.arg2 >= regs.len) return diag.failAt(0, "VM array_copy destination register out of range", .{});
                        const dest = try registerPointer(regs[inst.arg2], diag, "array_copy destination");
                        regs[inst.dest] = .{ .ptr = try vm.dynamicArrayCopyTo(dest, source, @intCast(@max(inst.arg3, 1)), diag) };
                    } else {
                        regs[inst.dest] = .{ .ptr = try vm.dynamicArrayCopy(source, @intCast(@max(inst.arg3, 1)), diag) };
                    }
                },
                .sort_array => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM sort_array register out of range", .{});
                    const array_ptr = try registerPointer(regs[inst.arg1], diag, "sort_array");
                    if (inst.arg5 != 0) {
                        try vm.sortStaticArray(array_ptr, @intCast(inst.arg2), @intCast(@max(inst.arg3, 1)), inst.arg4, diag);
                    } else {
                        try vm.sortDynamicArray(array_ptr, inst.arg4, diag);
                    }
                    regs[inst.dest] = regs[inst.arg1];
                },
                .array_count => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM array_count register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast(try vm.arrayCount(regs[inst.arg1], @intCast(inst.arg3), diag)) };
                },
                .array_data => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM array_data register out of range", .{});
                    regs[inst.dest] = switch (regs[inst.arg1]) {
                        .bytes => |bytes| .{ .ptr = try vm.materializeRegister(.{ .bytes = bytes }, diag) },
                        .ptr => |ptr| .{ .ptr = try vm.dynamicArrayData(ptr, diag) orelse ptr },
                        else => return diag.failAt(0, "VM array_data requires array-compatible value", .{}),
                    };
                },
                .array_index => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM array_index register out of range", .{});
                    const index = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM array_index requires integer index", .{}),
                    };
                    if (index < 0) return diag.failAt(0, "VM array_index does not support negative indices", .{});
                    const elem_size: usize = @intCast(@max(inst.arg3, 1));
                    switch (regs[inst.arg1]) {
                        .bytes => |bytes| {
                            const offset = @as(usize, @intCast(index)) * elem_size;
                            if (offset + elem_size > bytes.len) return diag.failAt(0, "VM array_index out of bounds", .{});
                            regs[inst.dest] = if (inst.arg4 == 1)
                                .{ .bytes = bytes[offset .. offset + elem_size] }
                            else if (elem_size == 1)
                                .{ .int = bytes[offset] }
                            else
                                .{ .int = readIntLittle(bytes[offset .. offset + @min(elem_size, 8)]) };
                        },
                        .ptr => |ptr| {
                            if (try vm.dynamicArrayIndex(ptr, @intCast(index), elem_size, inst.arg4, diag)) |item_value| {
                                regs[inst.dest] = item_value;
                                continue;
                            }
                            var item = ptr;
                            item.offset += @as(usize, @intCast(index)) * elem_size;
                            regs[inst.dest] = if (inst.arg4 == 1)
                                .{ .ptr = item }
                            else if (inst.arg4 == 2)
                                return diag.failAt(0, "VM array_index cannot load string elements from an untracked raw pointer", .{})
                            else if (elem_size == 1)
                                .{ .int = try vm.loadByte(item, diag) }
                            else
                                .{ .int = @bitCast(try vm.loadU64(item, diag)) };
                        },
                        .code_nodes => |nodes| {
                            if (index >= nodes.len) return diag.failAt(0, "VM Code_Node array index out of bounds", .{});
                            regs[inst.dest] = .{ .code_node = nodes[@intCast(index)] };
                        },
                        .code_notes => |notes| {
                            if (index >= notes.len) return diag.failAt(0, "VM Code_Note array index out of bounds", .{});
                            regs[inst.dest] = .{ .code_note = notes[@intCast(index)] };
                        },
                        .code_args => |code_arguments| {
                            if (index >= code_arguments.len) return diag.failAt(0, "VM Code_Argument array index out of bounds", .{});
                            regs[inst.dest] = .{ .code_arg = code_arguments[@intCast(index)] };
                        },
                        else => return diag.failAt(0, "VM array_index requires array or pointer value", .{}),
                    }
                },
                .compiler_get_nodes_root => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_get_nodes root register out of range", .{});
                    const code = try registerCodeValue(regs[inst.arg1], diag, "compiler_get_nodes");
                    const tree = try vm.ensureCodeTree(code);
                    regs[inst.dest] = .{ .code_node = vm.code_trees.items[tree].root };
                },
                .compiler_get_nodes_exprs => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_get_nodes expressions register out of range", .{});
                    const code = try registerCodeValue(regs[inst.arg1], diag, "compiler_get_nodes");
                    const tree = try vm.ensureCodeTree(code);
                    regs[inst.dest] = .{ .code_nodes = vm.code_trees.items[tree].nodes };
                },
                .code_node_field_kind => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Node.kind register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Node.kind requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .string = node.kind };
                },
                .code_node_field_flags => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Node.node_flags register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Node.node_flags requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .string = node.flags };
                },
                .code_node_field_expression => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Declaration.expression register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Declaration.expression requires a Code_Node value", .{}),
                    };
                    if (node.expression_index) |expression_index| {
                        if (node.tree < vm.code_trees.items.len) {
                            const tree = vm.code_trees.items[node.tree];
                            if (expression_index >= tree.nodes.len) return diag.failAt(0, "VM Code_Declaration.expression index out of range", .{});
                            regs[inst.dest] = .{ .code_node = tree.nodes[expression_index] };
                            continue;
                        }
                        if (expression_index >= vm.compiler_message_nodes.items.len) return diag.failAt(0, "VM Code_Declaration.expression index out of range", .{});
                        regs[inst.dest] = .{ .code_node = vm.compiler_message_nodes.items[expression_index] };
                        continue;
                    }
                    regs[inst.dest] = .{ .code_node = node };
                },
                .code_node_field_name => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Node.name register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Node.name requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .string = if (node.name.len != 0) node.name else node.text };
                },
                .code_node_field_notes => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Node.notes register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Node.notes requires a Code_Node value", .{}),
                    };
                    if (node.note_start > vm.compiler_message_notes.items.len or node.note_count > vm.compiler_message_notes.items.len - node.note_start) return diag.failAt(0, "VM Code_Node.notes slice out of range", .{});
                    regs[inst.dest] = .{ .code_notes = vm.compiler_message_notes.items[node.note_start .. node.note_start + node.note_count] };
                },
                .code_node_field_type => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Declaration.type register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Declaration.type requires a Code_Node value", .{}),
                    };
                    if (node.type_text.len == 0) return diag.failAt(0, "VM Code_Node.type requested for untyped {s} node '{s}'", .{ node.kind, node.text });
                    regs[inst.dest] = .{ .type_text = node.type_text };
                },
                .code_node_field_subexpressions => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Node.subexpressions register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Node.subexpressions requires a Code_Node value", .{}),
                    };
                    if (node.tree < vm.code_trees.items.len) {
                        const tree = vm.code_trees.items[node.tree];
                        if (node.subexpression_start > tree.nodes.len or node.subexpression_count > tree.nodes.len - node.subexpression_start) return diag.failAt(0, "VM Code_Node.subexpressions slice out of range", .{});
                        regs[inst.dest] = .{ .code_nodes = tree.nodes[node.subexpression_start .. node.subexpression_start + node.subexpression_count] };
                        continue;
                    }
                    if (node.subexpression_start > vm.compiler_message_nodes.items.len or node.subexpression_count > vm.compiler_message_nodes.items.len - node.subexpression_start) return diag.failAt(0, "VM Code_Node.subexpressions slice out of range", .{});
                    regs[inst.dest] = .{ .code_nodes = vm.compiler_message_nodes.items[node.subexpression_start .. node.subexpression_start + node.subexpression_count] };
                },
                .code_node_field_enclosing_load => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Node.enclosing_load register out of range", .{});
                    switch (regs[inst.arg1]) {
                        .code_node => {},
                        else => return diag.failAt(0, "VM Code_Node.enclosing_load requires a Code_Node value", .{}),
                    }
                    regs[inst.dest] = .{ .bool = false };
                },
                .code_note_field_text => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Note.text register out of range", .{});
                    const note = switch (regs[inst.arg1]) {
                        .code_note => |v| v,
                        else => return diag.failAt(0, "VM Code_Note.text requires a Code_Note value", .{}),
                    };
                    regs[inst.dest] = .{ .string = note.text };
                },
                .code_proc_call_arguments => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Procedure_Call.arguments_unsorted register out of range", .{});
                    const node = try vm.currentCodeNode(regs[inst.arg1], diag, "Code_Procedure_Call.arguments_unsorted");
                    if (!std.mem.eql(u8, node.kind, "PROCEDURE_CALL")) return diag.failAt(0, "VM Code_Procedure_Call.arguments_unsorted requires a procedure-call node", .{});
                    if (node.tree >= vm.code_trees.items.len) return diag.failAt(0, "VM Code_Procedure_Call.arguments_unsorted got a detached Code_Node", .{});
                    const tree = vm.code_trees.items[node.tree];
                    const start: usize = @intCast(node.arg_start);
                    const count: usize = @intCast(node.arg_count);
                    if (start > tree.arguments.len or count > tree.arguments.len - start) return diag.failAt(0, "VM Code_Procedure_Call.arguments_unsorted slice is out of range", .{});
                    regs[inst.dest] = .{ .code_args = tree.arguments[start .. start + count] };
                },
                .code_argument_field_expression => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Argument.expression register out of range", .{});
                    const arg = switch (regs[inst.arg1]) {
                        .code_arg => |value| value,
                        else => return diag.failAt(0, "VM Code_Argument.expression requires a Code_Argument value", .{}),
                    };
                    if (arg.tree >= vm.code_trees.items.len or arg.expression_index >= vm.code_trees.items[arg.tree].nodes.len) return diag.failAt(0, "VM Code_Argument.expression got a detached expression node", .{});
                    regs[inst.dest] = .{ .code_node = vm.code_trees.items[arg.tree].nodes[arg.expression_index] };
                },
                .code_literal_field_value_type => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Literal.value_type register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM Code_Literal.value_type requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .int = if (node.s64 != null) 0 else if (node.string_value != null) 1 else -1 };
                },
                .code_literal_field_s64 => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Literal._s64 register out of range", .{});
                    const node = try vm.currentCodeNode(regs[inst.arg1], diag, "Code_Literal._s64");
                    regs[inst.dest] = .{ .int = node.s64 orelse return diag.failAt(0, "VM Code_Literal._s64 requires a numeric literal node", .{}) };
                },
                .code_literal_set_s64 => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM Code_Literal._s64 setter register out of range", .{});
                    const value = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM Code_Literal._s64 setter requires integer source", .{}),
                    };
                    try vm.updateCodeLiteralS64(regs[inst.arg1], value, diag);
                    if (inst.dest < regs.len) regs[inst.dest] = .{ .int = value };
                },
                .code_literal_field_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM Code_Literal._string register out of range", .{});
                    const node = try vm.currentCodeNode(regs[inst.arg1], diag, "Code_Literal._string");
                    regs[inst.dest] = .{ .string = node.string_value orelse return diag.failAt(0, "VM Code_Literal._string requires a string literal node", .{}) };
                },
                .code_literal_set_string => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM Code_Literal._string setter register out of range", .{});
                    const value = try registerText(vm, regs[inst.arg2], diag, "Code_Literal._string setter");
                    try vm.updateCodeLiteralString(regs[inst.arg1], value, diag);
                    if (inst.dest < regs.len) regs[inst.dest] = .{ .string = value };
                },
                .code_node_to_code => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_get_code register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM compiler_get_code requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .code = .{
                        .text = try vm.renderCodeNode(node, diag),
                        .path = node.path,
                        .line_number = node.line_number,
                    } };
                },
                .code_node_location => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM make_location(Code_Node) register out of range", .{});
                    const node = switch (regs[inst.arg1]) {
                        .code_node => |v| v,
                        else => return diag.failAt(0, "VM make_location requires a Code_Node value", .{}),
                    };
                    regs[inst.dest] = .{ .source_location = .{
                        .fully_pathed_filename = node.path,
                        .line_number = node.line_number,
                    } };
                },
                .compiler_report => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_report message register out of range", .{});
                    const message = switch (regs[inst.arg1]) {
                        .string => |value| value,
                        else => return diag.failAt(0, "VM compiler_report expects a string message", .{}),
                    };
                    if (inst.arg2 != std.math.maxInt(u32)) {
                        if (inst.arg2 >= regs.len) return diag.failAt(0, "VM compiler_report location register out of range", .{});
                        const loc = switch (regs[inst.arg2]) {
                            .source_location => |value| value,
                            else => return diag.failAt(0, "VM compiler_report second argument must be a Source_Code_Location", .{}),
                        };
                        if (loc.fully_pathed_filename.len != 0) {
                            std.debug.print("{s}:{d}: {s}", .{ loc.fully_pathed_filename, loc.line_number, message });
                        } else {
                            std.debug.print("{s}", .{message});
                        }
                    } else {
                        std.debug.print("{s}", .{message});
                    }
                    if (inst.dest < regs.len) regs[inst.dest] = .{ .int = 0 };
                },
                .cpu_has_feature => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM cpu_has_feature destination register out of range", .{});
                    regs[inst.dest] = .{ .bool = false };
                },
                .load_ptr_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM pointer/array destination register out of range", .{});
                    const ptr = try registerPointer(regs[inst.arg1], diag, "load_ptr_string");
                    regs[inst.dest] = .{ .string = try vm.loadStringSlot(ptr, diag) };
                },
                .format_static_int_array, .format_static_float_array, .format_static_string_array => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM static array format register out of range", .{});
                    const array_ptr = try registerPointer(regs[inst.arg1], diag, "static array format");
                    const count: usize = @intCast(inst.arg2);
                    const kind: u32 = switch (inst.opcode) {
                        .format_static_float_array => 1,
                        .format_static_string_array => 2,
                        else => 0,
                    };
                    const elem_size: usize = @intCast(@max(inst.arg3, 1));
                    try vm.printStaticArray(array_ptr, count, elem_size, kind, diag);
                },
                .sleep_milliseconds => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM sleep_milliseconds register out of range", .{});
                    const millis = switch (regs[inst.arg1]) {
                        .int => |v| if (v < 0) 0 else @as(u64, @intCast(v)),
                        .float => |v| if (v < 0) 0 else @as(u64, @intFromFloat(v)),
                        else => return diag.failAt(0, "VM sleep_milliseconds requires numeric argument", .{}),
                    };
                    const io = try vm.requireIo(diag, "sleep_milliseconds");
                    const bounded_millis: i64 = @intCast(@min(millis, @as(u64, @intCast(std.math.maxInt(i64)))));
                    try std.Io.Clock.Duration.sleep(.{
                        .raw = std.Io.Duration.fromMilliseconds(bounded_millis),
                        .clock = .awake,
                    }, io);
                },
                .compiler_read_file => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_read_file register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "compiler_read_file path");
                    regs[inst.dest] = .{ .bytes = try vm.hostReadFile(path, diag) };
                },
                .read_entire_file => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM read_entire_file register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "read_entire_file path");
                    const result = try vm.hostReadEntireFile(path, diag);
                    regs[inst.dest] = .{ .string = result.contents };
                    if (inst.arg2 != std.math.maxInt(u32)) {
                        if (inst.arg2 >= regs.len) return diag.failAt(0, "VM read_entire_file success register out of range", .{});
                        regs[inst.arg2] = .{ .bool = result.success };
                    }
                },
                .compiler_write_file => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM compiler_write_file register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "compiler_write_file path");
                    const contents = try vm.registerText(regs[inst.arg2], diag, "compiler_write_file contents");
                    regs[inst.dest] = .{ .bool = try vm.hostWriteFile(path, contents, diag) };
                },
                .make_directory => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM make_directory register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "make_directory path");
                    regs[inst.dest] = .{ .bool = try vm.hostMakeDirectory(path, diag) };
                },
                .delete_directory => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM delete_directory register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "delete_directory path");
                    regs[inst.dest] = .{ .bool = try vm.hostDeleteDirectory(path, diag) };
                },
                .file_exists => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM file_exists register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "file_exists path");
                    regs[inst.dest] = .{ .bool = try vm.hostPathExists(path, diag) };
                },
                .set_working_directory => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM set_working_directory register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "set_working_directory path");
                    regs[inst.dest] = .{ .bool = try vm.hostSetWorkingDirectory(path, diag) };
                },
                .get_working_directory => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM get_working_directory register out of range", .{});
                    regs[inst.dest] = .{ .string = try vm.hostGetWorkingDirectory(diag) };
                },
                .get_path_of_running_executable => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM get_path_of_running_executable register out of range", .{});
                    regs[inst.dest] = .{ .string = try vm.hostGetExecutablePath(diag) };
                },
                .host_copy_file => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM copy_file register out of range", .{});
                    const src = try vm.registerText(regs[inst.arg1], diag, "copy_file source");
                    const dest = try vm.registerText(regs[inst.arg2], diag, "copy_file destination");
                    regs[inst.dest] = .{ .bool = try vm.hostCopyFile(src, dest, diag) };
                },
                .host_run_command => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM run_command register out of range", .{});
                    const command = try vm.registerText(regs[inst.arg1], diag, "run_command command");
                    regs[inst.dest] = .{ .int = try vm.hostRunCommand(command, diag) };
                },
                .host_run_command_capture => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len or inst.arg3 >= regs.len or inst.arg4 >= regs.len) return diag.failAt(0, "VM run_command capture register out of range", .{});
                    const command = try vm.registerText(regs[inst.arg1], diag, "run_command command");
                    const result = try vm.hostRunCommandCapture(command, diag);
                    regs[inst.dest] = .{ .int = result.exit_code };
                    regs[inst.arg2] = .{ .string = result.stdout };
                    regs[inst.arg3] = .{ .string = result.stderr };
                    regs[inst.arg4] = .{ .bool = result.timeout_reached };
                },
                .host_build_cpp_dynamic_lib => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM build_cpp_dynamic_lib register out of range", .{});
                    const name = try vm.registerText(regs[inst.arg1], diag, "build_cpp_dynamic_lib library name");
                    const source = try vm.registerText(regs[inst.arg2], diag, "build_cpp_dynamic_lib source file");
                    regs[inst.dest] = .{ .bool = try vm.hostBuildCppDynamicLib(name, source, diag) };
                },
                .host_generate_bindings => {
                    if (inst.dest >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM generate_bindings register out of range", .{});
                    const output = try vm.registerText(regs[inst.arg2], diag, "generate_bindings output path");
                    regs[inst.dest] = .{ .bool = try vm.hostGenerateBindings(output, diag) };
                },
                .host_add_build_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM add_build_string register out of range", .{});
                    const source = try vm.registerText(regs[inst.arg1], diag, "add_build_string source");
                    const workspace = switch (regs[inst.arg2]) {
                        .int => |value| value,
                        else => return diag.failAt(0, "add_build_string workspace argument must be an integer workspace handle", .{}),
                    };
                    regs[inst.dest] = .{ .bool = try vm.hostAddBuildString(source, workspace, diag) };
                },
                .host_add_build_file => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM add_build_file register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "add_build_file path");
                    const workspace = switch (regs[inst.arg2]) {
                        .int => |value| value,
                        else => return diag.failAt(0, "add_build_file workspace argument must be an integer workspace handle", .{}),
                    };
                    regs[inst.dest] = .{ .bool = try vm.hostAddBuildFile(path, workspace, diag) };
                },
                .host_compiler_create_workspace => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM compiler_create_workspace register out of range", .{});
                    regs[inst.dest] = .{ .int = try vm.hostCompilerCreateWorkspace(diag) };
                },
                .host_get_current_workspace => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM get_current_workspace register out of range", .{});
                    regs[inst.dest] = .{ .int = vm.hostGetCurrentWorkspace() };
                },
                .host_compiler_begin_intercept => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_begin_intercept register out of range", .{});
                    const workspace = try registerInt(regs[inst.arg1], diag, "compiler_begin_intercept workspace");
                    try vm.hostCompilerBeginIntercept(workspace, diag);
                    regs[inst.dest] = .{ .bool = true };
                },
                .host_compiler_end_intercept => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_end_intercept register out of range", .{});
                    _ = try registerInt(regs[inst.arg1], diag, "compiler_end_intercept workspace");
                    vm.intercepted_workspace = 0;
                    vm.compiler_message_queue.clearRetainingCapacity();
                    regs[inst.dest] = .{ .bool = true };
                },
                .host_compiler_wait_for_message => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM compiler_wait_for_message register out of range", .{});
                    regs[inst.dest] = if (vm.hostCompilerWaitForMessage()) |message_index|
                        .{ .message = message_index }
                    else
                        .empty;
                },
                .load_build_options => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM get_build_options register out of range", .{});
                    const workspace = if (inst.arg1 == std.math.maxInt(u32))
                        vm.hostGetCurrentWorkspace()
                    else blk: {
                        if (inst.arg1 >= regs.len) return diag.failAt(0, "VM get_build_options workspace register out of range", .{});
                        break :blk try registerInt(regs[inst.arg1], diag, "get_build_options workspace");
                    };
                    regs[inst.dest] = .{ .build_options = try vm.buildOptionsForWorkspace(workspace, diag) };
                },
                .host_set_build_options => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM set_build_options register out of range", .{});
                    const source_index = switch (regs[inst.arg1]) {
                        .build_options => |v| v,
                        else => return diag.failAt(0, "VM set_build_options requires a Build_Options value", .{}),
                    };
                    const workspace_arg = try registerInt(regs[inst.arg2], diag, "set_build_options workspace");
                    const workspace = if (workspace_arg == -1) vm.hostGetCurrentWorkspace() else workspace_arg;
                    try vm.setBuildOptionsForWorkspace(workspace, source_index, diag);
                    regs[inst.dest] = .{ .bool = true };
                },
                .host_set_optimization => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len or inst.arg3 >= regs.len) return diag.failAt(0, "VM set_optimization register out of range", .{});
                    const options_index = switch (regs[inst.arg1]) {
                        .build_options => |v| v,
                        else => return diag.failAt(0, "VM set_optimization requires a Build_Options value", .{}),
                    };
                    const mode = try vm.optimizationMode(regs[inst.arg2], diag);
                    const keep_runtime_checks = try registerTruthy(regs[inst.arg3], diag, "set_optimization runtime-check flag");
                    try vm.applyOptimization(options_index, mode, keep_runtime_checks, diag);
                    regs[inst.dest] = .{ .bool = true };
                },
                .host_set_workspace_status => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM compiler_set_workspace_status register out of range", .{});
                    const status = try vm.workspaceStatusCode(regs[inst.arg1], diag);
                    try vm.setWorkspaceStatus(status, diag);
                    regs[inst.dest] = .{ .bool = true };
                },
                .host_custom_link_complete => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM compiler_custom_link_command_is_complete register out of range", .{});
                    try vm.hostCustomLinkCommandComplete(diag);
                    regs[inst.dest] = .{ .bool = true };
                },
                .build_options_get_field => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= vm.program.strings.items.len) return diag.failAt(0, "VM Build_Options field access out of range", .{});
                    const index = switch (regs[inst.arg1]) {
                        .build_options => |v| v,
                        .build_llvm_options => |v| v,
                        else => return diag.failAt(0, "VM Build_Options field access requires a Build_Options value", .{}),
                    };
                    regs[inst.dest] = switch (regs[inst.arg1]) {
                        .build_options => try vm.buildOptionsGetField(index, vm.program.strings.items[inst.arg2], diag),
                        .build_llvm_options => try vm.buildOptionsLlvmGetField(index, vm.program.strings.items[inst.arg2], diag),
                        else => unreachable,
                    };
                },
                .message_get_field => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= vm.program.strings.items.len) return diag.failAt(0, "VM Message field access out of range", .{});
                    const index = switch (regs[inst.arg1]) {
                        .message => |value| value,
                        else => return diag.failAt(0, "VM Message field access requires a Message value", .{}),
                    };
                    regs[inst.dest] = try vm.compilerMessageGetField(index, vm.program.strings.items[inst.arg2], diag);
                },
                .type_info_field => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= vm.program.strings.items.len) return diag.failAt(0, "VM Type_Info field access out of range", .{});
                    regs[inst.dest] = try vm.typeInfoField(regs[inst.arg1], vm.program.strings.items[inst.arg2], diag);
                },
                .type_info_member_field => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= vm.program.strings.items.len) return diag.failAt(0, "VM Type_Info member field access out of range", .{});
                    regs[inst.dest] = try vm.typeInfoMemberField(regs[inst.arg1], vm.program.strings.items[inst.arg2], diag);
                },
                .source_location_get_field => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= vm.program.strings.items.len) return diag.failAt(0, "VM Source_Code_Location field access out of range", .{});
                    const loc = switch (regs[inst.arg1]) {
                        .source_location => |value| value,
                        else => return diag.failAt(0, "VM Source_Code_Location field access requires a Source_Code_Location value", .{}),
                    };
                    const field_name = vm.program.strings.items[inst.arg2];
                    if (std.mem.eql(u8, field_name, "fully_pathed_filename")) {
                        regs[inst.dest] = .{ .string = loc.fully_pathed_filename };
                    } else if (std.mem.eql(u8, field_name, "line_number")) {
                        regs[inst.dest] = .{ .int = loc.line_number };
                    } else {
                        return diag.failAt(0, "unsupported Source_Code_Location field '{s}'", .{field_name});
                    }
                },
                .build_options_set_field => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= vm.program.strings.items.len or inst.arg3 >= regs.len) return diag.failAt(0, "VM Build_Options field assignment out of range", .{});
                    const index = switch (regs[inst.arg1]) {
                        .build_options => |v| v,
                        .build_llvm_options => |v| v,
                        else => return diag.failAt(0, "VM Build_Options field assignment requires a Build_Options value", .{}),
                    };
                    switch (regs[inst.arg1]) {
                        .build_options => try vm.buildOptionsSetField(index, vm.program.strings.items[inst.arg2], regs[inst.arg3], diag),
                        .build_llvm_options => try vm.buildOptionsLlvmSetField(index, vm.program.strings.items[inst.arg2], regs[inst.arg3], diag),
                        else => unreachable,
                    }
                    if (inst.dest < regs.len) regs[inst.dest] = regs[inst.arg1];
                },
                .get_command_line_arguments => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM runtime API destination register out of range", .{});
                    regs[inst.dest] = .{ .ptr = try vm.commandLineArgumentsArray(diag) };
                },
                .file_open => {
                    if (inst.dest >= regs.len) return diag.failAt(0, "VM file_open destination register out of range", .{});
                    const path = try vm.registerText(regs[inst.arg1], diag, "file_open path");
                    const opened = try vm.hostFileOpen(path, inst.arg2 != 0, inst.arg3 != 0, diag);
                    regs[inst.dest] = .{ .int = opened.handle };
                    if (inst.arg4 != 0) {
                        const ok_reg = inst.arg4 - 1;
                        if (ok_reg >= regs.len) return diag.failAt(0, "VM file_open success register out of range", .{});
                        regs[ok_reg] = .{ .bool = opened.ok };
                    }
                },
                .file_close => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM file_close register out of range", .{});
                    try vm.hostFileClose(try registerInt(regs[inst.arg1], diag, "file_close handle"), diag);
                },
                .file_length => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM file_length register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast((try vm.hostFile(try registerInt(regs[inst.arg1], diag, "file_length handle"), diag)).contents.items.len) };
                },
                .file_set_position => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM file_set_position register out of range", .{});
                    const position = try registerInt(regs[inst.arg2], diag, "file_set_position position");
                    regs[inst.dest] = .{ .bool = if (position < 0)
                        false
                    else
                        try vm.hostFileSetPosition(try registerInt(regs[inst.arg1], diag, "file_set_position handle"), @intCast(position), diag) };
                },
                .file_write => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM file_write register out of range", .{});
                    const data = if (inst.arg4 != 0)
                        try vm.registerText(regs[inst.arg2], diag, "file_write data")
                    else blk: {
                        if (inst.arg3 >= regs.len) return diag.failAt(0, "VM file_write length register out of range", .{});
                        const len = try registerInt(regs[inst.arg3], diag, "file_write byte count");
                        if (len < 0) return diag.failAt(0, "VM file_write byte count cannot be negative", .{});
                        const ptr = try registerPointer(regs[inst.arg2], diag, "file_write data pointer");
                        break :blk try vm.blockSlice(ptr, @intCast(len), diag);
                    };
                    regs[inst.dest] = .{ .bool = try vm.hostFileWrite(try registerInt(regs[inst.arg1], diag, "file_write handle"), data, diag) };
                },
                .file_read => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len or inst.arg3 >= regs.len) return diag.failAt(0, "VM file_read register out of range", .{});
                    const len = try registerInt(regs[inst.arg3], diag, "file_read byte count");
                    if (len < 0) return diag.failAt(0, "VM file_read byte count cannot be negative", .{});
                    const ptr = try registerPointer(regs[inst.arg2], diag, "file_read destination");
                    regs[inst.dest] = .{ .bool = try vm.hostFileRead(try registerInt(regs[inst.arg1], diag, "file_read handle"), ptr, @intCast(len), diag) };
                },
                .posix_read => {
                    return diag.failAt(0, "VM does not support runtime file opcode {s} in #run yet", .{@tagName(inst.opcode)});
                },
                .string_builder_init => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM string_builder_init register out of range", .{});
                    try vm.builderInit(try registerPointer(regs[inst.arg1], diag, "string_builder_init slot"));
                },
                .string_builder_free => {
                    if (inst.arg1 >= regs.len) return diag.failAt(0, "VM string_builder_free register out of range", .{});
                    try vm.builderFree(try registerPointer(regs[inst.arg1], diag, "string_builder_free slot"));
                },
                .string_builder_append_string, .string_builder_append_int, .string_builder_append_float => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_builder_append register out of range", .{});
                    try vm.builderAppendValue(try registerPointer(regs[inst.arg1], diag, "string_builder_append slot"), regs[inst.arg2], diag);
                },
                .string_builder_append_format => {
                    if (inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM string_builder_append_format register out of range", .{});
                    if (inst.arg3 + inst.arg4 > vm.program.call_args.items.len) return diag.failAt(0, "VM string_builder_append_format call-argument range out of bounds", .{});
                    try vm.builderAppendFormat(
                        try registerPointer(regs[inst.arg1], diag, "string_builder_append_format slot"),
                        try registerText(vm, regs[inst.arg2], diag, "string_builder_append_format format"),
                        regs,
                        vm.program.call_args.items[inst.arg3 .. inst.arg3 + inst.arg4],
                        diag,
                    );
                },
                .string_builder_to_string => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_builder_to_string register out of range", .{});
                    regs[inst.dest] = .{ .string = try vm.builderString(try registerPointer(regs[inst.arg1], diag, "string_builder_to_string slot")) };
                },
                .string_builder_length => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM string_builder_length register out of range", .{});
                    regs[inst.dest] = .{ .int = @intCast((try vm.builderString(try registerPointer(regs[inst.arg1], diag, "string_builder_length slot"))).len) };
                },
                .store_ptr => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM store_ptr register out of range", .{});
                    try vm.storeRegister(try registerPointer(regs[inst.dest], diag, "store_ptr destination"), regs[inst.arg1], diag);
                },
                .store_ptr_byte => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM store_ptr_byte register out of range", .{});
                    const value: i64 = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        .bool => |v| if (v) 1 else 0,
                        else => return diag.failAt(0, "VM store_ptr_byte requires integer source", .{}),
                    };
                    try vm.storeByte(try registerPointer(regs[inst.dest], diag, "store_ptr_byte destination"), @intCast(value & 0xff), diag);
                },
                .store_ptr_float => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len) return diag.failAt(0, "VM store_ptr_float register out of range", .{});
                    const value = switch (regs[inst.arg1]) {
                        .float => |v| v,
                        .int => |v| @as(f64, @floatFromInt(v)),
                        else => return diag.failAt(0, "VM store_ptr_float requires numeric source", .{}),
                    };
                    const ptr = try registerPointer(regs[inst.dest], diag, "store_ptr_float destination");
                    if (inst.arg2 == 4)
                        try vm.storeF32(ptr, @floatCast(value), diag)
                    else
                        try vm.storeRegister(ptr, .{ .float = value }, diag);
                },
                .memcpy => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM memcpy register out of range", .{});
                    const count = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM memcpy byte count must be an integer", .{}),
                    };
                    if (count < 0) return diag.failAt(0, "VM memcpy byte count cannot be negative", .{});
                    try vm.copyBytes(try registerPointer(regs[inst.dest], diag, "memcpy destination"), regs[inst.arg1], @intCast(count), diag);
                },
                .memset => {
                    if (inst.dest >= regs.len or inst.arg1 >= regs.len or inst.arg2 >= regs.len) return diag.failAt(0, "VM memset register out of range", .{});
                    const value = switch (regs[inst.arg1]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM memset byte value must be an integer", .{}),
                    };
                    const count = switch (regs[inst.arg2]) {
                        .int => |v| v,
                        else => return diag.failAt(0, "VM memset byte count must be an integer", .{}),
                    };
                    if (count < 0) return diag.failAt(0, "VM memset byte count cannot be negative", .{});
                    @memset(try vm.blockSlice(try registerPointer(regs[inst.dest], diag, "memset destination"), @intCast(count), diag), @intCast(value & 0xff));
                },
                .free_heap, .array_free => {},
                else => return diag.failAt(0, "VM does not support opcode {s} in #run yet", .{@tagName(inst.opcode)}),
            }
        }
        return .empty;
    }

    fn allocBlock(vm: *VM, size: usize) !Pointer {
        const block = try vm.allocator.alloc(u8, size);
        @memset(block, 0);
        const index: u32 = @intCast(vm.memory_blocks.items.len);
        try vm.memory_blocks.append(vm.allocator, block);
        return .{ .block = index, .offset = 0 };
    }

    fn allocOwnedBlock(vm: *VM, size: usize, owner: u32) !Pointer {
        const ptr = try vm.allocBlock(size);
        try vm.allocation_owners.put(vm.allocator, ptr.block, owner);
        return ptr;
    }

    const AllocatorValue = struct {
        proc_id: u32,
        data: ?Pointer,
    };

    fn readAllocatorValue(vm: *VM, value: RegisterValue, diag: Diagnostic) !AllocatorValue {
        const ptr = try registerPointer(value, diag, "Allocator value");
        const proc_id: u32 = @intCast(try vm.loadU64(ptr, diag));
        var data_addr = ptr;
        data_addr.offset += 8;
        const encoded_data = try vm.loadU64(data_addr, diag);
        return .{
            .proc_id = proc_id,
            .data = if (encoded_data == 0) null else try vm.decodePointer(encoded_data, diag),
        };
    }

    fn decodePointer(vm: *VM, encoded: u64, diag: Diagnostic) !Pointer {
        const block_plus_one: u32 = @intCast(encoded >> 32);
        if (block_plus_one == 0) return diag.failAt(0, "VM encoded pointer has null block", .{});
        const block = block_plus_one - 1;
        if (block >= vm.memory_blocks.items.len) return diag.failAt(0, "VM encoded pointer block out of range", .{});
        const offset: usize = @intCast(encoded & 0xffffffff);
        if (offset > vm.memory_blocks.items[block].len) return diag.failAt(0, "VM encoded pointer offset out of range", .{});
        return .{ .block = block, .offset = offset };
    }

    fn allocatorName(proc_id: u32) []const u8 {
        return switch (proc_id) {
            allocator_proc_pool => "modules/Pool",
            allocator_proc_flat_pool => "modules/Flat_Pool",
            allocator_proc_rpmalloc => "rpmalloc 1.4.4",
            else => "stripped-down rpmalloc 1.4.4 intended as Default_Allocator",
        };
    }

    fn poolFieldPtr(pool: Pointer, offset: usize) Pointer {
        return .{ .block = pool.block, .offset = pool.offset + offset };
    }

    fn ensurePoolInitialized(vm: *VM, pool: Pointer, diag: Diagnostic) !void {
        const size_ptr = poolFieldPtr(pool, 0);
        const left_ptr = poolFieldPtr(pool, 8);
        if (try vm.loadU64(size_ptr, diag) == 0) {
            std.mem.writeInt(u64, try vm.blockArray8(size_ptr, diag), 65536, .little);
        }
        if (try vm.loadU64(left_ptr, diag) == 0) {
            std.mem.writeInt(u64, try vm.blockArray8(left_ptr, diag), 65536, .little);
        }
    }

    fn chargePoolAllocation(vm: *VM, maybe_pool: ?Pointer, size: usize, explicit_get: bool, diag: Diagnostic) !void {
        const pool = maybe_pool orelse return;
        try vm.ensurePoolInitialized(pool, diag);
        const left_ptr = poolFieldPtr(pool, 8);
        const left = try vm.loadU64(left_ptr, diag);
        const charged = size + if (explicit_get) @as(usize, 0) else 8;
        const next = if (left > charged) left - charged else 0;
        std.mem.writeInt(u64, try vm.blockArray8(left_ptr, diag), next, .little);
    }

    fn resetPool(vm: *VM, pool: Pointer, diag: Diagnostic) !void {
        try vm.ensurePoolInitialized(pool, diag);
        const size = try vm.loadU64(poolFieldPtr(pool, 0), diag);
        std.mem.writeInt(u64, try vm.blockArray8(poolFieldPtr(pool, 8), diag), size, .little);
    }

    fn setPoolReleased(vm: *VM, pool: Pointer, diag: Diagnostic) !void {
        try vm.ensurePoolInitialized(pool, diag);
        std.mem.writeInt(u64, try vm.blockArray8(poolFieldPtr(pool, 8), diag), 0, .little);
    }

    fn poolBytesLeft(vm: *VM, pool: Pointer, diag: Diagnostic) !i64 {
        return @intCast(try vm.loadU64(poolFieldPtr(pool, 8), diag));
    }

    fn globalPtr(vm: *VM, index: usize) !Pointer {
        while (vm.global_ptrs.items.len <= index) try vm.global_ptrs.append(vm.allocator, null);
        if (vm.global_ptrs.items[index]) |ptr| return ptr;
        const global = vm.program.globals.items[index];
        const ptr = try vm.allocBlock(@max(global.size, 1));
        if (global.initial_bytes) |initial| {
            const copy_len = @min(initial.len, global.size);
            if (copy_len != 0) @memcpy(vm.memory_blocks.items[ptr.block][0..copy_len], initial[0..copy_len]);
        }
        vm.global_ptrs.items[index] = ptr;
        return ptr;
    }

    pub fn globalBytes(vm: *VM, index: usize, diag: Diagnostic) !?[]const u8 {
        if (index >= vm.global_ptrs.items.len) return null;
        const ptr = vm.global_ptrs.items[index] orelse return null;
        const global = vm.program.globals.items[index];
        return try vm.blockSlice(ptr, global.size, diag);
    }

    fn materializeRegister(vm: *VM, value: RegisterValue, diag: Diagnostic) !Pointer {
        switch (value) {
            .ptr => |ptr| return ptr,
            .bytes => |bytes| {
                const ptr = try vm.allocBlock(@max(bytes.len, 1));
                if (bytes.len != 0) @memcpy(try vm.blockSlice(ptr, bytes.len, diag), bytes);
                return ptr;
            },
            .code => |code| {
                const ptr = try vm.allocBlock(@max(code.text.len, 1));
                if (code.text.len != 0) @memcpy(try vm.blockSlice(ptr, code.text.len, diag), code.text);
                return ptr;
            },
            .string => |text| {
                const ptr = try vm.allocBlock(@max(text.len, 1));
                if (text.len != 0) @memcpy(try vm.blockSlice(ptr, text.len, diag), text);
                return ptr;
            },
            .int => |int_value| {
                const ptr = try vm.allocBlock(8);
                std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), @bitCast(int_value), .little);
                return ptr;
            },
            .float => |float_value| {
                const ptr = try vm.allocBlock(8);
                std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), @bitCast(float_value), .little);
                return ptr;
            },
            .bool => |bool_value| {
                const ptr = try vm.allocBlock(1);
                try vm.storeByte(ptr, if (bool_value) 1 else 0, diag);
                return ptr;
            },
            .type_id => |type_id| {
                const ptr = try vm.allocBlock(8);
                std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), type_id, .little);
                return ptr;
            },
            .type_text => return diag.failAt(0, "VM cannot materialize Type values as raw bytes", .{}),
            .type_info_member => return diag.failAt(0, "VM cannot materialize Type_Info member values as raw bytes", .{}),
            .tuple => return diag.failAt(0, "VM cannot materialize undestructured multi-return values as raw bytes", .{}),
            .code_node, .code_nodes, .code_note, .code_notes, .code_arg, .code_args => return diag.failAt(0, "VM cannot materialize compiler Code_Node values as raw bytes", .{}),
            .message => return diag.failAt(0, "VM cannot materialize compiler Message values as raw bytes", .{}),
            .source_location => return diag.failAt(0, "VM cannot materialize Source_Code_Location as raw bytes; access its fields instead", .{}),
            .calendar => return diag.failAt(0, "VM cannot materialize Calendar as raw bytes; use field access or calendar_to_string instead", .{}),
            .build_options, .build_llvm_options => return diag.failAt(0, "VM cannot materialize Build_Options as raw bytes; access its fields instead", .{}),
            .empty => return diag.failAt(0, "VM cannot take address of an uninitialized register", .{}),
        }
    }

    fn materializeCString(vm: *VM, text: []const u8, diag: Diagnostic) !Pointer {
        const ptr = try vm.allocBlock(text.len + 1);
        if (text.len != 0) @memcpy(try vm.blockSlice(ptr, text.len, diag), text);
        (try vm.blockSlice(.{ .block = ptr.block, .offset = ptr.offset + text.len }, 1, diag))[0] = 0;
        return ptr;
    }

    fn blockSlice(vm: *VM, ptr: Pointer, len: usize, diag: Diagnostic) ![]u8 {
        if (ptr.block >= vm.memory_blocks.items.len) return diag.failAt(0, "VM pointer block out of range", .{});
        const block = vm.memory_blocks.items[ptr.block];
        if (ptr.offset > block.len or len > block.len - ptr.offset) return diag.failAt(0, "VM pointer access out of bounds: block={d} block_len={d} offset={d} len={d}", .{ ptr.block, block.len, ptr.offset, len });
        return block[ptr.offset .. ptr.offset + len];
    }

    fn blockArray8(vm: *VM, ptr: Pointer, diag: Diagnostic) !*[8]u8 {
        const slice = try vm.blockSlice(ptr, 8, diag);
        return slice[0..8];
    }

    fn readRemainingBytes(vm: *VM, ptr: Pointer, diag: Diagnostic) ![]const u8 {
        if (ptr.block >= vm.memory_blocks.items.len) return diag.failAt(0, "VM pointer block out of range", .{});
        const block = vm.memory_blocks.items[ptr.block];
        if (ptr.offset > block.len) return diag.failAt(0, "VM pointer access out of bounds", .{});
        return block[ptr.offset..];
    }

    fn stringFromPointer(vm: *VM, ptr: Pointer, len: usize, diag: Diagnostic) ![]const u8 {
        const bytes = try vm.blockSlice(ptr, len, diag);
        const owned = try vm.allocator.dupe(u8, bytes);
        errdefer vm.allocator.free(owned);
        try vm.rendered_code_strings.append(vm.allocator, owned);
        return owned;
    }

    fn stringFromCString(vm: *VM, ptr: Pointer, diag: Diagnostic) ![]const u8 {
        const bytes = try vm.readRemainingBytes(ptr, diag);
        const len = std.mem.indexOfScalar(u8, bytes, 0) orelse
            return diag.failAt(0, "VM to_string C string pointer does not reference a NUL-terminated buffer", .{});
        const owned = try vm.allocator.dupe(u8, bytes[0..len]);
        errdefer vm.allocator.free(owned);
        try vm.rendered_code_strings.append(vm.allocator, owned);
        return owned;
    }

    fn requireIo(vm: *VM, diag: Diagnostic, context: []const u8) !std.Io {
        return vm.io orelse diag.failAt(0, "VM {s} requires compiler IO context", .{context});
    }

    fn registerText(vm: *VM, value: RegisterValue, diag: Diagnostic, context: []const u8) ![]const u8 {
        return switch (value) {
            .string => |text| text,
            .bytes => |bytes| bytes,
            .code => |code| code.text,
            .ptr => |ptr| try vm.readRemainingBytes(ptr, diag),
            else => diag.failAt(0, "VM {s} requires a string value", .{context}),
        };
    }

    fn resolvedHostPath(vm: *VM, path: []const u8) ![]const u8 {
        if (std.fs.path.isAbsolute(path)) return try vm.allocator.dupe(u8, path);
        return try std.fs.path.join(vm.allocator, &.{ vm.base_dir, path });
    }

    fn ensureHostParentDir(vm: *VM, io: std.Io, path: []const u8) !void {
        _ = vm;
        if (std.fs.path.dirname(path)) |parent| {
            if (parent.len != 0) std.Io.Dir.cwd().createDirPath(io, parent) catch {};
        }
    }

    fn hostReadFile(vm: *VM, path: []const u8, diag: Diagnostic) ![]const u8 {
        const io = try vm.requireIo(diag, "compiler_read_file");
        const full = try vm.resolvedHostPath(path);
        defer vm.allocator.free(full);
        const contents = std.Io.Dir.cwd().readFileAlloc(io, full, vm.allocator, .limited(64 * 1024 * 1024)) catch |err| {
            return diag.failAt(0, "VM compiler_read_file failed for '{s}': {s}", .{ full, @errorName(err) });
        };
        errdefer vm.allocator.free(contents);
        try vm.rendered_code_strings.append(vm.allocator, contents);
        return contents;
    }

    const ReadEntireFileResult = struct {
        contents: []const u8,
        success: bool,
    };

    fn hostReadEntireFile(vm: *VM, path: []const u8, diag: Diagnostic) !ReadEntireFileResult {
        const io = try vm.requireIo(diag, "read_entire_file");
        const full = try vm.resolvedHostPath(path);
        defer vm.allocator.free(full);
        const contents = std.Io.Dir.cwd().readFileAlloc(io, full, vm.allocator, .limited(64 * 1024 * 1024)) catch {
            const empty = try vm.allocator.dupe(u8, "");
            errdefer vm.allocator.free(empty);
            try vm.rendered_code_strings.append(vm.allocator, empty);
            return .{ .contents = empty, .success = false };
        };
        errdefer vm.allocator.free(contents);
        try vm.rendered_code_strings.append(vm.allocator, contents);
        return .{ .contents = contents, .success = true };
    }

    fn hostWriteFile(vm: *VM, path: []const u8, contents: []const u8, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "compiler_write_file");
        const full = try vm.resolvedHostPath(path);
        defer vm.allocator.free(full);
        try vm.ensureHostParentDir(io, full);
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = full, .data = contents }) catch |err| {
            return diag.failAt(0, "VM compiler_write_file failed for '{s}': {s}", .{ full, @errorName(err) });
        };
        return true;
    }

    fn hostFileOpen(vm: *VM, path: []const u8, for_writing: bool, keep_existing_content: bool, diag: Diagnostic) !HostFileOpenResult {
        const io = try vm.requireIo(diag, "file_open");
        const full = try vm.resolvedHostPath(path);
        errdefer vm.allocator.free(full);

        var contents = std.ArrayList(u8).empty;
        errdefer contents.deinit(vm.allocator);

        if (!for_writing or keep_existing_content) {
            const loaded = std.Io.Dir.cwd().readFileAlloc(io, full, vm.allocator, .limited(256 * 1024 * 1024)) catch |err| switch (err) {
                error.FileNotFound => blk: {
                    if (!for_writing) {
                        vm.allocator.free(full);
                        return .{ .handle = 0, .ok = false };
                    }
                    break :blk &[_]u8{};
                },
                else => return diag.failAt(0, "VM file_open failed for '{s}': {s}", .{ full, @errorName(err) }),
            };
            defer if (loaded.len != 0) vm.allocator.free(loaded);
            try contents.appendSlice(vm.allocator, loaded);
        }

        try vm.open_files.append(vm.allocator, .{
            .path = full,
            .contents = contents,
            .cursor = 0,
            .writable = for_writing,
            .dirty = for_writing and !keep_existing_content,
        });
        return .{ .handle = @intCast(vm.open_files.items.len), .ok = true };
    }

    fn hostFile(vm: *VM, handle: i64, diag: Diagnostic) !*HostFile {
        if (handle <= 0) return diag.failAt(0, "VM file handle is null", .{});
        const index: usize = @intCast(handle - 1);
        if (index >= vm.open_files.items.len) return diag.failAt(0, "VM file handle {d} is out of range", .{handle});
        const file = &vm.open_files.items[index];
        if (!file.open) return diag.failAt(0, "VM file handle {d} is closed", .{handle});
        return file;
    }

    fn hostFileClose(vm: *VM, handle: i64, diag: Diagnostic) !void {
        const io = try vm.requireIo(diag, "file_close");
        const file = try vm.hostFile(handle, diag);
        if (file.dirty) {
            try vm.ensureHostParentDir(io, file.path);
            std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file.path, .data = file.contents.items }) catch |err| {
                return diag.failAt(0, "VM file_close failed to flush '{s}': {s}", .{ file.path, @errorName(err) });
            };
            file.dirty = false;
        }
        file.open = false;
    }

    fn hostFileSetPosition(vm: *VM, handle: i64, position: usize, diag: Diagnostic) !bool {
        const file = try vm.hostFile(handle, diag);
        file.cursor = position;
        return true;
    }

    fn hostFileWrite(vm: *VM, handle: i64, data: []const u8, diag: Diagnostic) !bool {
        const file = try vm.hostFile(handle, diag);
        if (!file.writable) return false;
        if (file.cursor > file.contents.items.len) {
            const old_len = file.contents.items.len;
            try file.contents.resize(vm.allocator, file.cursor);
            @memset(file.contents.items[old_len..], 0);
        }
        const end = file.cursor + data.len;
        if (end > file.contents.items.len) {
            const old_len = file.contents.items.len;
            try file.contents.resize(vm.allocator, end);
            @memset(file.contents.items[old_len..], 0);
        }
        if (data.len != 0) @memcpy(file.contents.items[file.cursor..end], data);
        file.cursor = end;
        file.dirty = true;
        return true;
    }

    fn hostFileRead(vm: *VM, handle: i64, dest: Pointer, len: usize, diag: Diagnostic) !bool {
        const file = try vm.hostFile(handle, diag);
        if (len > file.contents.items.len -| file.cursor) return false;
        const out = try vm.blockSlice(dest, len, diag);
        if (len != 0) @memcpy(out, file.contents.items[file.cursor .. file.cursor + len]);
        file.cursor += len;
        return true;
    }

    fn commandLineArgumentsArray(vm: *VM, diag: Diagnostic) !Pointer {
        const header = try vm.newDynamicArray(0, 16, diag);
        for (vm.command_line) |arg| _ = try vm.dynamicArrayAdd(header, .{ .string = arg }, 16, diag);
        return header;
    }

    fn hostMakeDirectory(vm: *VM, path: []const u8, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "make_directory_if_it_does_not_exist");
        const full = try vm.resolvedHostPath(path);
        defer vm.allocator.free(full);
        std.Io.Dir.cwd().createDirPath(io, full) catch |err| {
            return diag.failAt(0, "VM make_directory_if_it_does_not_exist failed for '{s}': {s}", .{ full, @errorName(err) });
        };
        return true;
    }

    fn hostDeleteDirectory(vm: *VM, path: []const u8, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "delete_directory");
        const full = try vm.resolvedHostPath(path);
        defer vm.allocator.free(full);
        if (!(try vm.hostPathExists(path, diag))) return true;
        std.Io.Dir.cwd().deleteTree(io, full) catch |err| return diag.failAt(0, "VM delete_directory failed for '{s}': {s}", .{ full, @errorName(err) });
        return true;
    }

    fn hostPathExists(vm: *VM, path: []const u8, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "file_exists");
        const full = try vm.resolvedHostPath(path);
        defer vm.allocator.free(full);
        std.Io.Dir.cwd().access(io, full, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return diag.failAt(0, "VM file_exists failed for '{s}': {s}", .{ full, @errorName(err) }),
        };
        return true;
    }

    fn hostSetWorkingDirectory(vm: *VM, path: []const u8, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "set_working_directory");
        const full = try vm.resolvedHostPath(path);
        defer vm.allocator.free(full);
        std.process.setCurrentPath(io, full) catch |err| return diag.failAt(0, "VM set_working_directory failed for '{s}': {s}", .{ full, @errorName(err) });
        return true;
    }

    fn hostGetWorkingDirectory(vm: *VM, diag: Diagnostic) ![]const u8 {
        const io = try vm.requireIo(diag, "get_working_directory");
        const cwd = std.process.currentPathAlloc(io, vm.allocator) catch |err| return diag.failAt(0, "VM get_working_directory failed: {s}", .{@errorName(err)});
        errdefer vm.allocator.free(cwd);
        try vm.rendered_code_strings.append(vm.allocator, cwd);
        return cwd;
    }

    fn hostGetExecutablePath(vm: *VM, diag: Diagnostic) ![]const u8 {
        const io = try vm.requireIo(diag, "get_path_of_running_executable");
        const sentinel_path = std.process.executablePathAlloc(io, vm.allocator) catch |err| return diag.failAt(0, "VM get_path_of_running_executable failed: {s}", .{@errorName(err)});
        defer vm.allocator.free(sentinel_path);
        const path = try vm.allocator.dupe(u8, sentinel_path);
        errdefer vm.allocator.free(path);
        try vm.rendered_code_strings.append(vm.allocator, path);
        return path;
    }

    fn hostRealtimeNs(vm: *VM, diag: Diagnostic) !i64 {
        var ts: std.posix.timespec = undefined;
        switch (std.posix.errno(std.posix.system.clock_gettime(.REALTIME, &ts))) {
            .SUCCESS => return @as(i64, @intCast(ts.sec)) * std.time.ns_per_s + @as(i64, @intCast(ts.nsec)),
            .INTR => return vm.hostRealtimeNs(diag),
            else => return diag.failAt(0, "VM realtime clock failed", .{}),
        }
    }

    fn hostMonotonicNs(vm: *VM, diag: Diagnostic) !i64 {
        var ts: std.posix.timespec = undefined;
        switch (std.posix.errno(std.posix.system.clock_gettime(.MONOTONIC, &ts))) {
            .SUCCESS => return @as(i64, @intCast(ts.sec)) * std.time.ns_per_s + @as(i64, @intCast(ts.nsec)),
            .INTR => return vm.hostMonotonicNs(diag),
            else => return diag.failAt(0, "VM monotonic clock failed", .{}),
        }
    }

    fn nextRandom(vm: *VM) u64 {
        var z = vm.random_state +% 0x9e3779b97f4a7c15;
        vm.random_state = z;
        z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
        return z ^ (z >> 31);
    }

    fn nextRandomZeroToOne(vm: *VM) f64 {
        const bits = vm.nextRandom() >> 11;
        return @as(f64, @floatFromInt(bits)) * (1.0 / 9007199254740992.0);
    }

    fn hostToCalendar(vm: *VM, low_ns: u64, timezone: u32, diag: Diagnostic) !CalendarValue {
        _ = vm;
        const sec_u64 = low_ns / std.time.ns_per_s;
        const nsec = low_ns % std.time.ns_per_s;
        const seconds: time_c.time_t = @intCast(sec_u64);
        var tm_value: time_c.struct_tm = undefined;
        const tm_ptr = if (timezone == 1) time_c.localtime_r(&seconds, &tm_value) else time_c.gmtime_r(&seconds, &tm_value);
        if (tm_ptr == null) return diag.failAt(0, "VM calendar conversion failed", .{});
        return .{
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
    }

    fn calendarToString(vm: *VM, calendar: CalendarValue) ![]const u8 {
        const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
        const month_idx: usize = if (calendar.month_starting_at_0 >= 0 and calendar.month_starting_at_0 < 12) @intCast(calendar.month_starting_at_0) else 0;
        const text = try std.fmt.allocPrint(vm.allocator, "{d} {s} {d}, {d:0>2}:{d:0>2}:{d:0>2}", .{
            calendar.day_of_month_starting_at_0 + 1,
            months[month_idx],
            calendar.year,
            @as(u64, @intCast(calendar.hour)),
            @as(u64, @intCast(calendar.minute)),
            @as(u64, @intCast(calendar.second)),
        });
        errdefer vm.allocator.free(text);
        try vm.rendered_code_strings.append(vm.allocator, text);
        return text;
    }

    fn pathStripFilename(vm: *VM, path: []const u8) ![]const u8 {
        var i = path.len;
        while (i > 0) {
            i -= 1;
            if (path[i] == '/' or path[i] == '\\') {
                const result = try vm.allocator.dupe(u8, path[0 .. i + 1]);
                errdefer vm.allocator.free(result);
                try vm.rendered_code_strings.append(vm.allocator, result);
                return result;
            }
        }
        const result = try vm.allocator.dupe(u8, "");
        errdefer vm.allocator.free(result);
        try vm.rendered_code_strings.append(vm.allocator, result);
        return result;
    }

    fn hostCopyFile(vm: *VM, src: []const u8, dest: []const u8, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "copy_file");
        const full_src = try vm.resolvedHostPath(src);
        defer vm.allocator.free(full_src);
        const full_dest = try vm.resolvedHostPath(dest);
        defer vm.allocator.free(full_dest);
        const contents = std.Io.Dir.cwd().readFileAlloc(io, full_src, vm.allocator, .limited(256 * 1024 * 1024)) catch |err| {
            return diag.failAt(0, "VM copy_file failed reading '{s}': {s}", .{ full_src, @errorName(err) });
        };
        defer vm.allocator.free(contents);
        try vm.ensureHostParentDir(io, full_dest);
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = full_dest, .data = contents }) catch |err| {
            return diag.failAt(0, "VM copy_file failed writing '{s}': {s}", .{ full_dest, @errorName(err) });
        };
        return true;
    }

    fn hostRunCommand(vm: *VM, command: []const u8, diag: Diagnostic) !i64 {
        const result = try vm.hostRunCommandCapture(command, diag);
        return result.exit_code;
    }

    fn hostRunCommandCapture(vm: *VM, command: []const u8, diag: Diagnostic) !RunCommandResult {
        const io = try vm.requireIo(diag, "run_command");
        const result = std.process.run(vm.allocator, io, .{
            .argv = &.{ "/bin/sh", "-c", command },
            .stderr_limit = .limited(64 * 1024),
            .stdout_limit = .limited(64 * 1024),
        }) catch |err| {
            return diag.failAt(0, "VM run_command failed for '{s}': {s}", .{ command, @errorName(err) });
        };
        defer vm.allocator.free(result.stdout);
        defer vm.allocator.free(result.stderr);
        const stdout = try vm.allocator.dupe(u8, result.stdout);
        errdefer vm.allocator.free(stdout);
        const stderr = try vm.allocator.dupe(u8, result.stderr);
        errdefer vm.allocator.free(stderr);
        try vm.rendered_code_strings.append(vm.allocator, stdout);
        try vm.rendered_code_strings.append(vm.allocator, stderr);
        const exit_code: i64 = switch (result.term) {
            .exited => |code| code,
            else => 1,
        };
        return .{ .exit_code = exit_code, .stdout = stdout, .stderr = stderr };
    }

    fn hostBuildCppDynamicLib(vm: *VM, name: []const u8, source: []const u8, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "build_cpp_dynamic_lib");
        const source_path = try vm.resolvedHostPath(source);
        defer vm.allocator.free(source_path);
        const output_name = switch (@import("builtin").os.tag) {
            .macos => try std.fmt.allocPrint(vm.allocator, "{s}", .{name}),
            .linux => try std.fmt.allocPrint(vm.allocator, "lib{s}.so", .{name}),
            .windows => try std.fmt.allocPrint(vm.allocator, "{s}.dll", .{name}),
            else => try std.fmt.allocPrint(vm.allocator, "{s}.dynlib", .{name}),
        };
        defer vm.allocator.free(output_name);
        const output_path = try vm.resolvedHostPath(output_name);
        defer vm.allocator.free(output_path);
        const argv = switch (@import("builtin").os.tag) {
            .macos => &[_][]const u8{ "clang++", "-dynamiclib", "-std=c++17", "-o", output_path, source_path },
            .linux => &[_][]const u8{ "clang++", "-shared", "-fPIC", "-std=c++17", "-o", output_path, source_path },
            else => return diag.failAt(0, "VM build_cpp_dynamic_lib does not support host OS {s} yet", .{@tagName(@import("builtin").os.tag)}),
        };
        const result = std.process.run(vm.allocator, io, .{
            .argv = argv,
            .stderr_limit = .limited(256 * 1024),
            .stdout_limit = .limited(256 * 1024),
        }) catch |err| {
            return diag.failAt(0, "VM build_cpp_dynamic_lib failed invoking clang++: {s}", .{@errorName(err)});
        };
        defer vm.allocator.free(result.stdout);
        defer vm.allocator.free(result.stderr);
        return switch (result.term) {
            .exited => |code| code == 0,
            else => false,
        };
    }

    fn hostGenerateBindings(vm: *VM, output: []const u8, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "generate_bindings");
        const full = try vm.resolvedHostPath(output);
        defer vm.allocator.free(full);
        std.Io.Dir.cwd().access(io, full, .{}) catch |err| switch (err) {
            error.FileNotFound => return diag.failAt(0, "VM generate_bindings requires a real bindings generator; no existing generated output found at '{s}'", .{full}),
            else => return diag.failAt(0, "VM generate_bindings failed checking '{s}': {s}", .{ full, @errorName(err) }),
        };
        return true;
    }

    fn hostAddBuildString(vm: *VM, source: []const u8, workspace: i64, diag: Diagnostic) !bool {
        if (workspace == vm.intercepted_workspace) {
            try vm.addWorkspaceSource(workspace, "<add_build_string>", source);
            try vm.rebuildInterceptMessages(workspace, diag);
            return true;
        }
        if (workspace != -1 and workspace != 1 and workspace != vm.current_workspace_id) {
            try vm.addWorkspaceSource(workspace, "<add_build_string>", source);
            return true;
        }
        const sink = vm.current_workspace_build_strings orelse return diag.failAt(0, "add_build_string requires an active compiler workspace", .{});
        const owned = try vm.allocator.dupe(u8, source);
        errdefer vm.allocator.free(owned);
        try sink.append(vm.allocator, owned);
        return true;
    }

    fn hostAddBuildFile(vm: *VM, path: []const u8, workspace: i64, diag: Diagnostic) !bool {
        const io = try vm.requireIo(diag, "add_build_file");
        const full = try vm.resolvedHostPath(path);
        defer vm.allocator.free(full);
        const source = std.Io.Dir.cwd().readFileAlloc(io, full, vm.allocator, .limited(64 * 1024 * 1024)) catch |err| {
            return diag.failAt(0, "VM add_build_file failed reading '{s}': {s}", .{ full, @errorName(err) });
        };
        defer vm.allocator.free(source);
        try vm.addWorkspaceSource(workspace, path, source);
        if (workspace == vm.intercepted_workspace) try vm.rebuildInterceptMessages(workspace, diag);
        return true;
    }

    fn addWorkspaceSource(vm: *VM, workspace: i64, path: []const u8, source: []const u8) !void {
        const owned_path = try vm.allocator.dupe(u8, path);
        errdefer vm.allocator.free(owned_path);
        const owned_source = try vm.allocator.dupe(u8, source);
        errdefer vm.allocator.free(owned_source);
        try vm.workspace_sources.append(vm.allocator, .{
            .workspace = workspace,
            .path = owned_path,
            .source = owned_source,
        });
    }

    fn hostCompilerCreateWorkspace(vm: *VM, diag: Diagnostic) !i64 {
        const next = vm.next_workspace_id orelse return diag.failAt(0, "compiler_create_workspace requires an active compiler workspace manager", .{});
        const id = next.*;
        next.* += 1;
        return id;
    }

    fn hostGetCurrentWorkspace(vm: *VM) i64 {
        if (vm.next_workspace_id == null) return 0;
        return vm.current_workspace_id;
    }

    fn workspaceStatusCode(vm: *VM, value: RegisterValue, diag: Diagnostic) !i64 {
        _ = vm;
        switch (value) {
            .int => |status| {
                if (status == 0 or status == 1) return status;
                return diag.failAt(0, "VM unsupported workspace status value {d}", .{status});
            },
            .string, .bytes => |name| {
                if (std.mem.eql(u8, name, "SUCCEEDED") or std.mem.eql(u8, name, "SUCCESS") or std.mem.eql(u8, name, "OK")) return 0;
                if (std.mem.eql(u8, name, "FAILED")) return 1;
                return diag.failAt(0, "VM unsupported workspace status value '{s}'", .{name});
            },
            else => return diag.failAt(0, "VM compiler_set_workspace_status requires a workspace status value", .{}),
        }
    }

    fn setWorkspaceStatus(vm: *VM, status: i64, diag: Diagnostic) !void {
        const workspace = if (vm.intercepted_workspace != 0) vm.intercepted_workspace else vm.hostGetCurrentWorkspace();
        if (workspace <= 0) return diag.failAt(0, "compiler_set_workspace_status requires an active compiler workspace", .{});
        try vm.workspace_status.put(vm.allocator, workspace, status);
        if (workspace == vm.intercepted_workspace) try vm.rebuildInterceptMessages(workspace, diag);
    }

    fn workspaceErrorCode(vm: *VM, workspace: i64) i64 {
        return vm.workspace_status.get(workspace) orelse 0;
    }

    fn workspaceBuildOptions(vm: *VM, workspace: i64) ?BuildOptions {
        const index = vm.workspace_build_options.get(workspace) orelse return null;
        if (index >= vm.build_options.items.len) return null;
        return vm.build_options.items[index];
    }

    fn workspaceExecutableName(vm: *VM, workspace: i64) []const u8 {
        const options = vm.workspaceBuildOptions(workspace) orelse return "program";
        if (options.output_executable_name.len == 0) return "program";
        return options.output_executable_name;
    }

    fn workspaceUsesCustomLinkCommand(vm: *VM, workspace: i64) bool {
        const options = vm.workspaceBuildOptions(workspace) orelse return false;
        return options.use_custom_link_command;
    }

    fn appendCompilerMessage(vm: *VM, message: CompilerMessage) !void {
        const index = vm.compiler_messages.items.len;
        try vm.compiler_messages.append(vm.allocator, message);
        try vm.compiler_message_queue.append(vm.allocator, index);
    }

    fn hostCompilerBeginIntercept(vm: *VM, workspace: i64, diag: Diagnostic) !void {
        vm.intercepted_workspace = workspace;
        try vm.rebuildInterceptMessages(workspace, diag);
    }

    fn rebuildInterceptMessages(vm: *VM, workspace: i64, diag: Diagnostic) !void {
        vm.compiler_message_queue.clearRetainingCapacity();
        vm.compiler_message_nodes.clearRetainingCapacity();
        vm.compiler_message_declarations.clearRetainingCapacity();
        vm.compiler_message_notes.clearRetainingCapacity();
        vm.compiler_messages.clearRetainingCapacity();
        const typechecked_start = vm.compiler_message_nodes.items.len;
        const declaration_start = vm.compiler_message_declarations.items.len;
        var found_source = false;
        var declaration_count: usize = 0;
        var first_error: ?[]const u8 = null;
        var seen_imports = std.StringHashMapUnmanaged(void).empty;
        defer seen_imports.deinit(vm.allocator);
        for (vm.workspace_sources.items) |source| {
            if (source.workspace != workspace) continue;
            found_source = true;
            try vm.appendCompilerMessage(.{ .kind = "FILE", .workspace = workspace, .fully_pathed_filename = source.path });
            vm.appendWorkspaceImportMessages(workspace, source.path, source.source, &seen_imports, diag) catch |err| {
                if (first_error == null) first_error = @errorName(err);
                try vm.workspace_status.put(vm.allocator, workspace, 1);
            };
            declaration_count += vm.appendWorkspaceDeclarations(source.path, source.source, diag) catch |err| blk: {
                if (first_error == null) first_error = @errorName(err);
                try vm.workspace_status.put(vm.allocator, workspace, 1);
                break :blk 0;
            };
        }
        if (!found_source) {
            const node: CodeNode = .{ .kind = "DECLARATION", .flags = "ALLOWED_BY_CONTEXT", .text = "main", .name = "main", .start = 0, .end = 4 };
            try vm.compiler_message_nodes.append(vm.allocator, node);
            try vm.compiler_message_declarations.append(vm.allocator, node);
            declaration_count = 1;
        }
        const typechecked_count = vm.compiler_message_nodes.items.len - typechecked_start;
        if (!found_source) {
            try vm.appendCompilerMessage(.{ .kind = "IMPORT", .workspace = workspace, .module_name = "main", .module_type = "MAIN_PROGRAM", .fully_pathed_filename = "<implicit>" });
            try vm.appendCompilerMessage(.{ .kind = "FILE", .workspace = workspace, .fully_pathed_filename = "<implicit>" });
        }
        if (first_error) |error_name| {
            try vm.appendCompilerMessage(.{ .kind = "ERROR", .workspace = workspace, .dump_text = error_name, .error_code = 1 });
            try vm.appendCompilerMessage(.{ .kind = "COMPLETE", .workspace = workspace, .executable_name = vm.workspaceExecutableName(workspace), .linker_exit_code = 1, .error_code = 1 });
            return;
        }
        try vm.appendCompilerMessage(.{ .kind = "PHASE", .workspace = workspace, .phase = "ALL_SOURCE_CODE_PARSED" });
        try vm.appendCompilerMessage(.{ .kind = "PHASE", .workspace = workspace, .phase = "TYPECHECKED_ALL_WE_CAN" });
        try vm.appendCompilerMessage(.{ .kind = "TYPECHECKED", .workspace = workspace, .all_start = typechecked_start, .all_count = typechecked_count, .declaration_start = declaration_start, .declaration_count = declaration_count });
        try vm.appendCompilerMessage(.{ .kind = "PHASE", .workspace = workspace, .phase = "ALL_TARGET_CODE_BUILT" });
        try vm.appendCompilerMessage(.{ .kind = "PHASE", .workspace = workspace, .phase = "PRE_WRITE_EXECUTABLE", .executable_name = vm.workspaceExecutableName(workspace), .linker_exit_code = vm.workspaceErrorCode(workspace) });
        if (vm.workspaceUsesCustomLinkCommand(workspace)) {
            try vm.appendCompilerMessage(.{ .kind = "PHASE", .workspace = workspace, .phase = "READY_FOR_CUSTOM_LINK_COMMAND", .executable_name = vm.workspaceExecutableName(workspace), .linker_exit_code = vm.workspaceErrorCode(workspace) });
        } else {
            try vm.appendWorkspaceCompletionMessages(workspace);
        }
    }

    fn appendWorkspaceCompletionMessages(vm: *VM, workspace: i64) !void {
        const error_code = vm.workspaceErrorCode(workspace);
        const executable_name = vm.workspaceExecutableName(workspace);
        try vm.appendCompilerMessage(.{ .kind = "PHASE", .workspace = workspace, .phase = "POST_WRITE_EXECUTABLE", .executable_name = executable_name, .executable_write_failed = error_code != 0, .linker_exit_code = error_code });
        try vm.appendCompilerMessage(.{ .kind = "COMPLETE", .workspace = workspace, .executable_name = executable_name, .linker_exit_code = error_code, .error_code = error_code });
    }

    fn hostCustomLinkCommandComplete(vm: *VM, diag: Diagnostic) !void {
        const workspace = vm.intercepted_workspace;
        if (workspace <= 0) return diag.failAt(0, "compiler_custom_link_command_is_complete requires an intercepted workspace", .{});
        try vm.appendWorkspaceCompletionMessages(workspace);
    }

    fn appendWorkspaceDeclarations(vm: *VM, path: []const u8, source: []const u8, parent_diag: Diagnostic) !usize {
        const diag = Diagnostic.init(vm.allocator, path, source);
        var tokens = try lexer.tokenize(vm.allocator, source, diag);
        defer tokens.deinit(vm.allocator);
        var ast = try parser.parse(
            vm.allocator,
            source,
            tokens.items(.tag),
            tokens.items(.start),
            tokens.items(.end),
            diag,
        );
        defer ast.deinit();
        defer vm.allocator.free(ast.tokens);
        if (ast.root == @import("Ast.zig").null_node) return 0;
        const decls = ast.extraSlice(ast.data(ast.root).lhs);
        const ProcDeclInfo = struct {
            decl: @import("Ast.zig").NodeIndex,
            node_index: usize,
        };
        var proc_decl_nodes = std.ArrayList(ProcDeclInfo).empty;
        defer proc_decl_nodes.deinit(vm.allocator);
        const declaration_start = vm.compiler_message_declarations.items.len;
        for (decls) |decl_idx| {
            const decl: @import("Ast.zig").NodeIndex = @intCast(decl_idx);
            if (decl >= ast.node_tags.items.len or ast.tag(decl) != .proc_decl) continue;
            const note_start = vm.compiler_message_notes.items.len;
            for (ast.noteTokens(decl)) |note_tok| {
                const text = ast.tokenSlice(@intCast(note_tok));
                try vm.compiler_message_notes.append(vm.allocator, .{ .text = text });
            }
            const name_token = ast.mainToken(decl);
            const name = ast.tokenSlice(name_token);
            const token_start = ast.tokens[name_token].start;
            const node_index = vm.compiler_message_nodes.items.len;
            try vm.compiler_message_nodes.append(vm.allocator, .{
                .kind = "DECLARATION",
                .flags = "ALLOWED_BY_CONTEXT",
                .text = name,
                .name = name,
                .path = path,
                .line_number = lineNumberAt(source, token_start),
                .type_text = "Procedure",
                .start = token_start,
                .end = ast.tokens[name_token].end,
                .note_start = note_start,
                .note_count = vm.compiler_message_notes.items.len - note_start,
                .expression_index = @intCast(node_index),
            });
            try proc_decl_nodes.append(vm.allocator, .{ .decl = decl, .node_index = node_index });
        }
        for (proc_decl_nodes.items) |proc_decl| {
            const decl = proc_decl.decl;
            const proc_node_index = proc_decl.node_index;
            const name_token = ast.mainToken(decl);
            const name = ast.tokenSlice(name_token);
            const token_start = ast.tokens[name_token].start;
            const sub_start = vm.compiler_message_nodes.items.len;
            try vm.appendWorkspaceLocalDeclarations(name, path, source, token_start);
            vm.compiler_message_nodes.items[proc_node_index].subexpression_start = sub_start;
            vm.compiler_message_nodes.items[proc_node_index].subexpression_count = vm.compiler_message_nodes.items.len - sub_start;
            try vm.compiler_message_declarations.append(vm.allocator, vm.compiler_message_nodes.items[proc_node_index]);
        }
        _ = parent_diag;
        return vm.compiler_message_declarations.items.len - declaration_start;
    }

    fn appendWorkspaceImportMessages(vm: *VM, workspace: i64, path: []const u8, source: []const u8, seen_imports: *std.StringHashMapUnmanaged(void), parent_diag: Diagnostic) !void {
        const diag = Diagnostic.init(vm.allocator, path, source);
        var tokens = try lexer.tokenize(vm.allocator, source, diag);
        defer tokens.deinit(vm.allocator);
        var ast = try parser.parse(
            vm.allocator,
            source,
            tokens.items(.tag),
            tokens.items(.start),
            tokens.items(.end),
            diag,
        );
        defer ast.deinit();
        defer vm.allocator.free(ast.tokens);
        if (ast.root == @import("Ast.zig").null_node) return;
        const decls = ast.extraSlice(ast.data(ast.root).lhs);
        for (decls) |decl_idx| {
            try vm.appendWorkspaceImportMessagesFromNode(workspace, path, &ast, @intCast(decl_idx), seen_imports);
        }
        _ = parent_diag;
    }

    fn appendWorkspaceImportMessagesFromNode(vm: *VM, workspace: i64, path: []const u8, ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex, seen_imports: *std.StringHashMapUnmanaged(void)) !void {
        if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return;
        switch (ast.tag(node)) {
            .import_decl => {
                const module_name = ast.stringTokenContents(@intCast(ast.data(node).lhs));
                if (seen_imports.contains(module_name)) return;
                try seen_imports.put(vm.allocator, module_name, {});
                try vm.appendCompilerMessage(.{
                    .kind = "IMPORT",
                    .workspace = workspace,
                    .module_name = module_name,
                    .module_type = "MODULE",
                    .fully_pathed_filename = path,
                });
            },
            .const_decl => {
                if (ast.data(node).lhs != @import("Ast.zig").null_node) try vm.appendWorkspaceImportMessagesFromNode(workspace, path, ast, ast.data(node).lhs, seen_imports);
            },
            .proc_decl => {
                if (ast.data(node).lhs != @import("Ast.zig").null_node) try vm.appendWorkspaceImportMessagesFromNode(workspace, path, ast, ast.data(node).lhs, seen_imports);
            },
            .block, .stmt_list => {
                for (ast.extraSlice(ast.data(node).lhs)) |child| try vm.appendWorkspaceImportMessagesFromNode(workspace, path, ast, @intCast(child), seen_imports);
            },
            else => {},
        }
    }

    fn appendWorkspaceLocalDeclarations(vm: *VM, proc_name: []const u8, path: []const u8, source: []const u8, proc_start: usize) !void {
        var local_types = std.StringHashMapUnmanaged([]const u8).empty;
        defer local_types.deinit(vm.allocator);
        const body = procBodyRange(source, proc_start) orelse return;
        var offset = body.start;
        while (offset < body.end) {
            const line_end = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse body.end;
            const raw_line = source[offset..@min(line_end, body.end)];
            const comment_pos = std.mem.indexOf(u8, raw_line, "//") orelse raw_line.len;
            const code = std.mem.trim(u8, raw_line[0..comment_pos], " \t\r\n");
            if (try vm.parseWorkspaceLocalDeclaration(code, local_types)) |decl| {
                const name_offset_in_line = std.mem.indexOf(u8, raw_line, decl.name) orelse 0;
                const absolute_name_offset = offset + name_offset_in_line;
                try local_types.put(vm.allocator, decl.name, decl.type_text);
                try vm.compiler_message_nodes.append(vm.allocator, .{
                    .kind = "DECLARATION",
                    .flags = "ALLOWED_BY_CONTEXT",
                    .text = decl.name,
                    .name = decl.name,
                    .path = path,
                    .line_number = lineNumberAt(source, absolute_name_offset),
                    .type_text = decl.type_text,
                    .start = absolute_name_offset,
                    .end = absolute_name_offset + decl.name.len,
                });
            }
            offset = @min(line_end + 1, body.end);
        }
        _ = proc_name;
    }

    const ParsedLocalDecl = struct {
        name: []const u8,
        type_text: []const u8,
    };

    fn parseWorkspaceLocalDeclaration(vm: *VM, line: []const u8, local_types: std.StringHashMapUnmanaged([]const u8)) !?ParsedLocalDecl {
        if (line.len == 0 or std.mem.indexOf(u8, line, "::") != null) return null;
        const first = line[0];
        if (!isIdentStart(first)) return null;
        var name_end: usize = 1;
        while (name_end < line.len and isIdentContinue(line[name_end])) name_end += 1;
        const name = line[0..name_end];
        var i = name_end;
        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
        if (i >= line.len or line[i] != ':') return null;
        i += 1;
        if (i < line.len and line[i] == '=') {
            i += 1;
            const rhs = std.mem.trim(u8, line[i..], " \t;");
            if (rhs.len >= 2 and rhs[0] == '*' and isIdentStart(rhs[1])) {
                var operand_end: usize = 2;
                while (operand_end < rhs.len and isIdentContinue(rhs[operand_end])) operand_end += 1;
                const operand_name = rhs[1..operand_end];
                const operand_type = local_types.get(operand_name) orelse "int";
                const owned = try std.fmt.allocPrint(vm.allocator, "*{s}", .{std.mem.trim(u8, operand_type, " \t\r\n")});
                try vm.rendered_code_strings.append(vm.allocator, owned);
                return .{ .name = name, .type_text = owned };
            }
            return .{ .name = name, .type_text = "int" };
        }
        const type_start = i;
        while (i < line.len and line[i] != '=' and line[i] != ';') i += 1;
        const type_text = std.mem.trim(u8, line[type_start..i], " \t\r\n");
        if (type_text.len == 0) return null;
        return .{ .name = name, .type_text = type_text };
    }

    fn procBodyRange(source: []const u8, proc_start: usize) ?struct { start: usize, end: usize } {
        const open_rel = std.mem.indexOfScalarPos(u8, source, proc_start, '{') orelse return null;
        var depth: usize = 0;
        var i = open_rel;
        while (i < source.len) : (i += 1) {
            switch (source[i]) {
                '{' => depth += 1,
                '}' => {
                    if (depth == 0) return null;
                    depth -= 1;
                    if (depth == 0) return .{ .start = open_rel + 1, .end = i };
                },
                '"' => {
                    i += 1;
                    while (i < source.len) : (i += 1) {
                        if (source[i] == '\\' and i + 1 < source.len) {
                            i += 1;
                            continue;
                        }
                        if (source[i] == '"') break;
                    }
                },
                else => {},
            }
        }
        return null;
    }

    fn isIdentStart(c: u8) bool {
        return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_';
    }

    fn isIdentContinue(c: u8) bool {
        return isIdentStart(c) or (c >= '0' and c <= '9');
    }

    fn lineNumberAt(source: []const u8, offset: usize) i64 {
        var line: i64 = 1;
        for (source[0..@min(offset, source.len)]) |c| {
            if (c == '\n') line += 1;
        }
        return line;
    }

    fn lineForCodeOffset(source: []const u8, base_line: i64, offset: usize) i64 {
        return base_line + lineNumberAt(source, offset) - 1;
    }

    fn astNodeSource(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex) []const u8 {
        if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return "";
        var start = ast.tokens[ast.mainToken(node)].start;
        var end = ast.tokens[ast.mainToken(node)].end;
        collectAstNodeStart(ast, node, &start);
        collectAstNodeEnd(ast, node, &end);
        return std.mem.trim(u8, ast.source[start..@min(end, ast.source.len)], " \t\r\n;");
    }

    fn collectAstNodeStart(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex, start: *u32) void {
        if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return;
        start.* = @min(start.*, ast.tokens[ast.mainToken(node)].start);
        const data = ast.data(node);
        switch (ast.tag(node)) {
            .pointer_type, .unary_expr, .expr_stmt, .return_stmt => collectAstNodeStart(ast, data.lhs, start),
            else => {},
        }
    }

    fn collectAstNodeEnd(ast: *const @import("Ast.zig").Ast, node: @import("Ast.zig").NodeIndex, end: *u32) void {
        if (node == @import("Ast.zig").null_node or node >= ast.node_tags.items.len) return;
        end.* = @max(end.*, ast.tokens[ast.mainToken(node)].end);
        const data = ast.data(node);
        switch (ast.tag(node)) {
            .pointer_type, .unary_expr, .expr_stmt, .return_stmt => collectAstNodeEnd(ast, data.lhs, end),
            else => {},
        }
    }

    fn hostCompilerWaitForMessage(vm: *VM) ?usize {
        if (vm.compiler_message_queue.items.len == 0) return null;
        return vm.compiler_message_queue.orderedRemove(0);
    }

    fn compilerMessageGetField(vm: *VM, index: usize, field_name: []const u8, diag: Diagnostic) !RegisterValue {
        if (index >= vm.compiler_messages.items.len) return diag.failAt(0, "VM Message handle out of range", .{});
        const message = vm.compiler_messages.items[index];
        if (std.mem.eql(u8, field_name, "kind")) return .{ .string = message.kind };
        if (std.mem.eql(u8, field_name, "workspace")) return .{ .int = message.workspace };
        if (std.mem.eql(u8, field_name, "phase")) return .{ .string = message.phase };
        if (std.mem.eql(u8, field_name, "fully_pathed_filename")) return .{ .string = message.fully_pathed_filename };
        if (std.mem.eql(u8, field_name, "module_name")) return .{ .string = message.module_name };
        if (std.mem.eql(u8, field_name, "module_type")) return .{ .string = message.module_type };
        if (std.mem.eql(u8, field_name, "executable_name")) return .{ .string = message.executable_name };
        if (std.mem.eql(u8, field_name, "executable_write_failed")) return .{ .bool = message.executable_write_failed };
        if (std.mem.eql(u8, field_name, "linker_exit_code")) return .{ .int = message.linker_exit_code };
        if (std.mem.eql(u8, field_name, "error_code")) return .{ .int = message.error_code };
        if (std.mem.eql(u8, field_name, "all")) {
            if (message.all_start > vm.compiler_message_nodes.items.len or message.all_count > vm.compiler_message_nodes.items.len - message.all_start) return diag.failAt(0, "VM Message_Typechecked node slice out of range", .{});
            return .{ .code_nodes = vm.compiler_message_nodes.items[message.all_start .. message.all_start + message.all_count] };
        }
        if (std.mem.eql(u8, field_name, "declarations")) {
            if (message.declaration_start > vm.compiler_message_declarations.items.len or message.declaration_count > vm.compiler_message_declarations.items.len - message.declaration_start) return diag.failAt(0, "VM Message_Typechecked declarations slice out of range", .{});
            return .{ .code_nodes = vm.compiler_message_declarations.items[message.declaration_start .. message.declaration_start + message.declaration_count] };
        }
        if (std.mem.eql(u8, field_name, "dump_text")) return .{ .string = message.dump_text };
        return diag.failAt(0, "VM Message has no implemented field '{s}'", .{field_name});
    }

    fn buildOptionsForWorkspace(vm: *VM, workspace: i64, diag: Diagnostic) !usize {
        if (workspace <= 0) return diag.failAt(0, "VM workspace handle must be positive, got {d}", .{workspace});
        if (vm.workspace_build_options.get(workspace)) |index| return index;
        const index = vm.build_options.items.len;
        try vm.build_options.append(vm.allocator, .{});
        try vm.workspace_build_options.put(vm.allocator, workspace, index);
        return index;
    }

    fn setBuildOptionsForWorkspace(vm: *VM, workspace: i64, source_index: usize, diag: Diagnostic) !void {
        if (workspace <= 0) return diag.failAt(0, "VM workspace handle must be positive, got {d}", .{workspace});
        if (source_index >= vm.build_options.items.len) return diag.failAt(0, "VM set_build_options source handle out of range", .{});
        const cloned_index = try vm.cloneBuildOptions(source_index, diag);
        try vm.workspace_build_options.put(vm.allocator, workspace, cloned_index);
    }

    fn cloneBuildOptions(vm: *VM, source_index: usize, diag: Diagnostic) !usize {
        if (source_index >= vm.build_options.items.len) return diag.failAt(0, "VM Build_Options source handle out of range", .{});
        var cloned = vm.build_options.items[source_index];
        if (cloned.import_path) |array_index| cloned.import_path = try vm.cloneDynamicArray(array_index, diag);
        if (cloned.compile_time_command_line) |array_index| cloned.compile_time_command_line = try vm.cloneDynamicArray(array_index, diag);
        const index = vm.build_options.items.len;
        try vm.build_options.append(vm.allocator, cloned);
        return index;
    }

    fn cloneDynamicArray(vm: *VM, source_index: usize, diag: Diagnostic) !usize {
        if (source_index >= vm.dynamic_arrays.items.len) return diag.failAt(0, "VM dynamic array handle out of range while cloning Build_Options", .{});
        const source = vm.dynamic_arrays.items[source_index];
        const header = try vm.newDynamicArray(0, source.elem_size, diag);
        const cloned_index = vm.dynamicArrayIndexForPointer(header) orelse return diag.failAt(0, "VM dynamic array clone allocation failed", .{});
        for (source.elems.items) |item| _ = try vm.dynamicArrayAdd(header, item, source.elem_size, diag);
        return cloned_index;
    }

    fn buildOptionsSnapshot(vm: *VM, allocator: std.mem.Allocator, index: usize) !BuildOptionsSnapshot {
        if (index >= vm.build_options.items.len) return error.InvalidBuildOptionsHandle;
        const options = vm.build_options.items[index];
        return .{
            .output_executable_name = try allocator.dupe(u8, options.output_executable_name),
            .output_path = try allocator.dupe(u8, options.output_path),
            .output_type = try allocator.dupe(u8, options.output_type),
            .backend = try allocator.dupe(u8, options.backend),
            .llvm_output_bitcode = options.llvm_output_bitcode,
        };
    }

    fn optimizationMode(vm: *VM, value: RegisterValue, diag: Diagnostic) !i64 {
        _ = vm;
        return switch (value) {
            .int => |mode| mode,
            .string => |name| optimizationModeByName(name) orelse diag.failAt(0, "VM unsupported Optimization_Type value '{s}'", .{name}),
            .bytes => |name| optimizationModeByName(name) orelse diag.failAt(0, "VM unsupported Optimization_Type value '{s}'", .{name}),
            else => diag.failAt(0, "VM set_optimization requires an Optimization_Type value", .{}),
        };
    }

    fn applyOptimization(vm: *VM, index: usize, mode: i64, keep_runtime_checks: bool, diag: Diagnostic) !void {
        if (index >= vm.build_options.items.len) return diag.failAt(0, "VM set_optimization Build_Options handle out of range", .{});
        const options = &vm.build_options.items[index];
        switch (mode) {
            0, 1 => {
                options.stack_trace = true;
                options.backtrace_on_crash = "ON";
                options.array_bounds_check = "ON";
                options.cast_bounds_check = "NONFATAL";
                options.null_pointer_check = "ON";
                options.enable_bytecode_inliner = false;
            },
            2, 3, 4, 5 => {
                options.stack_trace = false;
                options.backtrace_on_crash = "OFF";
                if (!keep_runtime_checks) {
                    options.array_bounds_check = "OFF";
                    options.cast_bounds_check = "OFF";
                    options.null_pointer_check = "OFF";
                }
                options.enable_bytecode_inliner = true;
            },
            else => return diag.failAt(0, "VM unsupported Optimization_Type value {d}", .{mode}),
        }
    }

    fn buildOptionsGetField(vm: *VM, index: usize, field_name: []const u8, diag: Diagnostic) !RegisterValue {
        if (index >= vm.build_options.items.len) return diag.failAt(0, "VM Build_Options handle out of range", .{});
        const options = vm.build_options.items[index];
        if (std.mem.eql(u8, field_name, "output_executable_name")) return .{ .string = options.output_executable_name };
        if (std.mem.eql(u8, field_name, "output_path")) return .{ .string = options.output_path };
        if (std.mem.eql(u8, field_name, "intermediate_path")) return .{ .string = options.intermediate_path };
        if (std.mem.eql(u8, field_name, "output_type")) return .{ .string = options.output_type };
        if (std.mem.eql(u8, field_name, "backend")) return .{ .string = options.backend };
        if (std.mem.eql(u8, field_name, "write_added_strings")) return .{ .bool = options.write_added_strings };
        if (std.mem.eql(u8, field_name, "stack_trace")) return .{ .bool = options.stack_trace };
        if (std.mem.eql(u8, field_name, "backtrace_on_crash")) return .{ .string = options.backtrace_on_crash };
        if (std.mem.eql(u8, field_name, "array_bounds_check")) return .{ .string = options.array_bounds_check };
        if (std.mem.eql(u8, field_name, "cast_bounds_check")) return .{ .string = options.cast_bounds_check };
        if (std.mem.eql(u8, field_name, "null_pointer_check")) return .{ .string = options.null_pointer_check };
        if (std.mem.eql(u8, field_name, "enable_bytecode_inliner")) return .{ .bool = options.enable_bytecode_inliner };
        if (std.mem.eql(u8, field_name, "runtime_storageless_type_info")) return .{ .bool = options.runtime_storageless_type_info };
        if (std.mem.eql(u8, field_name, "use_custom_link_command")) return .{ .bool = options.use_custom_link_command };
        if (std.mem.eql(u8, field_name, "llvm_options")) return .{ .build_llvm_options = index };
        if (std.mem.eql(u8, field_name, "import_path")) return .{ .ptr = try vm.buildOptionsImportPath(index, diag) };
        if (std.mem.eql(u8, field_name, "compile_time_command_line")) return .{ .ptr = try vm.buildOptionsCommandLine(index, diag) };
        return diag.failAt(0, "VM Build_Options has no implemented field '{s}'", .{field_name});
    }

    fn typeInfoField(vm: *VM, value: RegisterValue, field_name: []const u8, diag: Diagnostic) !RegisterValue {
        const type_name = switch (value) {
            .type_text => |text| text,
            .type_id => |type_id| typeName(type_id),
            else => return diag.failAt(0, "VM Type_Info field access requires a Type value", .{}),
        };
        if (isPointerTypeText(type_name)) {
            if (std.mem.eql(u8, field_name, "type")) return .{ .int = 4 };
            if (std.mem.eql(u8, field_name, "pointer_to")) return .{ .type_text = stripOnePointer(type_name) };
            return diag.failAt(0, "VM Type_Info_Pointer has no implemented field '{s}'", .{field_name});
        }
        if (std.mem.eql(u8, type_name, "Procedure")) {
            if (std.mem.eql(u8, field_name, "type")) return .{ .int = 8 };
            if (std.mem.eql(u8, field_name, "name")) return .{ .string = "Procedure" };
            return diag.failAt(0, "VM Type_Info procedure metadata has no implemented field '{s}'", .{field_name});
        }
        if (builtinTypeInfoTag(type_name)) |tag| {
            if (std.mem.eql(u8, field_name, "type")) return .{ .int = tag };
            if (std.mem.eql(u8, field_name, "name")) return .{ .string = type_name };
            return diag.failAt(0, "VM Type_Info builtin metadata has no implemented field '{s}'", .{field_name});
        }
        const info_index = vm.program.typeInfoIndexByName(type_name) orelse return diag.failAt(0, "VM has no Type_Info metadata for '{s}'", .{type_name});
        const info = vm.program.type_infos.items[info_index];
        if (std.mem.eql(u8, field_name, "type")) return .{ .int = info.tag };
        if (std.mem.eql(u8, field_name, "name")) return .{ .string = info.name };
        if (std.mem.eql(u8, field_name, "members")) {
            const header = try vm.newDynamicArray(0, 8, diag);
            const array_index = vm.dynamicArrayIndexForPointer(header) orelse return diag.failAt(0, "VM Type_Info members allocation failed", .{});
            for (info.members) |member| try vm.dynamic_arrays.items[array_index].elems.append(vm.allocator, .{ .type_info_member = member });
            try vm.writeDynamicArrayHeader(array_index, diag);
            return .{ .ptr = header };
        }
        return diag.failAt(0, "VM Type_Info has no implemented field '{s}'", .{field_name});
    }

    fn isPointerTypeText(raw: []const u8) bool {
        return std.mem.startsWith(u8, std.mem.trim(u8, raw, " \t\r\n"), "*");
    }

    fn stripOnePointer(raw: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] != '*') return trimmed;
        return std.mem.trim(u8, trimmed[1..], " \t\r\n");
    }

    fn builtinTypeInfoTag(name: []const u8) ?i64 {
        if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "s64") or std.mem.eql(u8, name, "s32") or std.mem.eql(u8, name, "u8") or std.mem.eql(u8, name, "u16") or std.mem.eql(u8, name, "u32") or std.mem.eql(u8, name, "u64")) return 1;
        if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "float32") or std.mem.eql(u8, name, "float64")) return 2;
        if (std.mem.eql(u8, name, "bool")) return 3;
        if (std.mem.eql(u8, name, "string")) return 9;
        return null;
    }

    fn typeInfoMemberField(vm: *VM, value: RegisterValue, field_name: []const u8, diag: Diagnostic) !RegisterValue {
        _ = vm;
        const member = switch (value) {
            .type_info_member => |member| member,
            else => return diag.failAt(0, "VM Type_Info member field access requires a Type_Info member value", .{}),
        };
        if (std.mem.eql(u8, field_name, "name")) return .{ .string = member.name };
        if (std.mem.eql(u8, field_name, "type")) return .{ .type_text = member.type_name };
        if (std.mem.eql(u8, field_name, "flags")) return .{ .int = member.flags };
        if (std.mem.eql(u8, field_name, "offset_in_bytes")) return .{ .int = 0 };
        return diag.failAt(0, "VM Type_Info member has no implemented field '{s}'", .{field_name});
    }

    fn buildOptionsLlvmGetField(vm: *VM, index: usize, field_name: []const u8, diag: Diagnostic) !RegisterValue {
        if (index >= vm.build_options.items.len) return diag.failAt(0, "VM Build_Options.llvm_options handle out of range", .{});
        const options = vm.build_options.items[index];
        if (std.mem.eql(u8, field_name, "output_bitcode")) return .{ .bool = options.llvm_output_bitcode };
        return diag.failAt(0, "VM Build_Options.llvm_options has no implemented field '{s}'", .{field_name});
    }

    fn buildOptionsLlvmSetField(vm: *VM, index: usize, field_name: []const u8, value: RegisterValue, diag: Diagnostic) !void {
        if (index >= vm.build_options.items.len) return diag.failAt(0, "VM Build_Options.llvm_options handle out of range", .{});
        const options = &vm.build_options.items[index];
        if (std.mem.eql(u8, field_name, "output_bitcode")) {
            options.llvm_output_bitcode = try registerTruthy(value, diag, "Build_Options.llvm_options.output_bitcode");
            return;
        }
        return diag.failAt(0, "VM Build_Options.llvm_options has no implemented field '{s}'", .{field_name});
    }

    fn buildOptionsSetField(vm: *VM, index: usize, field_name: []const u8, value: RegisterValue, diag: Diagnostic) !void {
        if (index >= vm.build_options.items.len) return diag.failAt(0, "VM Build_Options handle out of range", .{});
        const options = &vm.build_options.items[index];
        if (std.mem.eql(u8, field_name, "output_executable_name")) {
            options.output_executable_name = try vm.registerText(value, diag, "Build_Options.output_executable_name");
            return;
        }
        if (std.mem.eql(u8, field_name, "output_path")) {
            options.output_path = try vm.registerText(value, diag, "Build_Options.output_path");
            return;
        }
        if (std.mem.eql(u8, field_name, "intermediate_path")) {
            options.intermediate_path = try vm.registerText(value, diag, "Build_Options.intermediate_path");
            return;
        }
        if (std.mem.eql(u8, field_name, "output_type")) {
            options.output_type = try buildOptionsEnumText(value, "output_type", diag);
            return;
        }
        if (std.mem.eql(u8, field_name, "backend")) {
            options.backend = try buildOptionsEnumText(value, "backend", diag);
            return;
        }
        if (std.mem.eql(u8, field_name, "write_added_strings")) {
            options.write_added_strings = try registerTruthy(value, diag, "Build_Options.write_added_strings");
            return;
        }
        if (std.mem.eql(u8, field_name, "stack_trace")) {
            options.stack_trace = try registerTruthy(value, diag, "Build_Options.stack_trace");
            return;
        }
        if (std.mem.eql(u8, field_name, "backtrace_on_crash")) {
            options.backtrace_on_crash = try buildOptionsEnumText(value, "backtrace_on_crash", diag);
            return;
        }
        if (std.mem.eql(u8, field_name, "array_bounds_check")) {
            options.array_bounds_check = try buildOptionsEnumText(value, "array_bounds_check", diag);
            return;
        }
        if (std.mem.eql(u8, field_name, "cast_bounds_check")) {
            options.cast_bounds_check = try buildOptionsEnumText(value, "cast_bounds_check", diag);
            return;
        }
        if (std.mem.eql(u8, field_name, "null_pointer_check")) {
            options.null_pointer_check = try buildOptionsEnumText(value, "null_pointer_check", diag);
            return;
        }
        if (std.mem.eql(u8, field_name, "enable_bytecode_inliner")) {
            options.enable_bytecode_inliner = try registerTruthy(value, diag, "Build_Options.enable_bytecode_inliner");
            return;
        }
        if (std.mem.eql(u8, field_name, "runtime_storageless_type_info")) {
            options.runtime_storageless_type_info = try registerTruthy(value, diag, "Build_Options.runtime_storageless_type_info");
            return;
        }
        if (std.mem.eql(u8, field_name, "use_custom_link_command")) {
            options.use_custom_link_command = try registerTruthy(value, diag, "Build_Options.use_custom_link_command");
            return;
        }
        if (std.mem.eql(u8, field_name, "import_path")) {
            const ptr = try registerPointer(value, diag, "Build_Options.import_path");
            options.import_path = vm.dynamicArrayIndexForPointer(ptr) orelse return diag.failAt(0, "Build_Options.import_path requires a dynamic string array", .{});
            return;
        }
        if (std.mem.eql(u8, field_name, "compile_time_command_line")) {
            const ptr = try registerPointer(value, diag, "Build_Options.compile_time_command_line");
            options.compile_time_command_line = vm.dynamicArrayIndexForPointer(ptr) orelse return diag.failAt(0, "Build_Options.compile_time_command_line requires a dynamic string array", .{});
            return;
        }
        return diag.failAt(0, "VM Build_Options has no implemented field '{s}'", .{field_name});
    }

    fn buildOptionsImportPath(vm: *VM, index: usize, diag: Diagnostic) !Pointer {
        const options = &vm.build_options.items[index];
        if (options.import_path) |array_index| return vm.dynamic_arrays.items[array_index].header orelse vm.dynamic_arrays.items[array_index].slot orelse return diag.failAt(0, "Build_Options.import_path array has no handle", .{});
        const header = try vm.newDynamicArray(0, 16, diag);
        const array_index = vm.dynamicArrayIndexForPointer(header) orelse return diag.failAt(0, "Build_Options.import_path allocation failed", .{});
        _ = try vm.dynamicArrayAdd(header, .{ .string = "modules" }, 16, diag);
        options.import_path = array_index;
        return header;
    }

    fn buildOptionsCommandLine(vm: *VM, index: usize, diag: Diagnostic) !Pointer {
        const options = &vm.build_options.items[index];
        if (options.compile_time_command_line) |array_index| return vm.dynamic_arrays.items[array_index].header orelse vm.dynamic_arrays.items[array_index].slot orelse return diag.failAt(0, "Build_Options.compile_time_command_line array has no handle", .{});
        const header = try vm.newDynamicArray(0, 16, diag);
        const array_index = vm.dynamicArrayIndexForPointer(header) orelse return diag.failAt(0, "Build_Options.compile_time_command_line allocation failed", .{});
        for (vm.command_line) |arg| _ = try vm.dynamicArrayAdd(header, .{ .string = arg }, 16, diag);
        options.compile_time_command_line = array_index;
        return header;
    }

    fn loadByte(vm: *VM, ptr: Pointer, diag: Diagnostic) !i64 {
        return (try vm.blockSlice(ptr, 1, diag))[0];
    }

    fn loadU64(vm: *VM, ptr: Pointer, diag: Diagnostic) !u64 {
        return std.mem.readInt(u64, try vm.blockArray8(ptr, diag), .little);
    }

    fn loadF32(vm: *VM, ptr: Pointer, diag: Diagnostic) !f32 {
        const bytes = try vm.blockSlice(ptr, 4, diag);
        return @bitCast(std.mem.readInt(u32, bytes[0..4], .little));
    }

    fn storeF32(vm: *VM, ptr: Pointer, value: f32, diag: Diagnostic) !void {
        const bytes = try vm.blockSlice(ptr, 4, diag);
        std.mem.writeInt(u32, bytes[0..4], @bitCast(value), .little);
    }

    fn storeByte(vm: *VM, ptr: Pointer, value: u8, diag: Diagnostic) !void {
        (try vm.blockSlice(ptr, 1, diag))[0] = value;
    }

    fn storeStringSlot(vm: *VM, ptr: Pointer, text: []const u8, diag: Diagnostic) !void {
        try vm.string_slots.put(vm.allocator, pointerKey(ptr), text);
        std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), 0, .little);
    }

    fn loadStringSlot(vm: *VM, ptr: Pointer, diag: Diagnostic) ![]const u8 {
        return vm.string_slots.get(pointerKey(ptr)) orelse try vm.readRemainingBytes(ptr, diag);
    }

    fn storeRegister(vm: *VM, ptr: Pointer, value: RegisterValue, diag: Diagnostic) !void {
        switch (value) {
            .int => |int_value| std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), @bitCast(int_value), .little),
            .float => |float_value| std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), @bitCast(float_value), .little),
            .bool => |bool_value| try vm.storeByte(ptr, if (bool_value) 1 else 0, diag),
            .bytes => |bytes| if (bytes.len != 0) @memcpy(try vm.blockSlice(ptr, bytes.len, diag), bytes),
            .type_id => |type_id| std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), type_id, .little),
            .type_text => return diag.failAt(0, "VM cannot store Type values into raw memory", .{}),
            .type_info_member => return diag.failAt(0, "VM cannot store Type_Info member values into raw memory", .{}),
            .ptr => |source_ptr| std.mem.writeInt(u64, try vm.blockArray8(ptr, diag), encodePointer(source_ptr), .little),
            .string => |text| try vm.storeStringSlot(ptr, text, diag),
            .code => |code| if (code.text.len != 0) @memcpy(try vm.blockSlice(ptr, code.text.len, diag), code.text),
            .tuple => return diag.failAt(0, "VM cannot store undestructured multi-return values into raw memory", .{}),
            .code_node, .code_nodes, .code_note, .code_notes, .code_arg, .code_args => return diag.failAt(0, "VM cannot store compiler Code_Node values into raw memory", .{}),
            .message => return diag.failAt(0, "VM cannot store compiler Message values into raw memory", .{}),
            .source_location => return diag.failAt(0, "VM cannot store Source_Code_Location into raw memory; use field assignment", .{}),
            .calendar => return diag.failAt(0, "VM cannot store Calendar into raw memory; use field access or calendar_to_string instead", .{}),
            .build_options, .build_llvm_options => return diag.failAt(0, "VM cannot store Build_Options into raw memory; use field assignment", .{}),
            .empty => return diag.failAt(0, "VM cannot store an uninitialized register", .{}),
        }
    }

    fn copyBytes(vm: *VM, dest: Pointer, source: RegisterValue, count: usize, diag: Diagnostic) !void {
        const dest_slice = try vm.blockSlice(dest, count, diag);
        switch (source) {
            .ptr => |ptr| @memcpy(dest_slice, try vm.blockSlice(ptr, count, diag)),
            .bytes => |bytes| {
                if (count > bytes.len) return diag.failAt(0, "VM memcpy source byte array is too small", .{});
                if (count != 0) @memcpy(dest_slice, bytes[0..count]);
            },
            else => {
                const ptr = try vm.materializeRegister(source, diag);
                @memcpy(dest_slice, try vm.blockSlice(ptr, count, diag));
            },
        }
    }

    fn arrayCount(vm: *VM, value: RegisterValue, elem_size_hint: usize, diag: Diagnostic) !usize {
        return switch (value) {
            .bytes => |bytes| bytes.len,
            .ptr => |ptr| if (vm.dynamicArrayIndexForPointer(ptr)) |array_index|
                vm.dynamic_arrays.items[array_index].elems.items.len
            else if (elem_size_hint != 0)
                vm.dynamic_arrays.items[try vm.ensureDynamicArrayForPointer(ptr, elem_size_hint, diag)].elems.items.len
            else
                (try vm.readRemainingBytes(ptr, diag)).len,
            .code_nodes => |nodes| nodes.len,
            .code_notes => |notes| notes.len,
            .code_args => |args| args.len,
            else => diag.failAt(0, "VM array_count requires array-compatible value", .{}),
        };
    }

    fn newDynamicArray(vm: *VM, count: usize, elem_size: usize, diag: Diagnostic) !Pointer {
        const header = try vm.allocBlock(24);
        var array = DynamicArray{ .header = header, .elem_size = elem_size };
        errdefer array.elems.deinit(vm.allocator);
        if (count != 0) {
            const data = try vm.allocBlock(count * elem_size);
            array.data = data;
            try array.elems.ensureTotalCapacity(vm.allocator, count);
            var i: usize = 0;
            while (i < count) : (i += 1) array.elems.appendAssumeCapacity(.{ .int = 0 });
        }
        const index = try vm.addDynamicArray(array);
        try vm.writeDynamicArrayHeader(index, diag);
        return header;
    }

    fn dynamicArrayAdd(vm: *VM, array_ptr: Pointer, item: RegisterValue, elem_size: usize, diag: Diagnostic) !Pointer {
        const array_index = try vm.ensureDynamicArrayForPointer(array_ptr, elem_size, diag);
        var array = &vm.dynamic_arrays.items[array_index];
        if (array.elem_size != elem_size) {
            if (array.elems.items.len != 0) return diag.failAt(0, "VM array_add element size changed from {d} to {d}", .{ array.elem_size, elem_size });
            array.elem_size = elem_size;
        }
        try array.elems.append(vm.allocator, item);
        try vm.ensureDynamicArrayData(array_index, array.elems.items.len, diag);
        const item_ptr = vm.dynamicArrayItemPointer(array_index, array.elems.items.len - 1, diag) catch |err| return err;
        try vm.storeDynamicArrayElementBytes(item_ptr, item, elem_size, diag);
        try vm.writeDynamicArrayHeader(array_index, diag);
        return item_ptr;
    }

    fn dynamicArrayAddSpread(vm: *VM, array_ptr: Pointer, source: RegisterValue, elem_size: usize, diag: Diagnostic) !Pointer {
        const source_ptr = try registerPointer(source, diag, "array_add spread source");
        const source_index = vm.dynamicArrayIndexForPointer(source_ptr) orelse return diag.failAt(0, "array_add spread source must be a dynamic array", .{});
        var last: ?Pointer = null;
        for (vm.dynamic_arrays.items[source_index].elems.items) |item| {
            last = try vm.dynamicArrayAdd(array_ptr, item, elem_size, diag);
        }
        return last orelse array_ptr;
    }

    fn dynamicArrayPop(vm: *VM, array_ptr: Pointer, elem_size: usize, elem_kind: u32, diag: Diagnostic) !RegisterValue {
        const array_index = vm.dynamicArrayIndexForPointer(array_ptr) orelse return diag.failAt(0, "VM pop requires a dynamic array", .{});
        const array = &vm.dynamic_arrays.items[array_index];
        if (array.elems.items.len == 0) return diag.failAt(0, "VM pop from empty dynamic array", .{});
        const value = try vm.dynamicArrayIndex(array_ptr, array.elems.items.len - 1, elem_size, elem_kind, diag) orelse return diag.failAt(0, "VM pop failed to read dynamic array element", .{});
        _ = array.elems.pop();
        try vm.writeDynamicArrayHeader(array_index, diag);
        return value;
    }

    fn dynamicArrayReset(vm: *VM, array_ptr: Pointer, elem_size: usize, diag: Diagnostic) !void {
        const array_index = try vm.ensureDynamicArrayForPointer(array_ptr, elem_size, diag);
        vm.dynamic_arrays.items[array_index].elems.clearRetainingCapacity();
        try vm.writeDynamicArrayHeader(array_index, diag);
    }

    fn dynamicArrayReserve(vm: *VM, array_ptr: Pointer, capacity: usize, elem_size: usize, diag: Diagnostic) !void {
        const array_index = try vm.ensureDynamicArrayForPointer(array_ptr, elem_size, diag);
        try vm.dynamic_arrays.items[array_index].elems.ensureTotalCapacity(vm.allocator, capacity);
        try vm.ensureDynamicArrayData(array_index, capacity, diag);
        try vm.writeDynamicArrayHeader(array_index, diag);
    }

    fn dynamicArrayOrderedRemove(vm: *VM, array_ptr: Pointer, index: usize, elem_size: usize, diag: Diagnostic) !void {
        const array_index = vm.dynamicArrayIndexForPointer(array_ptr) orelse return diag.failAt(0, "VM array_ordered_remove_by_index requires a dynamic array", .{});
        const array = &vm.dynamic_arrays.items[array_index];
        if (index >= array.elems.items.len) return diag.failAt(0, "VM array_ordered_remove_by_index out of bounds", .{});
        _ = array.elems.orderedRemove(index);
        try vm.ensureDynamicArrayData(array_index, array.elems.items.len, diag);
        for (array.elems.items, 0..) |item, i| {
            const item_ptr = try vm.dynamicArrayItemPointer(array_index, i, diag);
            try vm.storeDynamicArrayElementBytes(item_ptr, item, elem_size, diag);
        }
        try vm.writeDynamicArrayHeader(array_index, diag);
    }

    fn dynamicArrayFind(vm: *VM, array_ptr: Pointer, needle: RegisterValue, elem_size: usize, elem_kind: u32, diag: Diagnostic) !bool {
        const array_index = vm.dynamicArrayIndexForPointer(array_ptr) orelse return diag.failAt(0, "VM array_find requires a dynamic array", .{});
        var i: usize = 0;
        while (i < vm.dynamic_arrays.items[array_index].elems.items.len) : (i += 1) {
            const value = try vm.dynamicArrayIndex(array_ptr, i, elem_size, elem_kind, diag) orelse return diag.failAt(0, "VM array_find failed to read dynamic array element", .{});
            if (try vm.valuesEqual(value, needle, diag)) return true;
        }
        return false;
    }

    fn dynamicArrayCopy(vm: *VM, source_ptr: Pointer, elem_size: usize, diag: Diagnostic) !Pointer {
        const result = try vm.newDynamicArray(0, elem_size, diag);
        return try vm.dynamicArrayCopyTo(result, source_ptr, elem_size, diag);
    }

    fn dynamicArrayCopyTo(vm: *VM, dest_ptr: Pointer, source_ptr: Pointer, elem_size: usize, diag: Diagnostic) !Pointer {
        const source_index = vm.dynamicArrayIndexForPointer(source_ptr) orelse return diag.failAt(0, "VM array_copy source must be a dynamic array", .{});
        const dest_index = try vm.ensureDynamicArrayForPointer(dest_ptr, elem_size, diag);
        vm.dynamic_arrays.items[dest_index].elems.clearRetainingCapacity();
        for (vm.dynamic_arrays.items[source_index].elems.items) |item| {
            _ = try vm.dynamicArrayAdd(dest_ptr, item, elem_size, diag);
        }
        return dest_ptr;
    }

    fn valuesEqual(vm: *VM, lhs: RegisterValue, rhs: RegisterValue, diag: Diagnostic) !bool {
        _ = vm;
        _ = diag;
        return switch (lhs) {
            .int => |l| switch (rhs) {
                .int => |r| l == r,
                else => false,
            },
            .float => |l| switch (rhs) {
                .float => |r| l == r,
                else => false,
            },
            .bool => |l| switch (rhs) {
                .bool => |r| l == r,
                else => false,
            },
            .string, .bytes => |l| switch (rhs) {
                .string, .bytes => |r| std.mem.eql(u8, l, r),
                else => false,
            },
            .ptr => |l| switch (rhs) {
                .ptr => |r| l.block == r.block and l.offset == r.offset,
                else => false,
            },
            else => false,
        };
    }

    fn sortDynamicArray(vm: *VM, array_ptr: Pointer, kind: u32, diag: Diagnostic) !void {
        const array_index = vm.dynamicArrayIndexForPointer(array_ptr) orelse return diag.failAt(0, "VM sort_array requires a dynamic array pointer", .{});
        const array = &vm.dynamic_arrays.items[array_index];
        var i: usize = 1;
        while (i < array.elems.items.len) : (i += 1) {
            var j = i;
            while (j > 0 and try compareSortValues(array.elems.items[j - 1], array.elems.items[j], kind, diag) > 0) : (j -= 1) {
                std.mem.swap(RegisterValue, &array.elems.items[j - 1], &array.elems.items[j]);
            }
        }
        try vm.ensureDynamicArrayData(array_index, array.elems.items.len, diag);
        for (array.elems.items, 0..) |item, index| {
            const item_ptr = try vm.dynamicArrayItemPointer(array_index, index, diag);
            try vm.storeDynamicArrayElementBytes(item_ptr, item, array.elem_size, diag);
        }
        try vm.writeDynamicArrayHeader(array_index, diag);
    }

    fn sortStaticArray(vm: *VM, array_ptr: Pointer, count: usize, elem_size: usize, kind: u32, diag: Diagnostic) !void {
        var i: usize = 1;
        while (i < count) : (i += 1) {
            var j = i;
            while (j > 0) {
                const lhs = try vm.loadStaticArrayElement(array_ptr, j - 1, elem_size, kind, diag);
                const rhs = try vm.loadStaticArrayElement(array_ptr, j, elem_size, kind, diag);
                if (try compareSortValues(lhs, rhs, kind, diag) <= 0) break;
                try vm.storeStaticArrayElement(array_ptr, j - 1, rhs, elem_size, kind, diag);
                try vm.storeStaticArrayElement(array_ptr, j, lhs, elem_size, kind, diag);
                j -= 1;
            }
        }
    }

    fn loadStaticArrayElement(vm: *VM, array_ptr: Pointer, index: usize, elem_size: usize, kind: u32, diag: Diagnostic) !RegisterValue {
        var ptr = array_ptr;
        ptr.offset += index * elem_size;
        return switch (kind) {
            1 => if (elem_size == 4)
                .{ .float = @as(f64, @floatCast(try vm.loadF32(ptr, diag))) }
            else
                .{ .float = @bitCast(try vm.loadU64(ptr, diag)) },
            2 => .{ .string = try vm.loadStringSlot(ptr, diag) },
            else => if (elem_size == 1)
                .{ .int = try vm.loadByte(ptr, diag) }
            else
                .{ .int = @bitCast(try vm.loadU64(ptr, diag)) },
        };
    }

    fn storeStaticArrayElement(vm: *VM, array_ptr: Pointer, index: usize, value: RegisterValue, elem_size: usize, kind: u32, diag: Diagnostic) !void {
        var ptr = array_ptr;
        ptr.offset += index * elem_size;
        switch (kind) {
            1 => {
                const float_value = switch (value) {
                    .float => |v| v,
                    .int => |v| @as(f64, @floatFromInt(v)),
                    else => return diag.failAt(0, "VM static float array store requires numeric value", .{}),
                };
                if (elem_size == 4)
                    try vm.storeF32(ptr, @floatCast(float_value), diag)
                else
                    try vm.storeRegister(ptr, .{ .float = float_value }, diag);
            },
            2 => {
                const text = switch (value) {
                    .string => |v| v,
                    .bytes => |v| v,
                    else => return diag.failAt(0, "VM static string array store requires string value", .{}),
                };
                try vm.storeStringSlot(ptr, text, diag);
            },
            else => try vm.storeRegister(ptr, value, diag),
        }
    }

    fn dynamicArrayData(vm: *VM, ptr: Pointer, diag: Diagnostic) !?Pointer {
        const array_index = vm.dynamicArrayIndexForPointer(ptr) orelse return null;
        try vm.ensureDynamicArrayData(array_index, vm.dynamic_arrays.items[array_index].elems.items.len, diag);
        return vm.dynamic_arrays.items[array_index].data;
    }

    fn dynamicArrayIndex(vm: *VM, ptr: Pointer, index: usize, elem_size: usize, elem_kind: u32, diag: Diagnostic) !?RegisterValue {
        const array_index = vm.dynamicArrayIndexForPointer(ptr) orelse return null;
        const array = &vm.dynamic_arrays.items[array_index];
        if (index >= array.elems.items.len) return diag.failAt(0, "VM dynamic array index out of bounds", .{});
        if (elem_kind == 1) return .{ .ptr = try vm.dynamicArrayItemPointer(array_index, index, diag) };
        const value = array.elems.items[index];
        if (elem_kind == 3) {
            return switch (value) {
                .type_info_member => |member| .{ .type_info_member = member },
                else => diag.failAt(0, "VM dynamic array Type_Info member index found {s} element", .{@tagName(value)}),
            };
        }
        if (elem_kind == 2) {
            return switch (value) {
                .string => |text| .{ .string = text },
                .bytes => |bytes| .{ .string = bytes },
                else => diag.failAt(0, "VM dynamic array string index found {s} element", .{@tagName(value)}),
            };
        }
        return switch (value) {
            .int, .float, .bool, .string, .bytes, .code, .ptr, .type_id, .type_text, .type_info_member, .source_location, .calendar, .build_options, .build_llvm_options => value,
            .empty => if (elem_size == 1)
                .{ .int = try vm.loadByte(try vm.dynamicArrayItemPointer(array_index, index, diag), diag) }
            else
                .{ .int = @bitCast(try vm.loadU64(try vm.dynamicArrayItemPointer(array_index, index, diag), diag)) },
            .tuple => diag.failAt(0, "VM dynamic arrays cannot index undestructured multi-return values as runtime data", .{}),
            .code_node, .code_nodes, .code_note, .code_notes, .code_arg, .code_args => diag.failAt(0, "VM dynamic arrays cannot index compiler Code_Node values as runtime data", .{}),
            .message => diag.failAt(0, "VM dynamic arrays cannot index compiler Message values as runtime data", .{}),
        };
    }

    fn addDynamicArray(vm: *VM, array: DynamicArray) !usize {
        const index = vm.dynamic_arrays.items.len;
        try vm.dynamic_arrays.append(vm.allocator, array);
        if (array.header) |header| try vm.dynamic_array_refs.put(vm.allocator, pointerKey(header), index);
        if (array.slot) |slot| try vm.dynamic_array_refs.put(vm.allocator, pointerKey(slot), index);
        if (array.data) |data| try vm.dynamic_array_refs.put(vm.allocator, pointerKey(data), index);
        return index;
    }

    fn ensureDynamicArrayForPointer(vm: *VM, ptr: Pointer, elem_size: usize, diag: Diagnostic) !usize {
        if (vm.dynamicArrayIndexForPointer(ptr)) |index| return index;
        var array = DynamicArray{ .slot = ptr, .elem_size = elem_size };
        errdefer array.elems.deinit(vm.allocator);
        const index = try vm.addDynamicArray(array);
        try vm.writeDynamicArrayHeader(index, diag);
        return index;
    }

    fn dynamicArrayIndexForPointer(vm: *VM, ptr: Pointer) ?usize {
        if (vm.dynamic_array_refs.get(pointerKey(ptr))) |index| return index;
        return null;
    }

    fn ensureDynamicArrayData(vm: *VM, array_index: usize, count: usize, diag: Diagnostic) !void {
        const array = &vm.dynamic_arrays.items[array_index];
        const byte_count = @max(count * array.elem_size, 1);
        if (array.data) |data| {
            const block = vm.memory_blocks.items[data.block];
            if (block.len >= byte_count) return;
            _ = vm.dynamic_array_refs.remove(pointerKey(data));
        }
        const old_data = array.data;
        const new_data = try vm.allocBlock(byte_count);
        if (old_data) |old| {
            const old_bytes = try vm.readRemainingBytes(old, diag);
            const copy_len = @min(old_bytes.len, byte_count);
            if (copy_len != 0) @memcpy((try vm.blockSlice(new_data, copy_len, diag)), old_bytes[0..copy_len]);
        }
        array.data = new_data;
        try vm.dynamic_array_refs.put(vm.allocator, pointerKey(new_data), array_index);
    }

    fn dynamicArrayItemPointer(vm: *VM, array_index: usize, index: usize, diag: Diagnostic) !Pointer {
        try vm.ensureDynamicArrayData(array_index, vm.dynamic_arrays.items[array_index].elems.items.len, diag);
        const data = vm.dynamic_arrays.items[array_index].data orelse return diag.failAt(0, "VM dynamic array has no data block", .{});
        return .{ .block = data.block, .offset = data.offset + index * vm.dynamic_arrays.items[array_index].elem_size };
    }

    fn storeDynamicArrayElementBytes(vm: *VM, dest: Pointer, value: RegisterValue, elem_size: usize, diag: Diagnostic) !void {
        switch (value) {
            .ptr => |ptr| {
                const src = try vm.blockSlice(ptr, elem_size, diag);
                if (elem_size != 0) @memcpy(try vm.blockSlice(dest, elem_size, diag), src);
            },
            .string => |text| try vm.storeStringSlot(dest, text, diag),
            .bytes => |bytes| {
                const copy_len = @min(bytes.len, elem_size);
                if (copy_len != 0) @memcpy(try vm.blockSlice(dest, copy_len, diag), bytes[0..copy_len]);
            },
            else => try vm.storeRegister(dest, value, diag),
        }
    }

    fn writeDynamicArrayHeader(vm: *VM, array_index: usize, diag: Diagnostic) !void {
        const array = &vm.dynamic_arrays.items[array_index];
        const count = array.elems.items.len;
        if (array.header) |header| {
            std.mem.writeInt(u64, try vm.blockArray8(header, diag), @intCast(count), .little);
            std.mem.writeInt(u64, try vm.blockArray8(.{ .block = header.block, .offset = header.offset + 8 }, diag), @intCast(count), .little);
        }
        if (array.slot) |slot| {
            std.mem.writeInt(u64, try vm.blockArray8(slot, diag), @intCast(count), .little);
        }
    }

    fn printValue(vm: *VM, value: RegisterValue, diag: Diagnostic, context: []const u8) anyerror!void {
        switch (value) {
            .string => |text| std.debug.print("{s}", .{text}),
            .bytes => |bytes| std.debug.print("{s}", .{bytes}),
            .code => |code| std.debug.print("{s}", .{code.text}),
            .int => |int_value| std.debug.print("{d}", .{int_value}),
            .float => |float_value| std.debug.print("{d}", .{float_value}),
            .bool => |bool_value| std.debug.print("{s}", .{if (bool_value) "true" else "false"}),
            .type_id => |type_id| std.debug.print("{s}", .{typeName(type_id)}),
            .type_text => |type_text| std.debug.print("{s}", .{type_text}),
            .type_info_member => |member| std.debug.print("Type_Info_Struct_Member {{ name = \"{s}\"; }}", .{member.name}),
            .tuple => return diag.failAt(0, "{s} cannot print an undestructured multi-return value", .{context}),
            .ptr => |ptr| {
                if (vm.dynamicArrayIndexForPointer(ptr)) |array_index| {
                    try vm.printDynamicArray(array_index, diag);
                } else {
                    std.debug.print("*0x{x}:0x{x}", .{ ptr.block, ptr.offset });
                }
            },
            .code_node => |node| std.debug.print("{s}", .{node.text}),
            .code_nodes => |nodes| {
                std.debug.print("[", .{});
                for (nodes, 0..) |node, i| {
                    if (i != 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{node.text});
                }
                std.debug.print("]", .{});
            },
            .code_note => |note| std.debug.print("@{s}", .{note.text}),
            .code_notes => |notes| {
                std.debug.print("[", .{});
                for (notes, 0..) |note, i| {
                    if (i != 0) std.debug.print(", ", .{});
                    std.debug.print("@{s}", .{note.text});
                }
                std.debug.print("]", .{});
            },
            .code_arg => |arg| std.debug.print("Code_Argument(tree={d}, expression={d})", .{ arg.tree, arg.expression_index }),
            .code_args => |args| {
                std.debug.print("[", .{});
                for (args, 0..) |arg, i| {
                    if (i != 0) std.debug.print(", ", .{});
                    std.debug.print("Code_Argument(tree={d}, expression={d})", .{ arg.tree, arg.expression_index });
                }
                std.debug.print("]", .{});
            },
            .message => |index| {
                if (index >= vm.compiler_messages.items.len) return diag.failAt(0, "VM Message handle out of range", .{});
                const message = vm.compiler_messages.items[index];
                std.debug.print("{{{s}, {d}}}", .{ message.kind, message.workspace });
            },
            .source_location => |loc| std.debug.print("{s}:{d}", .{ loc.fully_pathed_filename, loc.line_number }),
            .calendar => |calendar| std.debug.print("{s}", .{try vm.calendarToString(calendar)}),
            .build_options, .build_llvm_options => |index| try vm.printBuildOptions(index, diag),
            .empty => return diag.failAt(0, "VM {s} cannot print an uninitialized value", .{context}),
        }
    }

    fn printBuildOptions(vm: *VM, index: usize, diag: Diagnostic) anyerror!void {
        if (index >= vm.build_options.items.len) return diag.failAt(0, "VM Build_Options handle out of range", .{});
        const options = vm.build_options.items[index];
        std.debug.print("{{\n", .{});
        std.debug.print("    output_type = {s};\n", .{options.output_type});
        std.debug.print("    backend = {s};\n", .{options.backend});
        std.debug.print("    output_executable_name = \"{s}\";\n", .{options.output_executable_name});
        std.debug.print("    output_path = \"{s}\";\n", .{options.output_path});
        std.debug.print("    intermediate_path = \"{s}\";\n", .{options.intermediate_path});
        std.debug.print("    write_added_strings = {s};\n", .{if (options.write_added_strings) "true" else "false"});
        std.debug.print("    stack_trace = {s};\n", .{if (options.stack_trace) "true" else "false"});
        std.debug.print("    backtrace_on_crash = {s};\n", .{options.backtrace_on_crash});
        std.debug.print("    array_bounds_check = {s};\n", .{options.array_bounds_check});
        std.debug.print("    cast_bounds_check = {s};\n", .{options.cast_bounds_check});
        std.debug.print("    null_pointer_check = {s};\n", .{options.null_pointer_check});
        std.debug.print("    enable_bytecode_inliner = {s};\n", .{if (options.enable_bytecode_inliner) "true" else "false"});
        std.debug.print("    runtime_storageless_type_info = {s};\n", .{if (options.runtime_storageless_type_info) "true" else "false"});
        std.debug.print("    import_path = ", .{});
        try vm.printValue(.{ .ptr = try vm.buildOptionsImportPath(index, diag) }, diag, "Build_Options.import_path print");
        std.debug.print(";\n}}", .{});
    }

    fn printDynamicArray(vm: *VM, array_index: usize, diag: Diagnostic) anyerror!void {
        std.debug.print("[", .{});
        for (vm.dynamic_arrays.items[array_index].elems.items, 0..) |item, i| {
            if (i != 0) std.debug.print(", ", .{});
            switch (item) {
                .string => |text| std.debug.print("\"{s}\"", .{text}),
                .bytes => |bytes| std.debug.print("\"{s}\"", .{bytes}),
                else => try vm.printValue(item, diag, "dynamic array print"),
            }
        }
        std.debug.print("]", .{});
    }

    fn printStaticArray(vm: *VM, array_ptr: Pointer, count: usize, elem_size: usize, kind: u32, diag: Diagnostic) anyerror!void {
        std.debug.print("[", .{});
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (i != 0) std.debug.print(", ", .{});
            const item = try vm.loadStaticArrayElement(array_ptr, i, elem_size, kind, diag);
            if (kind == 1 and elem_size == 4) {
                var ptr = array_ptr;
                ptr.offset += i * elem_size;
                std.debug.print("{d}", .{try vm.loadF32(ptr, diag)});
            } else switch (item) {
                .string => |text| std.debug.print("\"{s}\"", .{text}),
                .bytes => |bytes| std.debug.print("\"{s}\"", .{bytes}),
                else => try vm.printValue(item, diag, "static array print"),
            }
        }
        std.debug.print("]", .{});
    }

    fn ensureCodeTree(vm: *VM, code: CodeValue) !u32 {
        for (vm.code_trees.items, 0..) |tree, i| {
            if (std.mem.eql(u8, tree.source, code.text) and
                std.mem.eql(u8, tree.path, code.path) and
                tree.line_number == code.line_number) return @intCast(i);
        }
        const built = try vm.buildCodeNodes(@intCast(vm.code_trees.items.len), code.text, code.path, code.line_number);
        const nodes = built.nodes;
        errdefer vm.allocator.free(nodes);
        errdefer vm.allocator.free(built.arguments);
        const index: u32 = @intCast(vm.code_trees.items.len);
        try vm.code_trees.append(vm.allocator, .{ .source = code.text, .path = code.path, .line_number = code.line_number, .root = built.root, .nodes = nodes, .arguments = built.arguments });
        return index;
    }

    const BuiltCodeTree = struct {
        root: CodeNode,
        nodes: []CodeNode,
        arguments: []CodeArgument,
    };

    fn buildCodeNodes(vm: *VM, tree_index: u32, code: []const u8, path: []const u8, base_line: i64) !BuiltCodeTree {
        var nodes = std.ArrayList(CodeNode).empty;
        errdefer nodes.deinit(vm.allocator);
        var arguments = std.ArrayList(CodeArgument).empty;
        errdefer arguments.deinit(vm.allocator);
        var root = CodeNode{ .tree = tree_index, .kind = "ROOT", .flags = "0", .text = code, .path = path, .line_number = base_line, .start = 0, .end = code.len };
        const declaration = try vm.parseCodeDeclarationInfo(code);

        if (try vm.tryBuildBlockCodeTree(tree_index, code, &nodes, &arguments)) |block_root| {
            root = block_root;
            stampCodeTreeLocations(&root, nodes.items, code, path, base_line);
            return .{
                .root = root,
                .nodes = try nodes.toOwnedSlice(vm.allocator),
                .arguments = try arguments.toOwnedSlice(vm.allocator),
            };
        }

        if (try vm.tryBuildProcedureCallCodeTree(tree_index, code, &nodes, &arguments)) |call_root| {
            root = call_root;
            stampCodeTreeLocations(&root, nodes.items, code, path, base_line);
            return .{
                .root = root,
                .nodes = try nodes.toOwnedSlice(vm.allocator),
                .arguments = try arguments.toOwnedSlice(vm.allocator),
            };
        }

        var i: usize = 0;
        while (i < code.len) {
            const ch = code[i];
            if (std.ascii.isWhitespace(ch) or ch == ',' or ch == ';' or ch == '(' or ch == ')' or ch == '{' or ch == '}') {
                i += 1;
                continue;
            }
            if (ch == ':' and i + 1 < code.len and (code[i + 1] == '=' or code[i + 1] == ':')) {
                i += 2;
                continue;
            }
            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                const start = i;
                i += 1;
                while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '_')) : (i += 1) {}
                var scan = i;
                while (scan < code.len and std.ascii.isWhitespace(code[scan])) : (scan += 1) {}
                if (scan + 1 < code.len and code[scan] == '.' and code[scan + 1] == '{') {
                    try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "TYPE_INSTANTIATION", .flags = "0", .text = code[start..i], .type_text = code[start..i], .start = start, .end = i });
                    try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "LITERAL", .flags = "0", .text = code[scan .. scan + 2], .type_text = code[start..i], .start = scan, .end = scan + 2 });
                } else {
                    try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "IDENT", .flags = "0", .text = code[start..i], .type_text = identifierLiteralTypeText(code[start..i]), .start = start, .end = i });
                }
                continue;
            }
            if (std.ascii.isDigit(ch)) {
                const start = i;
                i += 1;
                while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '.' or code[i] == '_')) : (i += 1) {}
                const literal_value = std.fmt.parseInt(i64, code[start..i], 10) catch null;
                try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "LITERAL", .flags = "0", .text = code[start..i], .type_text = numericLiteralTypeText(code[start..i]), .start = start, .end = i, .s64 = literal_value });
                continue;
            }
            if (ch == '"' or ch == '\'') {
                const quote = ch;
                const start = i;
                i += 1;
                while (i < code.len) : (i += 1) {
                    if (code[i] == '\\' and i + 1 < code.len) {
                        i += 1;
                        continue;
                    }
                    if (code[i] == quote) {
                        i += 1;
                        break;
                    }
                }
                const end = @min(i, code.len);
                const payload = try vm.decodeCodeStringLiteralValue(code[start..end]);
                try nodes.append(vm.allocator, .{ .tree = tree_index, .index = @intCast(nodes.items.len), .kind = "LITERAL", .flags = "0", .text = code[start..end], .type_text = "string", .start = start, .end = end, .string_value = payload });
                continue;
            }
            i += 1;
        }
        if (declaration) |decl| {
            const expression_index = if (decl.expression_start != null and decl.expression_end != null)
                findCodeExpressionNodeForRange(nodes.items, decl.expression_start.?, decl.expression_end.?)
            else
                null;
            try nodes.append(vm.allocator, .{
                .tree = tree_index,
                .index = @intCast(nodes.items.len),
                .kind = "DECLARATION",
                .flags = "ALLOWED_BY_CONTEXT",
                .text = decl.text,
                .name = decl.name,
                .type_text = decl.type_text,
                .start = decl.start,
                .end = decl.end,
                .expression_index = expression_index,
            });
        }

        stampCodeTreeLocations(&root, nodes.items, code, path, base_line);
        return .{
            .root = root,
            .nodes = try nodes.toOwnedSlice(vm.allocator),
            .arguments = try arguments.toOwnedSlice(vm.allocator),
        };
    }

    fn stampCodeTreeLocations(root: *CodeNode, nodes: []CodeNode, source: []const u8, path: []const u8, base_line: i64) void {
        root.path = path;
        root.line_number = lineForCodeOffset(source, base_line, root.start);
        for (nodes) |*node| {
            node.path = path;
            node.line_number = lineForCodeOffset(source, base_line, node.start);
        }
    }

    const ParsedCodeDeclaration = struct {
        text: []const u8,
        name: []const u8,
        type_text: []const u8,
        expression_start: ?usize = null,
        expression_end: ?usize = null,
        start: usize,
        end: usize,
    };

    fn parseCodeDeclarationInfo(vm: *VM, code: []const u8) !?ParsedCodeDeclaration {
        const trimmed = std.mem.trim(u8, code, " \t\r\n;");
        if (trimmed.len == 0) return null;
        const base_offset = std.mem.indexOf(u8, code, trimmed) orelse 0;
        if (!isIdentStart(trimmed[0])) return null;

        var name_end: usize = 1;
        while (name_end < trimmed.len and isIdentContinue(trimmed[name_end])) name_end += 1;
        const name = trimmed[0..name_end];

        var cursor = name_end;
        while (cursor < trimmed.len and std.ascii.isWhitespace(trimmed[cursor])) cursor += 1;
        if (cursor >= trimmed.len or trimmed[cursor] != ':') return null;
        cursor += 1;

        if (cursor < trimmed.len and trimmed[cursor] == ':') {
            cursor += 1;
            const rhs = std.mem.trim(u8, trimmed[cursor..], " \t\r\n");
            const type_text = try vm.inferCodeExpressionTypeText(rhs);
            const rhs_relative = std.mem.indexOf(u8, trimmed[cursor..], rhs) orelse 0;
            return .{ .text = trimmed, .name = name, .type_text = type_text, .expression_start = base_offset + cursor + rhs_relative, .expression_end = base_offset + cursor + rhs_relative + rhs.len, .start = base_offset, .end = base_offset + trimmed.len };
        }

        if (cursor < trimmed.len and trimmed[cursor] == '=') {
            cursor += 1;
            const rhs = std.mem.trim(u8, trimmed[cursor..], " \t\r\n");
            const type_text = try vm.inferCodeExpressionTypeText(rhs);
            const rhs_relative = std.mem.indexOf(u8, trimmed[cursor..], rhs) orelse 0;
            return .{ .text = trimmed, .name = name, .type_text = type_text, .expression_start = base_offset + cursor + rhs_relative, .expression_end = base_offset + cursor + rhs_relative + rhs.len, .start = base_offset, .end = base_offset + trimmed.len };
        }

        while (cursor < trimmed.len and std.ascii.isWhitespace(trimmed[cursor])) cursor += 1;
        const type_start = cursor;
        while (cursor < trimmed.len and trimmed[cursor] != '=') cursor += 1;
        const type_text = std.mem.trim(u8, trimmed[type_start..cursor], " \t\r\n");
        if (type_text.len == 0) return null;
        var expression_start: ?usize = null;
        var expression_end: ?usize = null;
        if (cursor < trimmed.len and trimmed[cursor] == '=') {
            const rhs = std.mem.trim(u8, trimmed[cursor + 1 ..], " \t\r\n");
            if (rhs.len != 0) {
                const rhs_relative = std.mem.indexOf(u8, trimmed[cursor + 1 ..], rhs) orelse 0;
                expression_start = base_offset + cursor + 1 + rhs_relative;
                expression_end = expression_start.? + rhs.len;
            }
        }
        return .{ .text = trimmed, .name = name, .type_text = type_text, .expression_start = expression_start, .expression_end = expression_end, .start = base_offset, .end = base_offset + trimmed.len };
    }

    fn inferCodeExpressionTypeText(vm: *VM, expression: []const u8) ![]const u8 {
        const text = std.mem.trim(u8, expression, " \t\r\n;");
        if (text.len == 0) return "";
        if (std.fmt.parseInt(i64, text, 10)) |_| return "int" else |_| {}
        if (isFloatLiteralText(text)) return "float64";
        if (text.len >= 2 and ((text[0] == '"' and text[text.len - 1] == '"') or (text[0] == '\'' and text[text.len - 1] == '\''))) return "string";
        if (identifierLiteralTypeText(text).len != 0) return identifierLiteralTypeText(text);
        if (std.mem.indexOf(u8, text, ".{")) |dot_brace| {
            const type_text = std.mem.trim(u8, text[0..dot_brace], " \t\r\n");
            if (type_text.len != 0) return type_text;
        }
        if (std.mem.indexOfScalar(u8, text, '(')) |open_paren| {
            const callee = std.mem.trim(u8, text[0..open_paren], " \t\r\n");
            if (isSimpleIdentifier(callee)) return procedureCallTypeText(callee);
        }
        if (findTopLevelBinaryOperator(text)) |split| {
            const lhs = std.mem.trim(u8, text[0..split.index], " \t\r\n");
            const rhs = std.mem.trim(u8, text[split.index + split.width ..], " \t\r\n");
            const lhs_type = try vm.inferCodeExpressionTypeText(lhs);
            const rhs_type = try vm.inferCodeExpressionTypeText(rhs);
            return binaryExpressionTypeText(text[split.index .. split.index + split.width], lhs_type, rhs_type);
        }
        return "";
    }

    fn tryBuildBlockCodeTree(vm: *VM, tree_index: u32, code: []const u8, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) !?CodeNode {
        const trimmed = std.mem.trim(u8, code, " \t\r\n;");
        if (trimmed.len < 2 or trimmed[0] != '{') return null;
        const close = matchingCloseBrace(trimmed, 0) orelse return null;
        if (std.mem.trim(u8, trimmed[close + 1 ..], " \t\r\n;").len != 0) return null;
        const base_offset = std.mem.indexOf(u8, code, trimmed) orelse 0;
        const body = trimmed[1..close];
        const subexpression_start = nodes.items.len;
        try vm.appendCodeStatements(tree_index, body, base_offset + 1, nodes, arguments);
        return CodeNode{
            .tree = tree_index,
            .kind = "BLOCK",
            .flags = "0",
            .text = trimmed,
            .start = base_offset,
            .end = base_offset + trimmed.len,
            .subexpression_start = subexpression_start,
            .subexpression_count = nodes.items.len - subexpression_start,
        };
    }

    fn appendCodeStatements(vm: *VM, tree_index: u32, body: []const u8, body_start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!void {
        var cursor: usize = 0;
        var segment_start: usize = 0;
        var depth: usize = 0;
        while (cursor <= body.len) : (cursor += 1) {
            const at_end = cursor == body.len;
            if (!at_end) {
                if (body[cursor] == '"' or body[cursor] == '\'') {
                    const quote = body[cursor];
                    cursor += 1;
                    while (cursor < body.len) : (cursor += 1) {
                        if (body[cursor] == '\\' and cursor + 1 < body.len) {
                            cursor += 1;
                            continue;
                        }
                        if (body[cursor] == quote) break;
                    }
                    continue;
                }
                switch (body[cursor]) {
                    '{', '(', '[' => depth += 1,
                    '}', ')', ']' => {
                        if (depth > 0) depth -= 1;
                        if (body[cursor] == '}' and depth == 0 and isBlockStatementText(std.mem.trim(u8, body[segment_start .. cursor + 1], " \t\r\n;"))) {
                            const next = nextNonWhitespace(body, cursor + 1);
                            if (next >= body.len or !startsWithKeyword(body[next..], "else")) {
                                const raw = body[segment_start .. cursor + 1];
                                const statement = std.mem.trim(u8, raw, " \t\r\n;");
                                if (statement.len != 0) {
                                    const relative = std.mem.indexOf(u8, raw, statement) orelse 0;
                                    _ = try vm.appendCodeStatementNode(tree_index, statement, body_start + segment_start + relative, nodes, arguments);
                                }
                                segment_start = cursor + 1;
                            }
                        }
                    },
                    else => {},
                }
                if (body[cursor] != ';' or depth != 0) continue;
            }
            const raw = body[segment_start..cursor];
            const statement = std.mem.trim(u8, raw, " \t\r\n;");
            if (statement.len != 0) {
                const relative = std.mem.indexOf(u8, raw, statement) orelse 0;
                _ = try vm.appendCodeStatementNode(tree_index, statement, body_start + segment_start + relative, nodes, arguments);
            }
            segment_start = cursor + 1;
        }
    }

    fn appendCodeStatementNode(vm: *VM, tree_index: u32, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!u32 {
        if (try vm.tryAppendControlStatementNode(tree_index, text, start, nodes, arguments)) |index| return index;

        const node_index: u32 = @intCast(nodes.items.len);
        const assignment = findTopLevelAssignmentOperator(text);
        const subexpression_start: usize = nodes.items.len + 1;
        try nodes.append(vm.allocator, .{
            .tree = tree_index,
            .index = node_index,
            .kind = if (assignment != null) "ASSIGNMENT" else "STATEMENT",
            .flags = "0",
            .text = text,
            .start = start,
            .end = start + text.len,
        });
        if (assignment) |split| {
            const lhs_text = std.mem.trim(u8, text[0..split.index], " \t\r\n");
            if (lhs_text.len != 0) {
                const lhs_relative = std.mem.indexOf(u8, text[0..split.index], lhs_text) orelse 0;
                _ = try vm.appendCodeExpressionNode(tree_index, lhs_text, start + lhs_relative, nodes, arguments);
            }
            const rhs_raw_start = split.index + split.width;
            const rhs_text = std.mem.trim(u8, text[rhs_raw_start..], " \t\r\n");
            if (rhs_text.len != 0) {
                const rhs_relative = std.mem.indexOf(u8, text[rhs_raw_start..], rhs_text) orelse 0;
                _ = try vm.appendCodeExpressionNode(tree_index, rhs_text, start + rhs_raw_start + rhs_relative, nodes, arguments);
            }
        } else {
            _ = try vm.appendCodeExpressionNode(tree_index, text, start, nodes, arguments);
        }
        nodes.items[node_index].subexpression_start = subexpression_start;
        nodes.items[node_index].subexpression_count = nodes.items.len - subexpression_start;
        return node_index;
    }

    fn tryAppendControlStatementNode(vm: *VM, tree_index: u32, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!?u32 {
        if (startsWithKeyword(text, "return")) {
            const expr_raw = std.mem.trim(u8, text["return".len..], " \t\r\n;");
            const node_index: u32 = @intCast(nodes.items.len);
            const subexpression_start: usize = nodes.items.len + 1;
            try nodes.append(vm.allocator, .{ .tree = tree_index, .index = node_index, .kind = "RETURN", .flags = "0", .text = text, .start = start, .end = start + text.len });
            if (expr_raw.len != 0) {
                const relative = std.mem.indexOf(u8, text, expr_raw) orelse "return".len;
                _ = try vm.appendCodeExpressionNode(tree_index, expr_raw, start + relative, nodes, arguments);
            }
            nodes.items[node_index].subexpression_start = subexpression_start;
            nodes.items[node_index].subexpression_count = nodes.items.len - subexpression_start;
            return node_index;
        }

        if (startsWithKeyword(text, "if")) {
            return try vm.appendConditionalStatementNode(tree_index, text, start, nodes, arguments);
        }
        if (startsWithKeyword(text, "while")) {
            return try vm.appendLoopStatementNode(tree_index, "WHILE", "while".len, text, start, nodes, arguments);
        }
        if (startsWithKeyword(text, "for")) {
            return try vm.appendLoopStatementNode(tree_index, "FOR", "for".len, text, start, nodes, arguments);
        }
        return null;
    }

    fn appendConditionalStatementNode(vm: *VM, tree_index: u32, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!u32 {
        const open = findTopLevelChar(text, '{') orelse return try vm.appendGenericControlFallback(tree_index, "IF", text, start, nodes, arguments);
        const close = matchingCloseBrace(text, open) orelse return try vm.appendGenericControlFallback(tree_index, "IF", text, start, nodes, arguments);
        const node_index: u32 = @intCast(nodes.items.len);
        const subexpression_start: usize = nodes.items.len + 1;
        try nodes.append(vm.allocator, .{ .tree = tree_index, .index = node_index, .kind = "IF", .flags = "0", .text = text, .start = start, .end = start + text.len });

        const condition = std.mem.trim(u8, text["if".len..open], " \t\r\n");
        if (condition.len != 0) {
            const relative = std.mem.indexOf(u8, text["if".len..open], condition) orelse 0;
            _ = try vm.appendCodeExpressionNode(tree_index, condition, start + "if".len + relative, nodes, arguments);
        }
        _ = try vm.appendCodeBlockNode(tree_index, text[open .. close + 1], start + open, nodes, arguments);

        const tail = text[close + 1 ..];
        const tail_relative = nextNonWhitespace(tail, 0);
        if (tail_relative < tail.len and startsWithKeyword(tail[tail_relative..], "else")) {
            const else_text = std.mem.trim(u8, tail[tail_relative + "else".len ..], " \t\r\n");
            if (else_text.len != 0) {
                const else_start = start + close + 1 + tail_relative + "else".len + (std.mem.indexOf(u8, tail[tail_relative + "else".len ..], else_text) orelse 0);
                if (startsWithKeyword(else_text, "if")) {
                    _ = try vm.appendConditionalStatementNode(tree_index, else_text, else_start, nodes, arguments);
                } else if (else_text[0] == '{') {
                    _ = try vm.appendCodeBlockNode(tree_index, else_text, else_start, nodes, arguments);
                } else {
                    _ = try vm.appendCodeStatementNode(tree_index, else_text, else_start, nodes, arguments);
                }
            }
        }

        nodes.items[node_index].subexpression_start = subexpression_start;
        nodes.items[node_index].subexpression_count = nodes.items.len - subexpression_start;
        return node_index;
    }

    fn appendLoopStatementNode(vm: *VM, tree_index: u32, kind: []const u8, keyword_len: usize, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!u32 {
        const open = findTopLevelChar(text, '{') orelse return try vm.appendGenericControlFallback(tree_index, kind, text, start, nodes, arguments);
        const close = matchingCloseBrace(text, open) orelse return try vm.appendGenericControlFallback(tree_index, kind, text, start, nodes, arguments);
        const node_index: u32 = @intCast(nodes.items.len);
        const subexpression_start: usize = nodes.items.len + 1;
        try nodes.append(vm.allocator, .{ .tree = tree_index, .index = node_index, .kind = kind, .flags = "0", .text = text, .start = start, .end = start + text.len });

        const header = std.mem.trim(u8, text[keyword_len..open], " \t\r\n");
        if (header.len != 0) {
            const relative = std.mem.indexOf(u8, text[keyword_len..open], header) orelse 0;
            _ = try vm.appendCodeExpressionNode(tree_index, header, start + keyword_len + relative, nodes, arguments);
        }
        _ = try vm.appendCodeBlockNode(tree_index, text[open .. close + 1], start + open, nodes, arguments);

        nodes.items[node_index].subexpression_start = subexpression_start;
        nodes.items[node_index].subexpression_count = nodes.items.len - subexpression_start;
        return node_index;
    }

    fn appendCodeBlockNode(vm: *VM, tree_index: u32, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!u32 {
        const close = matchingCloseBrace(text, 0) orelse text.len - 1;
        const node_index: u32 = @intCast(nodes.items.len);
        const subexpression_start: usize = nodes.items.len + 1;
        try nodes.append(vm.allocator, .{ .tree = tree_index, .index = node_index, .kind = "BLOCK", .flags = "0", .text = text[0 .. close + 1], .start = start, .end = start + close + 1 });
        if (close > 0) try vm.appendCodeStatements(tree_index, text[1..close], start + 1, nodes, arguments);
        nodes.items[node_index].subexpression_start = subexpression_start;
        nodes.items[node_index].subexpression_count = nodes.items.len - subexpression_start;
        return node_index;
    }

    fn appendGenericControlFallback(vm: *VM, tree_index: u32, kind: []const u8, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!u32 {
        const node_index: u32 = @intCast(nodes.items.len);
        const subexpression_start: usize = nodes.items.len + 1;
        try nodes.append(vm.allocator, .{ .tree = tree_index, .index = node_index, .kind = kind, .flags = "0", .text = text, .start = start, .end = start + text.len });
        _ = try vm.appendCodeExpressionNode(tree_index, text, start, nodes, arguments);
        nodes.items[node_index].subexpression_start = subexpression_start;
        nodes.items[node_index].subexpression_count = nodes.items.len - subexpression_start;
        return node_index;
    }

    fn tryBuildProcedureCallCodeTree(vm: *VM, tree_index: u32, code: []const u8, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) !?CodeNode {
        const trimmed = std.mem.trim(u8, code, " \t\r\n;");
        if (trimmed.len == 0) return null;
        const base_offset = std.mem.indexOf(u8, code, trimmed) orelse 0;
        const open_rel = std.mem.indexOfScalar(u8, trimmed, '(') orelse return null;
        if (open_rel == 0) return null;
        const close_rel = matchingCloseParen(trimmed, open_rel) orelse return null;
        if (std.mem.trim(u8, trimmed[close_rel + 1 ..], " \t\r\n").len != 0) return null;
        const callee = std.mem.trim(u8, trimmed[0..open_rel], " \t\r\n");
        if (!isSimpleIdentifier(callee)) return null;

        var call_arg_indices = std.ArrayList(u32).empty;
        defer call_arg_indices.deinit(vm.allocator);
        const args_text = trimmed[open_rel + 1 .. close_rel];
        var cursor: usize = 0;
        var depth: usize = 0;
        var segment_start: usize = 0;
        while (cursor <= args_text.len) : (cursor += 1) {
            const at_end = cursor == args_text.len;
            if (!at_end) {
                switch (args_text[cursor]) {
                    '(', '{', '[' => depth += 1,
                    ')', '}', ']' => {
                        if (depth > 0) depth -= 1;
                    },
                    ',' => {},
                    else => {},
                }
                if (args_text[cursor] != ',' or depth != 0) continue;
            }
            const segment = std.mem.trim(u8, args_text[segment_start..cursor], " \t\r\n");
            if (segment.len != 0) {
                const relative = std.mem.indexOf(u8, args_text[segment_start..cursor], segment) orelse 0;
                const start = base_offset + open_rel + 1 + segment_start + relative;
                const expr_index = try vm.appendCodeExpressionNode(tree_index, segment, start, nodes, arguments);
                try call_arg_indices.append(vm.allocator, expr_index);
            }
            segment_start = cursor + 1;
        }
        const arg_start_index: u32 = @intCast(arguments.items.len);
        for (call_arg_indices.items) |expr_index| try arguments.append(vm.allocator, .{ .tree = tree_index, .expression_index = expr_index });
        return CodeNode{
            .tree = tree_index,
            .kind = "PROCEDURE_CALL",
            .flags = "0",
            .text = trimmed,
            .type_text = procedureCallTypeText(callee),
            .start = base_offset,
            .end = base_offset + trimmed.len,
            .arg_start = arg_start_index,
            .arg_count = @intCast(call_arg_indices.items.len),
        };
    }

    fn appendCodeExpressionNode(vm: *VM, tree_index: u32, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!u32 {
        const trimmed = std.mem.trim(u8, text, " \t\r\n;");
        const relative = std.mem.indexOf(u8, text, trimmed) orelse 0;
        const absolute_start = start + relative;
        const node_index: u32 = @intCast(nodes.items.len);

        if (try vm.tryAppendProcedureCallExpression(tree_index, node_index, trimmed, absolute_start, nodes, arguments)) return node_index;
        if (try vm.tryAppendBinaryExpression(tree_index, node_index, trimmed, absolute_start, nodes, arguments)) return node_index;

        try nodes.append(vm.allocator, try vm.codeNodeForText(tree_index, node_index, trimmed, absolute_start));
        return node_index;
    }

    fn tryAppendProcedureCallExpression(vm: *VM, tree_index: u32, node_index: u32, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!bool {
        const open_rel = std.mem.indexOfScalar(u8, text, '(') orelse return false;
        if (open_rel == 0) return false;
        const close_rel = matchingCloseParen(text, open_rel) orelse return false;
        if (std.mem.trim(u8, text[close_rel + 1 ..], " \t\r\n").len != 0) return false;
        const callee = std.mem.trim(u8, text[0..open_rel], " \t\r\n");
        if (!isSimpleIdentifier(callee)) return false;

        const subexpression_start: usize = nodes.items.len + 1;
        try nodes.append(vm.allocator, .{
            .tree = tree_index,
            .index = node_index,
            .kind = "PROCEDURE_CALL",
            .flags = "0",
            .text = text,
            .type_text = procedureCallTypeText(callee),
            .start = start,
            .end = start + text.len,
        });

        var call_arg_indices = std.ArrayList(u32).empty;
        defer call_arg_indices.deinit(vm.allocator);
        const args_text = text[open_rel + 1 .. close_rel];
        var cursor: usize = 0;
        var depth: usize = 0;
        var segment_start: usize = 0;
        while (cursor <= args_text.len) : (cursor += 1) {
            const at_end = cursor == args_text.len;
            if (!at_end) {
                switch (args_text[cursor]) {
                    '(', '{', '[' => depth += 1,
                    ')', '}', ']' => {
                        if (depth > 0) depth -= 1;
                    },
                    ',' => {},
                    else => {},
                }
                if (args_text[cursor] != ',' or depth != 0) continue;
            }
            const segment = std.mem.trim(u8, args_text[segment_start..cursor], " \t\r\n");
            if (segment.len != 0) {
                const relative = std.mem.indexOf(u8, args_text[segment_start..cursor], segment) orelse 0;
                const expr_start = start + open_rel + 1 + segment_start + relative;
                const expr_index = try vm.appendCodeExpressionNode(tree_index, segment, expr_start, nodes, arguments);
                try call_arg_indices.append(vm.allocator, expr_index);
            }
            segment_start = cursor + 1;
        }
        nodes.items[node_index].arg_start = @intCast(arguments.items.len);
        for (call_arg_indices.items) |expr_index| try arguments.append(vm.allocator, .{ .tree = tree_index, .expression_index = expr_index });
        nodes.items[node_index].arg_count = @intCast(call_arg_indices.items.len);
        nodes.items[node_index].subexpression_start = subexpression_start;
        nodes.items[node_index].subexpression_count = nodes.items.len - subexpression_start;
        return true;
    }

    fn tryAppendBinaryExpression(vm: *VM, tree_index: u32, node_index: u32, text: []const u8, start: usize, nodes: *std.ArrayList(CodeNode), arguments: *std.ArrayList(CodeArgument)) anyerror!bool {
        const split = findTopLevelBinaryOperator(text) orelse return false;
        const subexpression_start: usize = nodes.items.len + 1;
        try nodes.append(vm.allocator, .{
            .tree = tree_index,
            .index = node_index,
            .kind = "BINARY_OPERATOR",
            .flags = "0",
            .text = text,
            .start = start,
            .end = start + text.len,
        });
        const lhs_text = std.mem.trim(u8, text[0..split.index], " \t\r\n");
        var lhs_type: []const u8 = "";
        if (lhs_text.len != 0) {
            const lhs_relative = std.mem.indexOf(u8, text[0..split.index], lhs_text) orelse 0;
            const lhs_index = try vm.appendCodeExpressionNode(tree_index, lhs_text, start + lhs_relative, nodes, arguments);
            lhs_type = nodes.items[lhs_index].type_text;
        }
        const rhs_raw_start = split.index + split.width;
        const rhs_text = std.mem.trim(u8, text[rhs_raw_start..], " \t\r\n");
        var rhs_type: []const u8 = "";
        if (rhs_text.len != 0) {
            const rhs_relative = std.mem.indexOf(u8, text[rhs_raw_start..], rhs_text) orelse 0;
            const rhs_index = try vm.appendCodeExpressionNode(tree_index, rhs_text, start + rhs_raw_start + rhs_relative, nodes, arguments);
            rhs_type = nodes.items[rhs_index].type_text;
        }
        nodes.items[node_index].subexpression_start = subexpression_start;
        nodes.items[node_index].subexpression_count = nodes.items.len - subexpression_start;
        nodes.items[node_index].type_text = binaryExpressionTypeText(text[split.index .. split.index + split.width], lhs_type, rhs_type);
        return true;
    }

    fn currentCodeNode(vm: *VM, value: RegisterValue, diag: Diagnostic, context: []const u8) !CodeNode {
        const node = switch (value) {
            .code_node => |v| v,
            else => return diag.failAt(0, "VM {s} requires a Code_Node value", .{context}),
        };
        if (node.tree >= vm.code_trees.items.len or node.index >= vm.code_trees.items[node.tree].nodes.len) return node;
        return vm.code_trees.items[node.tree].nodes[node.index];
    }

    fn updateCodeLiteralS64(vm: *VM, value: RegisterValue, new_value: i64, diag: Diagnostic) !void {
        const node = switch (value) {
            .code_node => |v| v,
            else => return diag.failAt(0, "VM Code_Literal._s64 setter requires a Code_Node value", .{}),
        };
        if (node.tree >= vm.code_trees.items.len or node.index >= vm.code_trees.items[node.tree].nodes.len) return diag.failAt(0, "VM Code_Literal._s64 setter got a detached Code_Node", .{});
        if (vm.code_trees.items[node.tree].nodes[node.index].s64 == null) return diag.failAt(0, "VM Code_Literal._s64 setter requires a numeric literal node", .{});
        vm.code_trees.items[node.tree].nodes[node.index].s64 = new_value;
    }

    fn updateCodeLiteralString(vm: *VM, value: RegisterValue, new_value: []const u8, diag: Diagnostic) !void {
        const node = switch (value) {
            .code_node => |v| v,
            else => return diag.failAt(0, "VM Code_Literal._string setter requires a Code_Node value", .{}),
        };
        if (node.tree >= vm.code_trees.items.len or node.index >= vm.code_trees.items[node.tree].nodes.len) return diag.failAt(0, "VM Code_Literal._string setter got a detached Code_Node", .{});
        if (vm.code_trees.items[node.tree].nodes[node.index].string_value == null) return diag.failAt(0, "VM Code_Literal._string setter requires a string literal node", .{});
        vm.code_trees.items[node.tree].nodes[node.index].string_value = new_value;
    }

    fn renderCodeNode(vm: *VM, node: CodeNode, diag: Diagnostic) ![]const u8 {
        if (node.tree >= vm.code_trees.items.len) return node.text;
        const tree = vm.code_trees.items[node.tree];
        const render_start = if (node.start <= node.end and node.end <= tree.source.len) node.start else 0;
        const render_end = if (node.start <= node.end and node.end <= tree.source.len) node.end else tree.source.len;
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(vm.allocator);
        var cursor: usize = render_start;
        for (tree.nodes) |literal| {
            if (!std.mem.eql(u8, literal.kind, "LITERAL") or (literal.s64 == null and literal.string_value == null)) continue;
            if (literal.start < render_start or literal.end > render_end) continue;
            if (literal.start < cursor or literal.end > tree.source.len) continue;
            try out.appendSlice(vm.allocator, tree.source[cursor..literal.start]);
            if (literal.s64) |int_value| {
                const text = try std.fmt.allocPrint(vm.allocator, "{d}", .{int_value});
                defer vm.allocator.free(text);
                try out.appendSlice(vm.allocator, text);
            } else if (literal.string_value) |string_value| {
                try vm.appendQuotedJaiString(&out, string_value);
            }
            cursor = literal.end;
        }
        try out.appendSlice(vm.allocator, tree.source[cursor..render_end]);
        _ = diag;
        const rendered = try out.toOwnedSlice(vm.allocator);
        errdefer vm.allocator.free(rendered);
        try vm.rendered_code_strings.append(vm.allocator, rendered);
        return rendered;
    }

    fn appendQuotedJaiString(vm: *VM, out: *std.ArrayList(u8), value: []const u8) !void {
        try out.append(vm.allocator, '"');
        for (value) |ch| switch (ch) {
            '\\' => try out.appendSlice(vm.allocator, "\\\\"),
            '"' => try out.appendSlice(vm.allocator, "\\\""),
            '\n' => try out.appendSlice(vm.allocator, "\\n"),
            '\r' => try out.appendSlice(vm.allocator, "\\r"),
            '\t' => try out.appendSlice(vm.allocator, "\\t"),
            else => try out.append(vm.allocator, ch),
        };
        try out.append(vm.allocator, '"');
    }

    fn codeNodeForText(vm: *VM, tree_index: u32, node_index: u32, text: []const u8, start: usize) !CodeNode {
        if (std.fmt.parseInt(i64, text, 10)) |value| {
            return .{ .tree = tree_index, .index = node_index, .kind = "LITERAL", .flags = "0", .text = text, .type_text = "int", .start = start, .end = start + text.len, .s64 = value };
        } else |_| {}
        if (isFloatLiteralText(text)) {
            return .{ .tree = tree_index, .index = node_index, .kind = "LITERAL", .flags = "0", .text = text, .type_text = "float64", .start = start, .end = start + text.len };
        }
        if (text.len >= 2 and ((text[0] == '"' and text[text.len - 1] == '"') or (text[0] == '\'' and text[text.len - 1] == '\''))) {
            return .{ .tree = tree_index, .index = node_index, .kind = "LITERAL", .flags = "0", .text = text, .type_text = "string", .start = start, .end = start + text.len, .string_value = try vm.decodeCodeStringLiteralValue(text) };
        }
        if (isSimpleIdentifier(text)) {
            return .{ .tree = tree_index, .index = node_index, .kind = "IDENT", .flags = "0", .text = text, .type_text = identifierLiteralTypeText(text), .start = start, .end = start + text.len };
        }
        return .{ .tree = tree_index, .index = node_index, .kind = "EXPRESSION", .flags = "0", .text = text, .start = start, .end = start + text.len };
    }

    fn decodeCodeStringLiteralValue(vm: *VM, literal: []const u8) ![]const u8 {
        const decoded = try decodeJaiStringLiteralValue(vm.allocator, literal);
        errdefer vm.allocator.free(decoded);
        try vm.rendered_code_strings.append(vm.allocator, decoded);
        return decoded;
    }

    fn pointerKey(ptr: Pointer) u64 {
        return (@as(u64, ptr.block) << 32) | @as(u64, @intCast(@min(ptr.offset, std.math.maxInt(u32))));
    }

    fn builderInit(vm: *VM, slot: Pointer) !void {
        const key = pointerKey(slot);
        if (vm.string_builders.getPtr(key)) |builder| builder.clearRetainingCapacity() else try vm.string_builders.put(vm.allocator, key, .empty);
    }

    fn builderFree(vm: *VM, slot: Pointer) !void {
        const key = pointerKey(slot);
        if (vm.string_builders.fetchRemove(key)) |entry| {
            var builder = entry.value;
            builder.deinit(vm.allocator);
        }
    }

    fn ensureBuilder(vm: *VM, slot: Pointer) !*std.ArrayList(u8) {
        const key = pointerKey(slot);
        const gop = try vm.string_builders.getOrPut(vm.allocator, key);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        return gop.value_ptr;
    }

    fn builderAppendValue(vm: *VM, slot: Pointer, value: RegisterValue, diag: Diagnostic) !void {
        const builder = try vm.ensureBuilder(slot);
        switch (value) {
            .string => |text| try builder.appendSlice(vm.allocator, text),
            .bytes => |bytes| try builder.appendSlice(vm.allocator, bytes),
            .code => |code| try builder.appendSlice(vm.allocator, code.text),
            .code_node => |node| try vm.builderAppendCodeText(builder, try vm.renderCodeNode(node, diag)),
            .code_note => |note| try builder.appendSlice(vm.allocator, note.text),
            .code_nodes, .code_notes, .code_args => return diag.failAt(0, "VM cannot append a compiler meta array to a String_Builder without indexing it", .{}),
            .code_arg => return diag.failAt(0, "VM cannot append a Code_Argument directly; append its expression", .{}),
            .message => |index| {
                if (index >= vm.compiler_messages.items.len) return diag.failAt(0, "VM Message handle out of range", .{});
                const message = vm.compiler_messages.items[index];
                const text = try std.fmt.allocPrint(vm.allocator, "{{{s}, {d}}}", .{ message.kind, message.workspace });
                defer vm.allocator.free(text);
                try builder.appendSlice(vm.allocator, text);
            },
            .source_location => |loc| {
                const text = try std.fmt.allocPrint(vm.allocator, "{s}:{d}", .{ loc.fully_pathed_filename, loc.line_number });
                defer vm.allocator.free(text);
                try builder.appendSlice(vm.allocator, text);
            },
            .calendar => |calendar| try builder.appendSlice(vm.allocator, try vm.calendarToString(calendar)),
            .build_options => |index| try vm.builderAppendBuildOptions(builder, index, diag),
            .build_llvm_options => |index| try vm.builderAppendBuildOptions(builder, index, diag),
            .ptr => |ptr| try builder.appendSlice(vm.allocator, try vm.readRemainingBytes(ptr, diag)),
            .int => |int_value| {
                const text = try std.fmt.allocPrint(vm.allocator, "{d}", .{int_value});
                defer vm.allocator.free(text);
                try builder.appendSlice(vm.allocator, text);
            },
            .float => |float_value| {
                const text = try std.fmt.allocPrint(vm.allocator, "{d}", .{float_value});
                defer vm.allocator.free(text);
                try builder.appendSlice(vm.allocator, text);
            },
            .bool => |bool_value| try builder.appendSlice(vm.allocator, if (bool_value) "true" else "false"),
            .type_id => |type_id| try builder.appendSlice(vm.allocator, typeName(type_id)),
            .type_text => |type_text| try builder.appendSlice(vm.allocator, type_text),
            .type_info_member => |member| try builder.appendSlice(vm.allocator, member.name),
            .tuple => return diag.failAt(0, "VM cannot append an undestructured multi-return value to a String_Builder", .{}),
            .empty => return diag.failAt(0, "VM cannot append an uninitialized value to a String_Builder", .{}),
        }
    }

    fn builderAppendFormat(vm: *VM, slot: Pointer, fmt: []const u8, regs: []const RegisterValue, arg_regs: []const Bytecode.Register, diag: Diagnostic) !void {
        var start: usize = 0;
        var arg_index: usize = 0;
        var i: usize = 0;
        while (i < fmt.len) : (i += 1) {
            if (fmt[i] != '%') continue;
            if (i > 0 and fmt[i - 1] == '\\') {
                if (start < i - 1) try (try vm.ensureBuilder(slot)).appendSlice(vm.allocator, fmt[start .. i - 1]);
                try (try vm.ensureBuilder(slot)).append(vm.allocator, '%');
                start = i + 1;
                continue;
            }
            if (i + 1 < fmt.len and fmt[i + 1] == '%') {
                try (try vm.ensureBuilder(slot)).appendSlice(vm.allocator, fmt[start .. i + 1]);
                i += 1;
                start = i + 1;
                continue;
            }
            if (start < i) try (try vm.ensureBuilder(slot)).appendSlice(vm.allocator, fmt[start..i]);
            var selected_arg_index = arg_index;
            var next_start = i + 1;
            if (i + 1 < fmt.len and fmt[i + 1] >= '1' and fmt[i + 1] <= '9') {
                selected_arg_index = fmt[i + 1] - '1';
                next_start = i + 2;
            } else {
                arg_index += 1;
            }
            if (selected_arg_index >= arg_regs.len) return diag.failAt(0, "VM string_builder_append_format argument index out of range", .{});
            const reg = arg_regs[selected_arg_index];
            if (reg >= regs.len) return diag.failAt(0, "VM string_builder_append_format argument register out of range", .{});
            try vm.builderAppendValue(slot, regs[reg], diag);
            if (next_start + 1 < fmt.len and fmt[next_start] == ' ' and fmt[next_start + 1] == '\n') {
                start = next_start + 1;
            } else {
                start = next_start;
            }
        }
        if (start < fmt.len) try (try vm.ensureBuilder(slot)).appendSlice(vm.allocator, fmt[start..]);
    }

    fn builderString(vm: *VM, slot: Pointer) ![]const u8 {
        const builder = try vm.ensureBuilder(slot);
        const owned = try vm.allocator.dupe(u8, builder.items);
        errdefer vm.allocator.free(owned);
        try vm.rendered_code_strings.append(vm.allocator, owned);
        return owned;
    }

    fn builderAppendCodeText(vm: *VM, builder: *std.ArrayList(u8), text: []const u8) !void {
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            try builder.append(vm.allocator, text[i]);
            if (text[i] == ',') {
                const next = i + 1;
                if (next < text.len and !std.ascii.isWhitespace(text[next])) try builder.append(vm.allocator, ' ');
            }
        }
    }

    fn builderAppendBuildOptions(vm: *VM, builder: *std.ArrayList(u8), index: usize, diag: Diagnostic) !void {
        if (index >= vm.build_options.items.len) return diag.failAt(0, "VM Build_Options handle out of range", .{});
        const options = vm.build_options.items[index];
        const prefix = try std.fmt.allocPrint(
            vm.allocator,
            "{{ output_type = {s}; backend = {s}; output_executable_name = \"{s}\"; output_path = \"{s}\"; intermediate_path = \"{s}\"; write_added_strings = {s}; stack_trace = {s}; backtrace_on_crash = {s}; array_bounds_check = {s}; cast_bounds_check = {s}; null_pointer_check = {s}; enable_bytecode_inliner = {s}; runtime_storageless_type_info = {s}; use_custom_link_command = {s}; import_path = ",
            .{ options.output_type, options.backend, options.output_executable_name, options.output_path, options.intermediate_path, if (options.write_added_strings) "true" else "false", if (options.stack_trace) "true" else "false", options.backtrace_on_crash, options.array_bounds_check, options.cast_bounds_check, options.null_pointer_check, if (options.enable_bytecode_inliner) "true" else "false", if (options.runtime_storageless_type_info) "true" else "false", if (options.use_custom_link_command) "true" else "false" },
        );
        defer vm.allocator.free(prefix);
        try builder.appendSlice(vm.allocator, prefix);
        try vm.builderAppendDynamicArray(builder, vm.dynamicArrayIndexForPointer(try vm.buildOptionsImportPath(index, diag)) orelse return diag.failAt(0, "Build_Options.import_path allocation failed", .{}), diag);
        try builder.appendSlice(vm.allocator, "; }");
    }

    fn builderAppendDynamicArray(vm: *VM, builder: *std.ArrayList(u8), array_index: usize, diag: Diagnostic) !void {
        try builder.append(vm.allocator, '[');
        for (vm.dynamic_arrays.items[array_index].elems.items, 0..) |item, i| {
            if (i != 0) try builder.appendSlice(vm.allocator, ", ");
            switch (item) {
                .string => |text| try appendFormatted(vm.allocator, builder, "\"{s}\"", .{text}),
                .bytes => |bytes| try appendFormatted(vm.allocator, builder, "\"{s}\"", .{bytes}),
                .int => |int_value| try appendFormatted(vm.allocator, builder, "{d}", .{int_value}),
                .float => |float_value| try appendFormatted(vm.allocator, builder, "{d}", .{float_value}),
                .bool => |bool_value| try builder.appendSlice(vm.allocator, if (bool_value) "true" else "false"),
                else => return diag.failAt(0, "VM cannot append {s} dynamic-array element to Build_Options string", .{@tagName(item)}),
            }
        }
        try builder.append(vm.allocator, ']');
    }
};

fn appendFormatted(allocator: std.mem.Allocator, builder: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try builder.appendSlice(allocator, text);
}

fn decodeJaiStringLiteralValue(allocator: std.mem.Allocator, literal: []const u8) ![]const u8 {
    if (literal.len < 2) return try allocator.dupe(u8, "");
    const body = literal[1 .. literal.len - 1];
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        if (body[i] != '\\' or i + 1 >= body.len) {
            try out.append(allocator, body[i]);
            continue;
        }
        i += 1;
        try out.append(allocator, switch (body[i]) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '\\' => '\\',
            '"' => '"',
            '\'' => '\'',
            '0' => 0,
            else => body[i],
        });
    }
    return try out.toOwnedSlice(allocator);
}

fn isSimpleIdentifier(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!std.ascii.isAlphabetic(text[0]) and text[0] != '_') return false;
    for (text[1..]) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') return false;
    }
    return true;
}

fn matchingCloseParen(text: []const u8, open_index: usize) ?usize {
    var depth: usize = 0;
    var i = open_index;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '(' => depth += 1,
            ')' => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0) return i;
            },
            '"' => {
                i += 1;
                while (i < text.len) : (i += 1) {
                    if (text[i] == '\\' and i + 1 < text.len) {
                        i += 1;
                        continue;
                    }
                    if (text[i] == '"') break;
                }
            },
            else => {},
        }
    }
    return null;
}

fn matchingCloseBrace(text: []const u8, open_index: usize) ?usize {
    var depth: usize = 0;
    var i = open_index;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '{' => depth += 1,
            '}' => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0) return i;
            },
            '"' => {
                i += 1;
                while (i < text.len) : (i += 1) {
                    if (text[i] == '\\' and i + 1 < text.len) {
                        i += 1;
                        continue;
                    }
                    if (text[i] == '"') break;
                }
            },
            else => {},
        }
    }
    return null;
}

fn startsWithKeyword(text: []const u8, keyword: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, keyword)) return false;
    if (trimmed.len == keyword.len) return true;
    return !isMetaIdentContinue(trimmed[keyword.len]);
}

fn isMetaIdentContinue(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

fn isBlockStatementText(text: []const u8) bool {
    return startsWithKeyword(text, "if") or startsWithKeyword(text, "while") or startsWithKeyword(text, "for");
}

fn nextNonWhitespace(text: []const u8, start: usize) usize {
    var i = start;
    while (i < text.len and std.ascii.isWhitespace(text[i])) : (i += 1) {}
    return i;
}

fn findTopLevelChar(text: []const u8, needle: u8) ?usize {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '"', '\'' => {
                const quote = text[i];
                i += 1;
                while (i < text.len) : (i += 1) {
                    if (text[i] == '\\' and i + 1 < text.len) {
                        i += 1;
                        continue;
                    }
                    if (text[i] == quote) break;
                }
            },
            '(', '[' => depth += 1,
            ')', ']' => if (depth > 0) {
                depth -= 1;
            },
            '{' => if (depth == 0 and needle == '{') {
                return i;
            } else {
                depth += 1;
            },
            '}' => if (depth > 0) {
                depth -= 1;
            },
            else => if (depth == 0 and text[i] == needle) return i,
        }
    }
    return null;
}

fn findCodeExpressionNodeForRange(nodes: []const CodeNode, start: usize, end: usize) ?u32 {
    var best: ?u32 = null;
    var best_width: usize = std.math.maxInt(usize);
    for (nodes, 0..) |node, index| {
        if (node.start < start or node.end > end or node.end <= node.start) continue;
        const width = node.end - node.start;
        const replaces = if (best) |best_index| blk: {
            const current = nodes[@intCast(best_index)];
            break :blk node.start < current.start or (node.start == current.start and width < best_width);
        } else true;
        if (replaces) {
            best = @intCast(index);
            best_width = width;
        }
    }
    return best;
}

const BinarySplit = struct {
    index: usize,
    width: usize,
};

fn findTopLevelAssignmentOperator(text: []const u8) ?BinarySplit {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '(', '{', '[' => depth += 1,
            ')', '}', ']' => {
                if (depth > 0) depth -= 1;
            },
            '"' => {
                i += 1;
                while (i < text.len) : (i += 1) {
                    if (text[i] == '\\' and i + 1 < text.len) {
                        i += 1;
                        continue;
                    }
                    if (text[i] == '"') break;
                }
            },
            '=' => if (depth == 0) {
                if (i > 0) switch (text[i - 1]) {
                    '=', '!', '<', '>' => continue,
                    '+', '-', '*', '/', '%', '&', '|', '^' => return .{ .index = i - 1, .width = 2 },
                    else => {},
                };
                if (i + 1 < text.len and text[i + 1] == '=') continue;
                return .{ .index = i, .width = 1 };
            },
            else => {},
        }
    }
    return null;
}

fn findTopLevelBinaryOperator(text: []const u8) ?BinarySplit {
    var best: ?BinarySplit = null;
    var best_precedence: u8 = 0;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '(', '{', '[' => depth += 1,
            ')', '}', ']' => {
                if (depth > 0) depth -= 1;
            },
            '"' => {
                i += 1;
                while (i < text.len) : (i += 1) {
                    if (text[i] == '\\' and i + 1 < text.len) {
                        i += 1;
                        continue;
                    }
                    if (text[i] == '"') break;
                }
            },
            '|', '&', '=', '!', '<', '>' => if (depth == 0 and i != 0) {
                if (i + 1 < text.len) {
                    const pair = text[i .. i + 2];
                    if (std.mem.eql(u8, pair, "||")) {
                        noteBinaryCandidate(&best, &best_precedence, i, 2, 1);
                        i += 1;
                    } else if (std.mem.eql(u8, pair, "&&")) {
                        noteBinaryCandidate(&best, &best_precedence, i, 2, 2);
                        i += 1;
                    } else if (std.mem.eql(u8, pair, "==") or std.mem.eql(u8, pair, "!=") or std.mem.eql(u8, pair, "<=") or std.mem.eql(u8, pair, ">=")) {
                        noteBinaryCandidate(&best, &best_precedence, i, 2, 3);
                        i += 1;
                    } else if (text[i] == '<' or text[i] == '>') {
                        noteBinaryCandidate(&best, &best_precedence, i, 1, 3);
                    }
                } else if (text[i] == '<' or text[i] == '>') {
                    noteBinaryCandidate(&best, &best_precedence, i, 1, 3);
                }
            },
            '+', '-' => if (depth == 0 and i != 0) noteBinaryCandidate(&best, &best_precedence, i, 1, 4),
            '*', '/', '%' => if (depth == 0 and i != 0) noteBinaryCandidate(&best, &best_precedence, i, 1, 5),
            else => {},
        }
    }
    return best;
}

fn noteBinaryCandidate(best: *?BinarySplit, best_precedence: *u8, index: usize, width: usize, precedence: u8) void {
    if (best.* == null or precedence <= best_precedence.*) {
        best.* = .{ .index = index, .width = width };
        best_precedence.* = precedence;
    }
}

fn numericLiteralTypeText(text: []const u8) []const u8 {
    return if (isFloatLiteralText(text)) "float64" else "int";
}

fn isFloatLiteralText(text: []const u8) bool {
    if (text.len == 0) return false;
    var saw_digit = false;
    var saw_float_marker = false;
    for (text, 0..) |ch, i| switch (ch) {
        '0'...'9' => saw_digit = true,
        '.', 'e', 'E' => saw_float_marker = true,
        '+', '-' => if (i != 0 and text[i - 1] != 'e' and text[i - 1] != 'E') return false,
        '_' => {},
        else => return false,
    };
    if (!saw_digit or !saw_float_marker) return false;
    _ = std.fmt.parseFloat(f64, text) catch return false;
    return true;
}

fn identifierLiteralTypeText(text: []const u8) []const u8 {
    if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) return "bool";
    if (std.mem.eql(u8, text, "null")) return "*void";
    return "";
}

fn procedureCallTypeText(callee: []const u8) []const u8 {
    if (std.mem.eql(u8, callee, "print")) return "void";
    if (std.mem.eql(u8, callee, "type_to_string")) return "string";
    if (std.mem.eql(u8, callee, "builder_to_string")) return "string";
    if (std.mem.eql(u8, callee, "code_to_string")) return "string";
    if (std.mem.eql(u8, callee, "compiler_get_code")) return "Code";
    if (std.mem.eql(u8, callee, "compiler_get_nodes")) return "*Code_Node";
    return "";
}

fn binaryExpressionTypeText(op: []const u8, lhs_type: []const u8, rhs_type: []const u8) []const u8 {
    if (std.mem.eql(u8, op, "==") or
        std.mem.eql(u8, op, "!=") or
        std.mem.eql(u8, op, "<") or
        std.mem.eql(u8, op, "<=") or
        std.mem.eql(u8, op, ">") or
        std.mem.eql(u8, op, ">=") or
        std.mem.eql(u8, op, "&&") or
        std.mem.eql(u8, op, "||"))
    {
        return "bool";
    }
    if (std.mem.eql(u8, lhs_type, "float64") or std.mem.eql(u8, rhs_type, "float64")) return "float64";
    if (std.mem.eql(u8, lhs_type, "float32") or std.mem.eql(u8, rhs_type, "float32")) return "float32";
    if (std.mem.eql(u8, lhs_type, "string") and std.mem.eql(u8, rhs_type, "string") and std.mem.eql(u8, op, "+")) return "string";
    if (lhs_type.len != 0 and std.mem.eql(u8, lhs_type, rhs_type)) return lhs_type;
    if (isIntegerTypeText(lhs_type) and isIntegerTypeText(rhs_type)) return "int";
    return "";
}

fn isIntegerTypeText(text: []const u8) bool {
    return std.mem.eql(u8, text, "int") or
        std.mem.eql(u8, text, "s64") or
        std.mem.eql(u8, text, "s32") or
        std.mem.eql(u8, text, "s16") or
        std.mem.eql(u8, text, "s8") or
        std.mem.eql(u8, text, "u64") or
        std.mem.eql(u8, text, "u32") or
        std.mem.eql(u8, text, "u16") or
        std.mem.eql(u8, text, "u8");
}

fn numericAsFloatOrInt(value: RegisterValue, diag: Diagnostic, context: []const u8) !f64 {
    return switch (value) {
        .int => |v| @floatFromInt(v),
        .float => |v| v,
        .bool => |v| if (v) 1 else 0,
        .ptr => 1,
        .bytes => |v| if (v.len == 0) 0 else 1,
        .code => diag.failAt(0, "VM {s} cannot treat Code values as numbers", .{context}),
        .type_id => diag.failAt(0, "VM {s} cannot treat Type values as numbers", .{context}),
        .type_text => diag.failAt(0, "VM {s} cannot treat Type values as numbers", .{context}),
        .type_info_member => diag.failAt(0, "VM {s} cannot treat Type_Info member values as numbers", .{context}),
        .code_node, .code_nodes, .code_note, .code_notes, .code_arg, .code_args => diag.failAt(0, "VM {s} cannot treat compiler Code_Node values as numbers", .{context}),
        .source_location => diag.failAt(0, "VM {s} cannot treat Source_Code_Location values as numbers", .{context}),
        .calendar => diag.failAt(0, "VM {s} cannot treat Calendar values as numbers", .{context}),
        .build_options, .build_llvm_options => diag.failAt(0, "VM {s} cannot treat Build_Options values as numbers", .{context}),
        else => diag.failAt(0, "VM {s} requires numeric or bool value", .{context}),
    };
}

fn registerInt(value: RegisterValue, diag: Diagnostic, context: []const u8) !i64 {
    return switch (value) {
        .int => |v| v,
        .bool => |v| if (v) 1 else 0,
        .ptr => 1,
        else => diag.failAt(0, "VM {s} requires an integer value", .{context}),
    };
}

fn registerTruthy(value: RegisterValue, diag: Diagnostic, context: []const u8) !bool {
    return switch (value) {
        .bool => |v| v,
        .int => |v| v != 0,
        .float => |v| v != 0,
        .string => |v| v.len != 0,
        .bytes => |v| v.len != 0,
        .code => |v| v.text.len != 0,
        .code_node => true,
        .code_nodes => |v| v.len != 0,
        .code_note => true,
        .code_notes => |v| v.len != 0,
        .code_arg => true,
        .code_args => |v| v.len != 0,
        .type_text => |v| v.len != 0,
        .type_info_member => true,
        .source_location => true,
        .calendar => true,
        .build_options => true,
        .build_llvm_options => true,
        .message => true,
        .type_id => true,
        .tuple => diag.failAt(0, "VM {s} cannot coerce an undestructured multi-return value to bool", .{context}),
        .ptr => true,
        .empty => false,
    };
}

fn calendarFieldValue(calendar: CalendarValue, field_id: u32, diag: Diagnostic) !i64 {
    return switch (field_id) {
        0 => calendar.year,
        1 => calendar.month_starting_at_0,
        2 => calendar.day_of_month_starting_at_0,
        3 => calendar.day_of_week_starting_at_0,
        4 => calendar.hour,
        5 => calendar.minute,
        6 => calendar.second,
        7 => calendar.millisecond,
        8 => calendar.time_zone,
        else => diag.failAt(0, "invalid Calendar field id", .{}),
    };
}

fn registerPointer(value: RegisterValue, diag: Diagnostic, context: []const u8) !Pointer {
    return switch (value) {
        .ptr => |ptr| ptr,
        else => diag.failAt(0, "VM {s} requires pointer value", .{context}),
    };
}

fn encodePointer(ptr: Pointer) u64 {
    return (@as(u64, ptr.block) + 1) << 32 | @as(u64, @intCast(ptr.offset & 0xffffffff));
}

fn compareSortValues(lhs: RegisterValue, rhs: RegisterValue, kind: u32, diag: Diagnostic) !i32 {
    if (kind == 2) {
        const l = switch (lhs) {
            .string => |v| v,
            .bytes => |v| v,
            else => return diag.failAt(0, "VM string sort found {s} element", .{@tagName(lhs)}),
        };
        const r = switch (rhs) {
            .string => |v| v,
            .bytes => |v| v,
            else => return diag.failAt(0, "VM string sort found {s} element", .{@tagName(rhs)}),
        };
        return switch (std.mem.order(u8, l, r)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }
    const l = try numericAsFloatOrInt(lhs, diag, "sort comparison lhs");
    const r = try numericAsFloatOrInt(rhs, diag, "sort comparison rhs");
    if (l < r) return -1;
    if (l > r) return 1;
    return 0;
}

fn registerValueToValue(value: RegisterValue, diag: Diagnostic) !Value {
    return switch (value) {
        .int => |v| .{ .int = v },
        .float => |v| .{ .float = v },
        .bool => |v| .{ .bool = v },
        .string => |v| .{ .string = v },
        .bytes => |v| .{ .bytes = v },
        .code => |v| .{ .code = v },
        .type_id => |v| .{ .type_text = typeName(v) },
        .type_text => |v| .{ .type_text = v },
        .type_info_member => diag.failAt(0, "VM cannot pass Type_Info member values across procedure calls yet", .{}),
        .code_node, .code_nodes, .code_note, .code_notes, .code_arg, .code_args => diag.failAt(0, "VM cannot pass compiler Code_Node values across procedure calls yet", .{}),
        .message => diag.failAt(0, "VM cannot pass compiler Message values across procedure calls yet", .{}),
        .source_location => |v| .{ .source_location = v },
        .calendar => diag.failAt(0, "VM cannot pass Calendar across non-inlined procedure calls yet", .{}),
        .build_options, .build_llvm_options => diag.failAt(0, "VM cannot pass Build_Options across procedure calls yet", .{}),
        .ptr => diag.failAt(0, "VM cannot pass a raw compile-time pointer across procedure calls without a typed value", .{}),
        .empty => diag.failAt(0, "VM call argument register was not initialized", .{}),
    };
}

fn registerValueToRunValue(vm: *VM, value: RegisterValue, diag: Diagnostic) !Value {
    return switch (value) {
        .empty => .void,
        .int => |v| .{ .int = v },
        .float => |v| .{ .float = v },
        .bool => |v| .{ .bool = v },
        .string => |v| .{ .string = v },
        .bytes => |v| .{ .bytes = v },
        .code => |v| .{ .code = v },
        .type_id => |v| .{ .type_text = typeName(v) },
        .type_text => |v| .{ .type_text = v },
        .ptr => |ptr| .{ .bytes = try vm.readRemainingBytes(ptr, diag) },
        .type_info_member => diag.failAt(0, "expression-form #run cannot materialize Type_Info member values", .{}),
        .tuple => diag.failAt(0, "expression-form #run cannot materialize undestructured multi-return values", .{}),
        .code_node, .code_nodes, .code_note, .code_notes, .code_arg, .code_args => diag.failAt(0, "expression-form #run cannot materialize compiler Code_Node values", .{}),
        .message => diag.failAt(0, "expression-form #run cannot materialize compiler Message values", .{}),
        .source_location => |v| .{ .source_location = v },
        .calendar => diag.failAt(0, "expression-form #run cannot materialize Calendar values", .{}),
        .build_options, .build_llvm_options => diag.failAt(0, "expression-form #run cannot materialize Build_Options values", .{}),
    };
}

fn registerValueFromValue(value: Value, diag: Diagnostic) !RegisterValue {
    return switch (value) {
        .int => |v| .{ .int = v },
        .float => |v| .{ .float = v },
        .bool => |v| .{ .bool = v },
        .string => |v| .{ .string = v },
        .bytes => |v| .{ .bytes = v },
        .code => |v| .{ .code = v },
        .source_location => |v| .{ .source_location = v },
        .type_text => |v| .{ .type_text = v },
        .void => diag.failAt(0, "VM #run arguments cannot be void", .{}),
    };
}

fn registerValuesEqual(lhs: RegisterValue, rhs: RegisterValue) bool {
    return switch (lhs) {
        .empty => rhs == .empty,
        .string => |l| switch (rhs) {
            .string => |r| std.mem.eql(u8, l, r),
            else => false,
        },
        .bytes => |l| switch (rhs) {
            .bytes => |r| std.mem.eql(u8, l, r),
            else => false,
        },
        .code => |l| switch (rhs) {
            .code => |r| std.mem.eql(u8, l.text, r.text) and std.mem.eql(u8, l.path, r.path) and l.line_number == r.line_number,
            .string => |r| std.mem.eql(u8, l.text, r),
            else => false,
        },
        .ptr => |l| switch (rhs) {
            .ptr => |r| l.block == r.block and l.offset == r.offset,
            else => false,
        },
        .type_id => |l| switch (rhs) {
            .type_id => |r| l == r,
            else => false,
        },
        .type_text => |l| switch (rhs) {
            .type_text => |r| std.mem.eql(u8, l, r),
            .type_id => |r| std.mem.eql(u8, l, typeName(r)),
            else => false,
        },
        .type_info_member => |l| switch (rhs) {
            .type_info_member => |r| std.mem.eql(u8, l.name, r.name) and std.mem.eql(u8, l.type_name, r.type_name) and l.flags == r.flags,
            else => false,
        },
        .code_node => |l| switch (rhs) {
            .code_node => |r| std.mem.eql(u8, l.kind, r.kind) and std.mem.eql(u8, l.flags, r.flags) and std.mem.eql(u8, l.text, r.text),
            else => false,
        },
        .code_nodes => |l| switch (rhs) {
            .code_nodes => |r| l.ptr == r.ptr and l.len == r.len,
            else => false,
        },
        .code_note => |l| switch (rhs) {
            .code_note => |r| std.mem.eql(u8, l.text, r.text),
            else => false,
        },
        .code_notes => |l| switch (rhs) {
            .code_notes => |r| l.ptr == r.ptr and l.len == r.len,
            else => false,
        },
        .code_arg => |l| switch (rhs) {
            .code_arg => |r| l.tree == r.tree and l.expression_index == r.expression_index,
            else => false,
        },
        .code_args => |l| switch (rhs) {
            .code_args => |r| l.ptr == r.ptr and l.len == r.len,
            else => false,
        },
        .source_location => |l| switch (rhs) {
            .source_location => |r| std.mem.eql(u8, l.fully_pathed_filename, r.fully_pathed_filename) and l.line_number == r.line_number,
            else => false,
        },
        .calendar => |l| switch (rhs) {
            .calendar => |r| std.meta.eql(l, r),
            else => false,
        },
        .build_options => |l| switch (rhs) {
            .build_options => |r| l == r,
            else => false,
        },
        .message => |l| switch (rhs) {
            .message => |r| l == r,
            else => false,
        },
        .build_llvm_options => |l| switch (rhs) {
            .build_llvm_options => |r| l == r,
            else => false,
        },
        .tuple => |l| switch (rhs) {
            .tuple => |r| blk: {
                if (l.len != r.len) break :blk false;
                for (l, r) |lv, rv| if (!registerValuesEqual(lv, rv)) break :blk false;
                break :blk true;
            },
            else => false,
        },
        .int => |l| switch (rhs) {
            .int => |r| l == r,
            .float => |r| @as(f64, @floatFromInt(l)) == r,
            .bool => |r| (l != 0) == r,
            else => false,
        },
        .float => |l| switch (rhs) {
            .float => |r| l == r,
            .int => |r| l == @as(f64, @floatFromInt(r)),
            .bool => |r| (l != 0) == r,
            else => false,
        },
        .bool => |l| switch (rhs) {
            .bool => |r| l == r,
            .int => |r| l == (r != 0),
            .float => |r| l == (r != 0),
            else => false,
        },
    };
}

fn registerCodeValue(value: RegisterValue, diag: Diagnostic, context: []const u8) !CodeValue {
    return switch (value) {
        .code => |code| code,
        .string => |text| .{ .text = text },
        .bytes => |bytes| .{ .text = bytes },
        .code_node => |node| .{ .text = node.text, .path = node.path, .line_number = node.line_number },
        else => diag.failAt(0, "VM {s} requires a Code or Code_Node value", .{context}),
    };
}

fn buildOptionsEnumText(value: RegisterValue, field_name: []const u8, diag: Diagnostic) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        .bytes => |bytes| bytes,
        .int => |int_value| buildOptionsEnumTextFromInt(field_name, int_value),
        else => diag.failAt(0, "VM Build_Options.{s} requires an enum-like value", .{field_name}),
    };
}

fn optimizationModeByName(name: []const u8) ?i64 {
    if (std.mem.eql(u8, name, "DEBUG")) return 0;
    if (std.mem.eql(u8, name, "VERY_DEBUG")) return 1;
    if (std.mem.eql(u8, name, "OPTIMIZED")) return 2;
    if (std.mem.eql(u8, name, "VERY_OPTIMIZED")) return 3;
    if (std.mem.eql(u8, name, "OPTIMIZED_SMALL")) return 4;
    if (std.mem.eql(u8, name, "OPTIMIZED_VERY_SMALL")) return 5;
    return null;
}

fn buildOptionsEnumTextFromInt(field_name: []const u8, value: i64) []const u8 {
    if (std.mem.eql(u8, field_name, "backend")) {
        return switch (value) {
            0 => "LLVM",
            1 => "C",
            2 => "INTERPRETER",
            else => "UNKNOWN",
        };
    }
    if (std.mem.eql(u8, field_name, "output_type")) {
        return switch (value) {
            0 => "EXECUTABLE",
            1 => "DYNAMIC_LIBRARY",
            2 => "STATIC_LIBRARY",
            else => "UNKNOWN",
        };
    }
    if (std.mem.eql(u8, field_name, "backtrace_on_crash")) {
        return switch (value) {
            0 => "OFF",
            1 => "ON",
            else => "UNKNOWN",
        };
    }
    if (std.mem.endsWith(u8, field_name, "_check")) {
        return switch (value) {
            0 => "OFF",
            1 => "ON",
            2 => "FATAL",
            3 => "ALWAYS",
            else => "UNKNOWN",
        };
    }
    return switch (value) {
        0 => "OFF",
        1 => "ON",
        else => "UNKNOWN",
    };
}

fn typeName(type_id: u32) []const u8 {
    return switch (type_id) {
        1 => "bool",
        4 => "s32",
        5 => "int",
        7 => "u8",
        8 => "u16",
        9 => "u32",
        10 => "*void",
        12 => "float32",
        13 => "float64",
        14 => "string",
        15 => "Type",
        16 => "Any",
        30 => "procedure",
        31 => "()",
        else => "Type",
    };
}

fn truncateIntForType(value: i64, type_id: u32) i64 {
    const bits: u64 = @bitCast(value);
    return switch (type_id) {
        1 => if (value != 0) 1 else 0,
        4 => @as(i64, @as(i32, @bitCast(@as(u32, @truncate(bits))))),
        7 => @as(i64, @intCast(@as(u8, @truncate(bits)))),
        8 => @as(i64, @intCast(@as(u16, @truncate(bits)))),
        9 => @as(i64, @intCast(@as(u32, @truncate(bits)))),
        else => value,
    };
}

fn readIntLittle(bytes: []const u8) i64 {
    var buf: [8]u8 = .{0} ** 8;
    @memcpy(buf[0..bytes.len], bytes);
    return @bitCast(std.mem.readInt(u64, &buf, .little));
}
