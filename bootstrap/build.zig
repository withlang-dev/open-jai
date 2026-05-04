const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk_path = std.mem.trim(u8, b.run(&.{ "xcrun", "--show-sdk-path" }), " \t\r\n");
    const llvm_link_flags = b.run(&.{
        "/usr/local/llvm/bin/llvm-config",
        "--link-static",
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
    });
    configureLlvmImports(exe_mod);

    const exe_obj = b.addObject(.{
        .name = "openjai_main",
        .root_module = exe_mod,
        .use_llvm = true,
    });

    // The installed LLVM 22 static archives contain LLVM bitcode members. Zig 0.16's
    // Mach-O link path cannot consume them directly, while LLVM's own clang++/ld64.lld
    // can. Compile Zig to an object, then perform only the final LLVM-static link with
    // the matching toolchain from /usr/local/llvm.
    const link_exe = b.addSystemCommand(&.{
        "/usr/local/llvm/bin/clang++",
        "-isysroot",
        sdk_path,
        "-fuse-ld=lld",
    });
    link_exe.addFileArg(exe_obj.getEmittedBin());
    addTokenizedArgs(link_exe, llvm_link_flags);
    link_exe.addArg("-o");
    const linked_exe = link_exe.addOutputFileArg("openjai");
    link_exe.addArgs(&.{
        "-lc++",
        "-lc++abi",
        "-Wl,-rpath,/usr/local/llvm/lib",
    });
    const install_exe = b.addInstallBinFile(linked_exe, "openjai");
    b.getInstallStep().dependOn(&install_exe.step);

    const runtime_mod = b.createModule(.{
        .root_source_file = b.path("lib/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_mod.link_libc = true;

    const runtime_obj = b.addObject(.{
        .name = "openjai_runtime",
        .root_module = runtime_mod,
        .use_llvm = true,
    });
    const install_runtime = b.addInstallFile(runtime_obj.getEmittedBin(), "lib/openjai_runtime.o");
    b.getInstallStep().dependOn(&install_runtime.step);

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
    });
    configureLlvmImports(test_mod);

    const unit_tests = b.addTest(.{ .root_module = test_mod, .use_llvm = true, .use_lld = false });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run bootstrap compiler unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration test runner: compiles each annotated example and checks stdout.
    const test_runner_mod = b.createModule(.{
        .root_source_file = b.path("tools/test_runner.zig"),
        .target = target,
        .optimize = optimize,
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
}

fn configureLlvmImports(mod: *std.Build.Module) void {
    mod.addIncludePath(.{ .cwd_relative = "/usr/local/llvm/include" });
    mod.link_libc = true;
}

fn addTokenizedArgs(run: *std.Build.Step.Run, args: []const u8) void {
    var it = std.mem.tokenizeAny(u8, args, " \t\r\n");
    while (it.next()) |arg| run.addArg(arg);
}
