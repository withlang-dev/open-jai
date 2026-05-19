const std = @import("std");
const Compilation = @import("Compilation.zig").Compilation;
const Options = @import("Compilation.zig").Options;

const version_text = "OpenJai 0.1.0 (open source implementation of Jai)\n";

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const options = parseArgs(allocator, init.minimal) catch |err| switch (err) {
        error.InvalidArguments => std.process.exit(64),
        else => return err,
    };
    defer allocator.free(options.command_line);
    defer allocator.free(options.output_path);
    defer allocator.free(options.runtime_path);
    defer allocator.free(options.import_dirs);
    defer allocator.free(options.plugins);
    defer allocator.free(options.add_codes);
    defer allocator.free(options.run_codes);

    var comp = Compilation.init(allocator, init.io, options);
    comp.compile() catch std.process.exit(1);
}

fn parseArgs(allocator: std.mem.Allocator, init: std.process.Init.Minimal) !Options {
    var args = std.process.Args.Iterator.init(init.args);

    var raw_args = std.ArrayList([]const u8).empty;
    defer raw_args.deinit(allocator);
    while (args.next()) |arg| try raw_args.append(allocator, arg);

    if (raw_args.items.len < 2) {
        std.debug.print("openjai: no input file specified. Use -help for usage information.\n", .{});
        std.process.exit(1);
    }

    var compile_time_command_line = std.ArrayList([]const u8).empty;
    errdefer compile_time_command_line.deinit(allocator);
    try compile_time_command_line.append(allocator, raw_args.items[0]);

    var import_dirs = std.ArrayList([]const u8).empty;
    errdefer import_dirs.deinit(allocator);
    var plugins = std.ArrayList([]const u8).empty;
    errdefer plugins.deinit(allocator);

    var input_files = std.ArrayList([]const u8).empty;
    defer input_files.deinit(allocator);
    var output_path: []const u8 = "out/a.out";
    var runtime_path: []const u8 = "zig-out/lib/openjai_runtime.manifest";
    var check_only = false;
    var add_codes = std.ArrayList([]const u8).empty;
    errdefer add_codes.deinit(allocator);
    var context_size: ?u32 = null;
    var opt_debugger = false;
    var debug_for = false;
    var use_llvm = true;
    var msvc_format = false;
    var natvis = false;
    var no_backtrace_on_crash = false;
    var no_color = false;
    var no_dce = false;
    var no_split = false;
    var no_cwd = false;
    var no_check = false;
    var no_check_bindings = false;
    var no_inline = false;
    var output_dir: ?[]const u8 = null;
    var quiet = false;
    var release = false;
    var release_debug = false;
    var report_poly = false;
    var run_codes = std.ArrayList([]const u8).empty;
    errdefer run_codes.deinit(allocator);
    var verbose = false;
    var very_debug = false;
    var use_x64 = false;

    var i: usize = 1;
    while (i < raw_args.items.len) : (i += 1) {
        const arg = raw_args.items[i];

        // Single `-` is the metaprogram argument separator.
        if (std.mem.eql(u8, arg, "-")) {
            i += 1;
            while (i < raw_args.items.len) : (i += 1) try compile_time_command_line.append(allocator, raw_args.items[i]);
            break;
        }

        // `--` or `---` introduces developer/front-end options.
        if (std.mem.eql(u8, arg, "--") or std.mem.eql(u8, arg, "---")) {
            i += 1;
            while (i < raw_args.items.len) : (i += 1) {
                const dev_arg = raw_args.items[i];
                if (std.mem.eql(u8, dev_arg, "help")) {
                    std.debug.print("Developer options: import_dir name, meta metaprogram_name, no_jobs, randomize, seed some_number, extra, chaos.\n", .{});
                    std.process.exit(0);
                } else if (std.mem.eql(u8, dev_arg, "import_dir")) {
                    i += 1;
                    if (i >= raw_args.items.len) {
                        std.debug.print("openjai: error: expected directory after -- import_dir\n", .{});
                        return error.InvalidArguments;
                    }
                    try import_dirs.append(allocator, raw_args.items[i]);
                } else if (std.mem.eql(u8, dev_arg, "meta")) {
                    i += 1;
                    if (i >= raw_args.items.len) {
                        std.debug.print("openjai: error: expected metaprogram name after -- meta\n", .{});
                        return error.InvalidArguments;
                    }
                    // Accepted, no-op for now (always uses Default_Metaprogram).
                } else if (std.mem.eql(u8, dev_arg, "no_jobs")) {
                    // Accepted, no-op for now.
                } else {
                    std.debug.print("openjai: unrecognized developer option '{s}'. Use '-- help' for available options.\n", .{dev_arg});
                    std.process.exit(1);
                }
            }
            break;
        }

        // Non-flag argument is an input file.
        if (arg.len == 0 or arg[0] != '-') {
            try input_files.append(allocator, arg);
            try compile_time_command_line.append(allocator, arg);
            continue;
        }

        // Flags:
        if (std.mem.eql(u8, arg, "-version")) {
            printVersion();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-help") or std.mem.eql(u8, arg, "-?")) {
            usage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-check")) {
            check_only = true;
        } else if (std.mem.eql(u8, arg, "-exe")) {
            i += 1;
            if (i >= raw_args.items.len) {
                std.debug.print("openjai: error: expected name after {s}\n", .{arg});
                return error.InvalidArguments;
            }
            output_path = raw_args.items[i];
        } else if (std.mem.eql(u8, arg, "-runtime")) {
            i += 1;
            if (i >= raw_args.items.len) {
                std.debug.print("openjai: error: expected path after {s}\n", .{arg});
                return error.InvalidArguments;
            }
            runtime_path = raw_args.items[i];
        } else if (std.mem.eql(u8, arg, "-add")) {
            i += 1;
            if (i >= raw_args.items.len) {
                std.debug.print("openjai: error: expected code after -add\n", .{});
                return error.InvalidArguments;
            }
            try add_codes.append(allocator, raw_args.items[i]);
        } else if (std.mem.eql(u8, arg, "-context_size")) {
            i += 1;
            if (i >= raw_args.items.len) {
                std.debug.print("openjai: error: expected number after -context_size\n", .{});
                return error.InvalidArguments;
            }
            context_size = std.fmt.parseInt(u32, raw_args.items[i], 10) catch {
                std.debug.print("openjai: error: invalid context_size '{s}'\n", .{raw_args.items[i]});
                return error.InvalidArguments;
            };
        } else if (std.mem.eql(u8, arg, "-debugger")) {
            opt_debugger = true;
        } else if (std.mem.eql(u8, arg, "-debug_for")) {
            debug_for = true;
        } else if (std.mem.eql(u8, arg, "-import_dir")) {
            i += 1;
            if (i >= raw_args.items.len) {
                std.debug.print("openjai: error: expected directory after -import_dir\n", .{});
                return error.InvalidArguments;
            }
            try import_dirs.append(allocator, raw_args.items[i]);
        } else if (std.mem.eql(u8, arg, "-llvm")) {
            use_llvm = true;
        } else if (std.mem.eql(u8, arg, "-msvc_format")) {
            msvc_format = true;
        } else if (std.mem.eql(u8, arg, "-natvis")) {
            natvis = true;
        } else if (std.mem.eql(u8, arg, "-no_backtrace_on_crash")) {
            no_backtrace_on_crash = true;
        } else if (std.mem.eql(u8, arg, "-no_color")) {
            no_color = true;
        } else if (std.mem.eql(u8, arg, "-no_dce")) {
            no_dce = true;
        } else if (std.mem.eql(u8, arg, "-no_split")) {
            no_split = true;
        } else if (std.mem.eql(u8, arg, "-no_cwd")) {
            no_cwd = true;
        } else if (std.mem.eql(u8, arg, "-no_check")) {
            no_check = true;
        } else if (std.mem.eql(u8, arg, "-no_check_bindings")) {
            no_check_bindings = true;
        } else if (std.mem.eql(u8, arg, "-no_inline")) {
            no_inline = true;
        } else if (std.mem.eql(u8, arg, "-output_path")) {
            i += 1;
            if (i >= raw_args.items.len) {
                std.debug.print("openjai: error: expected path after -output_path\n", .{});
                return error.InvalidArguments;
            }
            output_dir = raw_args.items[i];
        } else if (std.mem.eql(u8, arg, "-plug") or std.mem.eql(u8, arg, "-plugin")) {
            i += 1;
            if (i >= raw_args.items.len) {
                std.debug.print("openjai: error: expected module name after -plug\n", .{});
                return error.InvalidArguments;
            }
            try plugins.append(allocator, raw_args.items[i]);
        } else if (std.mem.eql(u8, arg, "-quiet")) {
            quiet = true;
        } else if (std.mem.eql(u8, arg, "-release")) {
            release = true;
        } else if (std.mem.eql(u8, arg, "-release_debug")) {
            release_debug = true;
        } else if (std.mem.eql(u8, arg, "-report_poly")) {
            report_poly = true;
        } else if (std.mem.eql(u8, arg, "-run")) {
            i += 1;
            if (i >= raw_args.items.len) {
                std.debug.print("openjai: error: expected code after -run\n", .{});
                return error.InvalidArguments;
            }
            try run_codes.append(allocator, raw_args.items[i]);
        } else if (std.mem.eql(u8, arg, "-verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-very_debug")) {
            very_debug = true;
        } else if (std.mem.eql(u8, arg, "-x64")) {
            use_x64 = true;
            use_llvm = false;
        } else {
            std.debug.print("openjai: unrecognized option '{s}'. Use -help for usage information.\n", .{arg});
            std.process.exit(1);
        }
    }

    if (input_files.items.len == 0) {
        std.debug.print("openjai: no input file specified. Use -help for usage information.\n", .{});
        std.process.exit(1);
    }
    const resolved_input = input_files.items[0];

    const owned_output_path = if (output_dir != null and std.mem.eql(u8, output_path, "out/a.out")) blk: {
        const stem = std.fs.path.stem(std.fs.path.basename(resolved_input));
        break :blk try std.fs.path.join(allocator, &.{ output_dir.?, stem });
    } else try allocator.dupe(u8, output_path);

    return .{
        .input_path = resolved_input,
        .output_path = owned_output_path,
        .runtime_path = try allocator.dupe(u8, runtime_path),
        .check_only = check_only,
        .command_line = try compile_time_command_line.toOwnedSlice(allocator),
        .add_codes = try add_codes.toOwnedSlice(allocator),
        .context_size = context_size,
        .debugger = opt_debugger,
        .debug_for = debug_for,
        .import_dirs = try import_dirs.toOwnedSlice(allocator),
        .use_llvm = use_llvm,
        .msvc_format = msvc_format,
        .natvis = natvis,
        .no_backtrace_on_crash = no_backtrace_on_crash,
        .no_color = no_color,
        .no_dce = no_dce,
        .no_split = no_split,
        .no_cwd = no_cwd,
        .no_check = no_check,
        .no_check_bindings = no_check_bindings,
        .no_inline = no_inline,
        .output_dir = output_dir,
        .plugins = try plugins.toOwnedSlice(allocator),
        .quiet = quiet,
        .release = release,
        .release_debug = release_debug,
        .report_poly = report_poly,
        .run_codes = try run_codes.toOwnedSlice(allocator),
        .verbose = verbose,
        .very_debug = very_debug,
        .use_x64 = use_x64,
    };
}

fn usage() void {
    std.debug.print(
        \\Available Command-Line Arguments:
        \\
        \\-add arg         Add the string 'arg' to the target program as code.
        \\                 Example: -add "MY_VARIABLE :: 42";
        \\-check           Compile and check without producing an executable (OpenJai extension).
        \\-context_size n  Set the size of #Context, in bytes.
        \\                 Example: -context_size 2048
        \\-debugger        If there is a crash in compile-time execution, drop into the interactive debugger.
        \\-debug_for       Enable debugging of for_expansion macros.
        \\-exe name        Set output_executable_name on the target workspace to 'name'.
        \\-import_dir arg  Add this directory to the list of directories searched by #import. Can be
        \\                     used multiple times.
        \\-llvm            Use the LLVM backend by default (unless overridden by a metaprogram).
        \\-msvc_format     Use Visual Studio's message format for error messages.
        \\-natvis          Use natvis compatible type names in debug info (array<T> instead of [] T, etc).
        \\-no_backtrace_on_crash    Do not catch OS-level exceptions and print a stack trace when your program crashes.
        \\                     Causes less code to be imported on startup.
        \\-no_color        Disable ANSI terminal coloring in output messages.
        \\-no_dce          Turn off dead code elimination. This is a temporary option.
        \\-no_split        Disable split modules when compiling with the LLVM backend.
        \\-no_cwd          Turn off the compiler's initial change of working directory. This is a temporary option.
        \\-no_check        Do not import modules/Check and run it on the code.
        \\-no_check_bindings Disable checking of module bindings when running modules/Check.
        \\-no_inline       Disable inlining throughout the program (useful when debugging).
        \\-output_path     Set the path where your output files (such as the executable) will go.
        \\-plug name       Import module 'name' into the metaprogram and use it as a plugin.
        \\-quiet           Run the compiler in quiet mode (not outputting unnecessary text).
        \\-release         Build a release build, i.e., tell the default metaprogram to disable stack traces and enable optimizations.
        \\-release_debug   Build a release build with less optimization and user-level stack traces.
        \\-report_poly     Print the Polymorph Report when compilation is done.
        \\-run arg         Start a #run directive that parses and runs 'arg' as code.
        \\                     Example: -run write_string(\"Hello!\n\")
        \\-runtime path    Set runtime object/manifest path (OpenJai-specific).
        \\-verbose         Output some extra information about what this metaprogram is doing.
        \\-version         Print the version of the compiler.
        \\-very_debug      Build a very_debug build, i.e. add more debugging facilities than usual.
        \\-x64             Use the x64 backend by default (unless overridden by a metaprogram).
        \\
        \\-                Every argument after - is ignored by the compiler itself,
        \\                     and is passed to the user-level metaprogram for its own use.
        \\
        \\Any argument not starting with a -, and before a - by itself, is the name of a file to compile.
        \\
        \\Example:    openjai -x64 program.jai - info for -the compile_time execution
        \\
    , .{});
}

fn printVersion() void {
    std.debug.print("{s}", .{version_text});
}

test "argument parser module loads" {
    try std.testing.expect(true);
}
