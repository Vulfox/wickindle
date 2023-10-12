const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    //const lib = b.addStaticLibrary(.{
    const lib = b.addExecutable(.{
        .name = "wickindle",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // TODO: go back to module once fix is in place for iocp socket errors
    //const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    //lib.addModule("xev", xev.module("xev"));
    _ = lib.addAnonymousModule("xev", .{
        .source_file = .{ .path = "libxev/src/main.zig" },
    });
    // const xev_dep = b.anonymousDependency("xev", @import("libxev/build.zig"), .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // lib.linkLibrary(xev_dep.artifact("xev"));

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    _ = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    //_ = b.addRunArtifact(main_tests);

    const test_exe = std.Build.Step.Compile.create(b, .{
        .name = "test",
        .root_source_file = .{ .path = "src/main.zig" },

        .target = target,
        .optimize = .Debug,
        .kind = .@"test",
    });
    // test_exe.linkLibrary(lib);
    //test_exe.addModule("xev", xev.module("xev"));

    // run exe
    const run_cmd = b.addRunArtifact(lib);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    // end run exe

    //b.installArtifact(test_exe);
    const inst_test_exe = b.addInstallArtifact(test_exe, .{});
    const run_main_tests = b.addRunArtifact(test_exe);
    run_main_tests.step.dependOn(&inst_test_exe.step);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
