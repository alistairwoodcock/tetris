const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    //     const target = b.standardTargetOptions(.{});

    //     // Standard release options allow the person running `zig build` to select
    //     // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    //     const mode = b.standardReleaseOptions();

    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("tetris", "src/main.zig");
    exe.setBuildMode(mode);
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("c");

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);

    const run = b.step("run", "Run the demo");
    const run_cmd = exe.run();
    run.dependOn(&run_cmd.step);

}