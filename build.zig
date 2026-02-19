const std = @import("std");
const builtin = @import("builtin");

// Defaults.
const FORCE_RELEASE_MODE = true;
const PACKAGE_DEFAULT = .Game;
const INTERNAL_DEFAULT = true;
const SLOW_DEFAULT = true;

const Package = enum {
    All,
    Game,
    Executable,
    Library,
    AssetBuilder,
    HHAEdit,
    Preprocessor,
    Compressor,
    Raytracer,
    TestPNG,
};

pub fn build(b: *std.Build) void {
    if (FORCE_RELEASE_MODE) {
        b.release_mode = .small;
    }

    // Retrieve build options.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const package = b.option(Package, "package", "which part to build") orelse PACKAGE_DEFAULT;
    const internal = b.option(bool, "internal", "wether to include internal testing features") orelse INTERNAL_DEFAULT;
    const slow = b.option(bool, "slow", "wether to include slow testing features") orelse SLOW_DEFAULT;

    // Add build options.
    const build_options = b.addOptions();
    build_options.addOption(Package, "package", package);
    build_options.addOption(bool, "internal", internal);
    build_options.addOption(bool, "slow", slow);

    // Add the packages.
    if (package == .All or package == .Game or package == .Executable) {
        addExecutable(b, build_options, target, optimize, package, internal);
    }

    if (package == .All or package == .Game or package == .Library) {
        addLibrary(b, build_options, target, optimize, package);
    }

    if (package == .All or package == .AssetBuilder) {
        addAssetBuilder(b, build_options, target, optimize);
    }

    if (package == .All or package == .HHAEdit) {
        addHHAEdit(b, build_options, target, optimize);
    }

    if (package == .All or package == .Preprocessor) {
        addSimplePreprocessor(b, build_options, target, optimize);
    }

    if (package == .All or package == .Compressor) {
        addSimpleCompressor(b, build_options, target, optimize);
    }

    if (package == .All or package == .Raytracer) {
        addRaytracer(b, build_options, target, optimize);
    }

    if (package == .All or package == .TestPNG) {
        addTestPNG(b, build_options, target, optimize);
    }
}

fn addExecutable(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    package: Package,
    internal: bool,
) void {
    const file_formats_module = b.addModule("file_formats", .{
        .root_source_file = b.path("src/file_formats.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "handmade-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/win32_handmade.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
        }),
    });
    exe.stack_size = 0x100000; // 1MB.
    exe.root_module.addOptions("build_options", build_options);
    exe.root_module.addImport("file_formats", file_formats_module);

    if (!internal) {
        exe.subsystem = .Windows;
    }

    // Add the win32 API wrapper.
    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");
    exe.root_module.addImport("win32", zigwin32);

    if (package == .All) {
        // Emit generated assembly of the main executable.
        const assembly_file = b.addInstallFile(exe.getEmittedAsm(), "bin/handmade.asm");
        b.getInstallStep().dependOn(&assembly_file.step);
    }

    b.installArtifact(exe);

    // Allow running main executable from build command.
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_exe.setCwd(b.path("."));
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
        .target = target,
        .optimize = optimize,
    });

    const lib_handmade = b.addLibrary(.{
        .name = "handmade",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/handmade.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
        }),
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    lib_handmade.stack_size = 0x100000; // 1MB.
    lib_handmade.root_module.addOptions("build_options", build_options);
    lib_handmade.root_module.addImport("file_formats", file_formats_module);

    const lib_check = b.addLibrary(.{
        .name = "handmade",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/handmade.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
        }),
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    lib_check.stack_size = 0x100000; // 1MB.
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
        .target = target,
        .optimize = optimize,
    });
    const file_formats_module = b.addModule("file_formats", .{
        .root_source_file = b.path("src/file_formats.zig"),
        .target = target,
        .optimize = optimize,
    });

    const asset_builder_exe = b.addExecutable(.{
        .name = "test-asset-builder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/test_asset_builder.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    asset_builder_exe.stack_size = 0x100000; // 1MB.
    asset_builder_exe.root_module.addOptions("build_options", build_options);
    asset_builder_exe.root_module.addImport("shared", shared_module);
    asset_builder_exe.root_module.addImport("file_formats", file_formats_module);
    shared_module.addImport("file_formats", file_formats_module);

    const stb_dep = b.dependency("stb", .{});
    asset_builder_exe.addIncludePath(stb_dep.path(""));
    asset_builder_exe.addCSourceFiles(.{ .files = &[_][]const u8{"tools/stb_truetype.c"}, .flags = &[_][]const u8{"-g"} });

    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");
    asset_builder_exe.root_module.addImport("win32", zigwin32);

    b.installArtifact(asset_builder_exe);

    // Allow running asset builder from build command.
    const run_asset_builder = b.addRunArtifact(asset_builder_exe);
    const asset_builder_run_step = b.step("build-assets", "Run the test asset builder");
    run_asset_builder.setCwd(b.path("data/"));
    asset_builder_run_step.dependOn(&run_asset_builder.step);
}

fn addHHAEdit(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const shared_module = b.addModule("shared", .{
        .root_source_file = b.path("src/shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    const file_formats_module = b.addModule("file_formats", .{
        .root_source_file = b.path("src/file_formats.zig"),
        .target = target,
        .optimize = optimize,
    });

    const hha_edit_exe = b.addExecutable(.{
        .name = "hha-edit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/hha_edit.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    hha_edit_exe.stack_size = 0x100000; // 1MB.
    hha_edit_exe.root_module.addOptions("build_options", build_options);
    hha_edit_exe.root_module.addImport("shared", shared_module);
    hha_edit_exe.root_module.addImport("file_formats", file_formats_module);
    shared_module.addImport("file_formats", file_formats_module);

    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");
    hha_edit_exe.root_module.addImport("win32", zigwin32);

    b.installArtifact(hha_edit_exe);

    // Allow running asset builder from build command.
    const run_hha_edit = b.addRunArtifact(hha_edit_exe);
    if (b.args) |args| {
        run_hha_edit.addArgs(args);
    }
    const hha_edit_run_step = b.step("hha-edit", "Run the HHA edit tool");
    run_hha_edit.setCwd(b.path("data/"));
    hha_edit_run_step.dependOn(&run_hha_edit.step);
}

fn addSimplePreprocessor(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const simple_preprocessor_exe = b.addExecutable(.{
        .name = "simple-preprocessor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/simple_preprocessor.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
        }),
    });
    simple_preprocessor_exe.stack_size = 0x100000; // 1MB.
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

fn addRaytracer(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const math_module = b.addModule("math", .{
        .root_source_file = b.path("src/math.zig"),
        .target = target,
        .optimize = optimize,
    });
    const raytracer_exe = b.addExecutable(.{
        .name = "handmade-ray",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/ray.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    raytracer_exe.stack_size = 0x400000; // 4MB.
    raytracer_exe.root_module.addOptions("build_options", build_options);
    raytracer_exe.root_module.addImport("math", math_module);

    b.installArtifact(raytracer_exe);

    // Allow running the raytracer from a build command.
    const run_raytracer = b.addRunArtifact(raytracer_exe);
    if (b.args) |args| {
        run_raytracer.addArgs(args);
    }
    const raytracer_run_step = b.step("run-raytracer", "Run the raytracer");
    run_raytracer.setCwd(b.path("test/"));
    // raytracer_run_step.dependOn(&run_raytracer.step);

    const open_file = b.addSystemCommand(&.{
        "cmd", "/C", "start", "test.bmp",
    });
    open_file.setCwd(b.path("test/"));

    open_file.step.dependOn(&run_raytracer.step);
    raytracer_run_step.dependOn(&open_file.step);
}

fn addTestPNG(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const png_module = b.addModule("png", .{
        .root_source_file = b.path("src/png.zig"),
        .target = target,
        .optimize = optimize,
    });
    png_module.addOptions("build_options", build_options);
    const test_png_exe = b.addExecutable(.{
        .name = "test-png",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/test_png.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    test_png_exe.stack_size = 0x400000; // 4MB.
    test_png_exe.root_module.addOptions("build_options", build_options);
    test_png_exe.root_module.addImport("png", png_module);

    b.installArtifact(test_png_exe);

    // Allow running the png reader from a build command.
    const run_test_png = b.addRunArtifact(test_png_exe);
    if (b.args) |args| {
        run_test_png.addArgs(args);
    }
    const test_png_run_step = b.step("run-test-png", "Run the png reader");
    run_test_png.setCwd(b.path("."));
    test_png_run_step.dependOn(&run_test_png.step);
}

fn addSimpleCompressor(
    b: *std.Build,
    build_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const simple_compressor_exe = b.addExecutable(.{
        .name = "simple-compressor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/simple_compressor.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
        }),
    });
    simple_compressor_exe.stack_size = 0x100000; // 1MB.
    simple_compressor_exe.root_module.addOptions("build_options", build_options);

    b.installArtifact(simple_compressor_exe);

    // Allow running the preprocessor from build command.
    const run_simple_compressor = b.addRunArtifact(simple_compressor_exe);
    if (b.args) |args| {
        run_simple_compressor.addArgs(args);
    }
    const simple_preprocessor_run_step = b.step("simple-compressor", "Run the compressor");
    run_simple_compressor.setCwd(b.path("."));
    simple_preprocessor_run_step.dependOn(&run_simple_compressor.step);
}
