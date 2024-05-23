const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "handmade",
        .root_source_file = b.path("src/main.zig"),
        .target = b.host,
    });

    b.installArtifact(exe);

    // Allow running from build command.
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
