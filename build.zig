const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "handmade-zig",
        .root_source_file = b.path("src/win32_handmade.zig"),
        .target = b.host,
    });

    // Build options.
    const build_options = b.addOptions();
    build_options.addOption(bool, "timing", b.option(bool, "timing", "print timing info to debug output") orelse false);
    exe.root_module.addOptions("build_options", build_options);

    // Add the win32 API wrapper.
    const win32api = b.createModule(.{
        .root_source_file = b.path("lib/zigwin32/win32.zig"),
    });
    exe.root_module.addImport("win32", win32api);

    b.installArtifact(exe);

    // Allow running from build command.
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
