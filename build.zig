const std = @import("std");
const builtin = @import("builtin");

const Backend = enum {
    Win32,
    Raylib,
};

pub fn build(b: *std.Build) void {
    const backend = b.option(Backend, "backend", "win32 or raylib") orelse .Win32;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "handmade-zig",
        .root_source_file = if (backend == .Win32) b.path("src/win32_handmade.zig") else b.path("src/raylib_handmade.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build options.
    const build_options = b.addOptions();
    build_options.addOption(bool, "timing", b.option(bool, "timing", "print timing info to debug output") orelse false);
    build_options.addOption(Backend, "backend", backend);
    exe.root_module.addOptions("build_options", build_options);

    if (backend == .Win32) {
        // Add the win32 API wrapper.
        const zigwin32 = b.dependency("zigwin32", .{}).module("zigwin32");
        exe.root_module.addImport("win32", zigwin32);
    }

    if (backend == .Raylib) {
        // Add the raylib API wrapper and library.
        const raylib_dep = b.dependency("raylib-zig", .{
            .target = target,
            .optimize = optimize,
        });

        const raylib = raylib_dep.module("raylib");
        const raygui = raylib_dep.module("raygui");
        const raylib_artifact = raylib_dep.artifact("raylib");
        exe.linkLibrary(raylib_artifact);
        exe.root_module.addImport("raylib", raylib);
        exe.root_module.addImport("raygui", raygui);
    }

    // Emit generated assembly of the main executable.
    const assembly_file = b.addInstallFile(exe.getEmittedAsm(), "bin/handmade.asm");
    b.getInstallStep().dependOn(&assembly_file.step);

    b.installArtifact(exe);

    // Build the game library.
    const lib_handmade = b.addSharedLibrary(.{
        .name = "handmade",
        .root_source_file = b.path("src/handmade.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });

    // Emit generated assembly of the library.
    const lib_assembly_file = b.addInstallFile(lib_handmade.getEmittedAsm(), "bin/handmade-dll.asm");
    b.getInstallStep().dependOn(&lib_assembly_file.step);

    b.installArtifact(lib_handmade);

    if (builtin.zig_version.minor < 13) {
        // Copy the game library to the bin directory where the runtime expects it to be.
        // From Zig version 0.13.0 this is done automatically.
        const dll_copy_path = b.fmt("bin/{s}", .{lib_handmade.out_filename});
        const install_dll = b.addInstallFileWithDir(lib_handmade.getEmittedBin(), .prefix, dll_copy_path);
        b.getInstallStep().dependOn(&install_dll.step);
    }

    // Allow running from build command.
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_exe.setCwd(b.path("data/"));
    run_step.dependOn(&run_exe.step);
}
