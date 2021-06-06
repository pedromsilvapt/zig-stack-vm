const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const version = b.version(1, 0, 0);

    // Replaced `version` with `.unversioned` to temporarily work around a bug
    // tracked by https://github.com/ziglang/zig/issues/9013
    const lib = b.addSharedLibrary("libstackvm", "src/lib.zig", .unversioned);
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.addPackagePath("header_gen", "lib/zig-header-gen/src/header_gen.zig");
    lib.install();

    const exe = b.addExecutable("stackvm", "src/app.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("clap", "lib/zig-clap/clap.zig");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
