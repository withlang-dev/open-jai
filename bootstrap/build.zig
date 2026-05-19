const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const llvm_config = llvmConfigPath(b);

    const llvm_link_flags = b.run(&.{
        llvm_config,
        // "--link-static",
        "--ldflags",
        "--libs",
        "--system-libs",
        "core",
        "target",
        "native",
        "x86",
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .stack_check = false,
    });
    configureLlvmImports(b, exe_mod, llvm_config);

    const exe_obj = b.addObject(.{
        .name = "openjai_main",
        .root_module = exe_mod,
        .use_llvm = true,
    });

    // The installed LLVM 22 static archives contain LLVM bitcode members. Zig 0.16's
    // Mach-O link path cannot consume them directly, while LLVM's own clang++/ld64.lld
    // can. Compile Zig to an object, then perform only the final LLVM-static link with
    // the matching toolchain from /usr/local/llvm.

    const link_exe = b.addSystemCommand(&.{cxxDriverPath(b, llvm_config)});
    if (target.result.os.tag == .macos) {
        const sdk_path = std.mem.trim(u8, b.run(&.{ "xcrun", "--show-sdk-path" }), " \t\r\n");
        link_exe.addArgs(&.{ "-isysroot", sdk_path });
    }
    link_exe.addArg("-fuse-ld=lld");
    link_exe.addFileArg(exe_obj.getEmittedBin());
    addTokenizedArgs(link_exe, llvm_link_flags);
    addCxxRuntimeLinkArgs(link_exe, target);
    link_exe.addArg("-o");
    const linked_exe = link_exe.addOutputFileArg("openjai-macos");
    const llvm_libdir = std.mem.trim(
        u8,
        b.run(&.{ llvm_config, "--libdir" }),
        " \t\r\n",
    );
    link_exe.addArg(b.fmt("-Wl,-rpath,{s}", .{llvm_libdir}));
    const install_exe = b.addInstallBinFile(linked_exe, "openjai-macos");
    b.getInstallStep().dependOn(&install_exe.step);

    const runtime_mod = createRuntimeModule(b, target, optimize, "rt/runtime.zig");
    const runtime_core_mod = createRuntimeModule(b, target, optimize, "rt/core.zig");
    const runtime_platform_mod = createRuntimeModule(b, target, optimize, switch (target.result.os.tag) {
        .macos => "rt/platform_darwin.zig",
        .linux => "rt/platform_linux.zig",
        else => unreachable,
    });
    const runtime_start_mod = createRuntimeModule(b, target, optimize, "rt/start_exe.zig");

    // Direct-object compatibility for --runtime path/to/openjai_runtime.o.
    // The manifest below is the canonical runtime shape.
    const runtime_obj = b.addObject(.{
        .name = "openjai_runtime",
        .root_module = runtime_mod,
        .use_llvm = true,
    });
    const install_runtime = b.addInstallFile(runtime_obj.getEmittedBin(), "lib/openjai_runtime.o");
    b.getInstallStep().dependOn(&install_runtime.step);

    const runtime_core_obj = b.addObject(.{
        .name = "openjai_rt_core",
        .root_module = runtime_core_mod,
        .use_llvm = true,
    });
    const install_runtime_core = b.addInstallFile(runtime_core_obj.getEmittedBin(), "lib/openjai_rt_core.o");
    b.getInstallStep().dependOn(&install_runtime_core.step);

    const runtime_platform_name = b.fmt("openjai_rt_platform_{s}_{s}", .{ manifestOsName(target), manifestArchName(target) });
    const runtime_platform_basename = b.fmt("{s}.o", .{runtime_platform_name});
    const runtime_platform_obj = b.addObject(.{
        .name = runtime_platform_name,
        .root_module = runtime_platform_mod,
        .use_llvm = true,
    });
    const install_runtime_platform = b.addInstallFile(runtime_platform_obj.getEmittedBin(), b.fmt("lib/{s}", .{runtime_platform_basename}));
    b.getInstallStep().dependOn(&install_runtime_platform.step);

    const runtime_start_obj = b.addObject(.{
        .name = "openjai_rt_start_exe",
        .root_module = runtime_start_mod,
        .use_llvm = true,
    });
    const install_runtime_start = b.addInstallFile(runtime_start_obj.getEmittedBin(), "lib/openjai_rt_start_exe.o");
    b.getInstallStep().dependOn(&install_runtime_start.step);

    const manifest_text = b.fmt(
        "target {s} {s}\nobject openjai_rt_start_exe.o\nobject openjai_rt_core.o\nobject {s}\n{s}",
        .{
            manifestOsName(target),
            manifestArchName(target),
            runtime_platform_basename,
            manifestSystemLibraries(target),
        },
    );
    const runtime_manifest = b.addWriteFiles();
    const manifest_file = runtime_manifest.add("openjai_runtime.manifest", manifest_text);
    const install_runtime_manifest = b.addInstallFile(manifest_file, "lib/openjai_runtime.manifest");
    b.getInstallStep().dependOn(&install_runtime_manifest.step);

    // Unit tests use a dedicated test root (test_main.zig) that imports every
    // module with test blocks except Compilation.zig, which transitively imports
    // codegen/llvm.zig and requires LLVM static libs that Zig's linker cannot
    // consume. The test binary is compiled with use_lld=false to avoid that path.
    // LLVM headers are still needed for @cImport declarations in modules that
    // reference LLVM types (even if the functions aren't called in tests).
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_main.zig"),
        .target = target,
        .optimize = optimize,
        .stack_check = false,
    });
    configureLlvmImports(b, test_mod, llvm_config);

    const unit_tests = b.addTest(.{ .root_module = test_mod, .use_llvm = true, .use_lld = false });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run bootstrap compiler unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration test runner: compiles each annotated example and checks stdout.
    const test_runner_mod = b.createModule(.{
        .root_source_file = b.path("tools/test_runner.zig"),
        .target = target,
        .optimize = optimize,
        .stack_check = false,
    });
    const test_runner_exe = b.addExecutable(.{
        .name = "test_runner",
        .root_module = test_runner_mod,
    });

    const run_test_examples = b.addRunArtifact(test_runner_exe);
    // Arg 1: path to the compiled openjai binary.
    run_test_examples.addFileArg(linked_exe);
    // Arg 2: path to the runtime object file.
    run_test_examples.addFileArg(runtime_obj.getEmittedBin());
    // Arg 3: path to the examples directory (relative to repo root, one level up from bootstrap/).
    run_test_examples.addArg(b.pathFromRoot("../examples"));
    // Forward any extra args (e.g. --filter) passed after `--` on the command line.
    if (b.args) |extra_args| run_test_examples.addArgs(extra_args);

    const test_examples_step = b.step("test-examples", "Run integration tests against examples/");
    test_examples_step.dependOn(&run_test_examples.step);

    const openjai_test_runner_mod = b.createModule(.{
        .root_source_file = b.path("src/openjai_test_runner.zig"),
        .target = target,
        .optimize = optimize,
        .stack_check = false,
    });
    const openjai_test_runner_exe = b.addExecutable(.{
        .name = "openjai_test_runner",
        .root_module = openjai_test_runner_mod,
    });

    const run_openjai_tests = b.addRunArtifact(openjai_test_runner_exe);
    run_openjai_tests.addFileArg(linked_exe);
    run_openjai_tests.addFileArg(runtime_obj.getEmittedBin());
    run_openjai_tests.addArg(b.pathFromRoot(".."));
    if (b.args) |extra_args| run_openjai_tests.addArgs(extra_args);

    const test_jai_step = b.step("test-jai", "Run Jai-native OpenJai test framework");
    test_jai_step.dependOn(&run_openjai_tests.step);
}

fn configureLlvmImports(b: *std.Build, mod: *std.Build.Module, llvm_config: []const u8) void {
    // this runs multiple times, but llvm's include path probably doesnt change between runs
    mod.addIncludePath(.{ .cwd_relative = (std.mem.trim(
        u8,
        b.run(&.{ llvm_config, "--includedir" }),
        " \t\r\n",
    )) });
    mod.link_libc = true;
}

fn llvmConfigPath(b: *std.Build) []const u8 {
    if (b.option([]const u8, "llvm-config", "Path to llvm-config")) |value| return value;
    if (b.graph.environ_map.get("LLVM_CONFIG")) |value| return value;
    return "llvm-config";
}

fn cxxDriverPath(b: *std.Build, llvm_config: []const u8) []const u8 {
    if (b.option([]const u8, "cxx", "C++ linker driver for the bootstrap compiler")) |value| return value;
    if (b.graph.environ_map.get("OPENJAI_CXX")) |value| return value;
    if (b.graph.environ_map.get("CXX")) |value| return value;

    const llvm_bindir = std.mem.trim(u8, b.run(&.{ llvm_config, "--bindir" }), " \t\r\n");
    return b.pathJoin(&.{ llvm_bindir, "clang++" });
}

fn manifestOsName(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        .macos => "darwin",
        .linux => "linux",
        .windows => "windows",
        else => @tagName(target.result.os.tag),
    };
}

fn manifestArchName(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.cpu.arch) {
        .aarch64 => "aarch64",
        .x86_64 => "x86_64",
        else => @tagName(target.result.cpu.arch),
    };
}

fn manifestSystemLibraries(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        .macos => "system_library System\n",
        else => "",
    };
}

fn addCxxRuntimeLinkArgs(run: *std.Build.Step.Run, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .macos => run.addArgs(&.{ "-lc++", "-lc++abi" }),
        else => {},
    }
}

fn createRuntimeModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, root_source_file: []const u8) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
        .stack_check = false,
    });
    mod.link_libc = true;
    return mod;
}

fn addTokenizedArgs(run: *std.Build.Step.Run, args: []const u8) void {
    var it = std.mem.tokenizeAny(u8, args, " \t\r\n");
    while (it.next()) |arg| run.addArg(arg);
}
