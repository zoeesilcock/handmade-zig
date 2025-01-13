const std = @import("std");
const builtin = @import("builtin");

// Defaults.
const FORCE_RELEASE_MODE = false;
const PACKAGE_DEFAULT = .Game;
const INTERNAL_DEFAULT = true;
const BACKEND_DEFAULT = .Win32;

const Backend = enum {
    Win32,
    Raylib,
};

const Package = enum {
    All,
    Game,
    Executable,
    Library,
    AssetBuilder,
    Preprocessor,
};

pub fn build(b: *std.Build) void {
    if (FORCE_RELEASE_MODE) {
        b.release_mode = .fast;
    }

    // Retrieve build options.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const backend = b.option(Backend, "backend", "platform backend") orelse BACKEND_DEFAULT;
    const package = b.option(Package, "package", "which part to build") orelse PACKAGE_DEFAULT;
    const internal = b.option(bool, "internal", "use this for internal builds") orelse INTERNAL_DEFAULT;

    // Add build options.
    const build_options = b.addOptions();
    build_options.addOption(Package, "package", package);
    build_options.addOption(Backend, "backend", backend);
    build_options.addOption(bool, "internal", internal);

    // Add the packages.
    if (package == .All or package == .Game or package == .Executable) {
        addExecutable(b, build_options, target, optimize, package, backend, internal);
    }

    if (package == .All or package == .Game or package == .Library) {
        addLibrary(b, build_options, target, optimize, package);
    }

    if (package == .All or package == .AssetBuilder) {
        addAssetBuilder(b, build_options, target, optimize);
    }

    if (package == .All or package == .Preprocessor) {
        addSimplePreprocessor(b, build_options, target, optimize);
    }
}

fn addExecutable(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    package: Package,
    backend: Backend,
    internal: bool,
) void {
    const file_formats_module = b.addModule("file_formats", .{
        .root_source_file = b.path("src/file_formats.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "handmade-zig",
        .root_source_file = if (backend == .Win32) b.path("src/win32_handmade.zig") else b.path("src/raylib_handmade.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("build_options", build_options);
    exe.root_module.addImport("file_formats", file_formats_module);

    if (backend == .Win32 and internal) {
        exe.subsystem = .Windows;
    }

    if (backend == .Win32) {
        // Add the win32 API wrapper.
        const zigwin32 = b.dependency("zigwin32", .{}).module("zigwin32");
        exe.root_module.addImport("win32", zigwin32);
    } else if (backend == .Raylib) {
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

    if (package == .All) {
        // Emit generated assembly of the main executable.
        const assembly_file = b.addInstallFile(exe.getEmittedAsm(), "bin/handmade.asm");
        b.getInstallStep().dependOn(&assembly_file.step);
    }

    b.installArtifact(exe);

    // Allow running main executable from build command.
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_exe.setCwd(b.path("data/"));
    run_step.dependOn(&run_exe.step);
}

fn addLibrary(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    package: Package,
) void {
    const file_formats_module = b.addModule("file_formats", .{
        .root_source_file = b.path("src/file_formats.zig"),
    });

    const lib_handmade = b.addSharedLibrary(.{
        .name = "handmade",
        .root_source_file = b.path("src/handmade.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    lib_handmade.root_module.addOptions("build_options", build_options);
    lib_handmade.root_module.addImport("file_formats", file_formats_module);

    const lib_check = b.addSharedLibrary(.{
        .name = "handmade",
        .root_source_file = b.path("src/handmade.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    lib_check.root_module.addOptions("build_options", build_options);
    lib_check.root_module.addImport("file_formats", file_formats_module);
    const check = b.step("check", "Check if lib compiles");
    check.dependOn(&lib_check.step);

    if (package == .All) {
        // Emit generated assembly of the library.
        const lib_assembly_file = b.addInstallFile(lib_handmade.getEmittedAsm(), "bin/handmade-dll.asm");
        b.getInstallStep().dependOn(&lib_assembly_file.step);
    }

    b.installArtifact(lib_handmade);

    if (builtin.zig_version.minor < 13) {
        // Copy the game library to the bin directory where the runtime expects it to be.
        // From Zig version 0.13.0 this is done automatically.
        const dll_copy_path = b.fmt("bin/{s}", .{lib_handmade.out_filename});
        const install_dll = b.addInstallFileWithDir(lib_handmade.getEmittedBin(), .prefix, dll_copy_path);
        b.getInstallStep().dependOn(&install_dll.step);
    }
}

fn addAssetBuilder(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const shared_module = b.addModule("shared", .{
        .root_source_file = b.path("src/shared.zig"),
    });
    const file_formats_module = b.addModule("file_formats", .{
        .root_source_file = b.path("src/file_formats.zig"),
    });

    const asset_builder_exe = b.addExecutable(.{
        .name = "test-asset-builder",
        .root_source_file = b.path("tools/test_asset_builder.zig"),
        .target = target,
        .optimize = optimize,
    });
    asset_builder_exe.root_module.addOptions("build_options", build_options);
    asset_builder_exe.root_module.addImport("shared", shared_module);
    asset_builder_exe.root_module.addImport("file_formats", file_formats_module);

    const stb_dep = b.dependency("stb", .{});
    asset_builder_exe.linkLibC();
    asset_builder_exe.addIncludePath(stb_dep.path(""));
    asset_builder_exe.addCSourceFiles(.{ .files = &[_][]const u8{"src/stb_truetype.c"}, .flags = &[_][]const u8{"-g"} });

    const zigwin32 = b.dependency("zigwin32", .{}).module("zigwin32");
    asset_builder_exe.root_module.addImport("win32", zigwin32);

    b.installArtifact(asset_builder_exe);

    // Allow running asset builder from build command.
    const run_asset_builder = b.addRunArtifact(asset_builder_exe);
    const asset_builder_run_step = b.step("build-assets", "Run the test asset builder");
    run_asset_builder.setCwd(b.path("data/"));
    asset_builder_run_step.dependOn(&run_asset_builder.step);
}

fn addSimplePreprocessor(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const simple_preprocessor_exe = b.addExecutable(.{
        .name = "simple-preprocessor",
        .root_source_file = b.path("tools/simple_preprocessor.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_preprocessor_exe.root_module.addOptions("build_options", build_options);

    b.installArtifact(simple_preprocessor_exe);

    // Allow running the preprocessor from build command.
    const run_simple_preprocessor = b.addRunArtifact(simple_preprocessor_exe);
    const simple_preprocessor_run_step = b.step("simple-preprocessor", "Run the preprocessor");
    run_simple_preprocessor.setCwd(b.path("."));
    simple_preprocessor_run_step.dependOn(&run_simple_preprocessor.step);

    // const output = run_simple_preprocessor.captureStdOut();
    // simple_preprocessor_run_step.dependOn(&b.addInstallFileWithDir(output, .prefix, "../src/generated.zig").step);
}
