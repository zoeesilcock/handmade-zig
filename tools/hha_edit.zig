const std = @import("std");
const shared = @import("shared");
const file_formats = @import("file_formats");
const file_formats_v0 = @import("file_formats_v0");
const math = shared.math;
const intrinsics = shared.intrinsics;

// Types.
const HHAHeaderV0 = file_formats_v0.HHAHeaderV0;
const HHAAssetTypeV0 = file_formats_v0.HHAAssetTypeV0;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAsset = file_formats.HHAAsset;
const HHAAnnotation = file_formats.HHAAnnotation;

pub const std_options: std.Options = .{
    .logFn = myLogFn,
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    if (level == .err) {
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        const stderr = std.fs.File.stderr().deprecatedWriter();
        nosuspend stderr.print(format ++ "\n", args) catch return;
    } else {
        var stdout_buf: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writerStreaming(&stdout_buf);
        var stdout = &stdout_writer.interface;
        stdout.print(format ++ "\n", args) catch return;
        stdout.flush() catch return;
    }
}

const LoadedHHAAnnotation = struct {
    source_file_base_name: []const u8 = "",
    asset_name: []const u8 = "",
    asset_description: []const u8 = "",
    author: []const u8 = "",
};

const LoadedHHA = struct {
    valid: bool = false,
    source_file_name: []const u8 = "",

    magic_value: u32 = 0,
    source_version: u32 = 0,

    tag_count: u32 = 0,
    tags: [*]HHATag = undefined,

    asset_count: u32 = 0,
    assets: [*]HHAAsset = undefined,
    annotations: [*]LoadedHHAAnnotation = undefined,

    data_store: []const u8 = undefined,
};

fn readEntireFile(file: std.fs.File, allocator: std.mem.Allocator) ![]const u8 {
    var result: []const u8 = undefined;

    _ = try file.seekTo(0);

    result = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, .@"32", 0);

    return result;
}

fn readHHAV0(source_file: std.fs.File, hha: *LoadedHHA, allocator: std.mem.Allocator) void {
    _ = source_file;

    const header: *const HHAHeaderV0 = @ptrCast(hha.data_store);
    const source_tags: [*]HHATag = @ptrFromInt(@intFromPtr(hha.data_store.ptr) + header.tags);
    _ = source_tags;
    const source_asset_types: [*]HHAAssetTypeV0 = @ptrFromInt(@intFromPtr(hha.data_store.ptr) + header.asset_types);
    const source_assets: [*]HHAAsset = @ptrFromInt(@intFromPtr(hha.data_store.ptr) + header.assets);

    hha.tag_count = header.tag_count + header.asset_count - 1;
    hha.tags = @ptrCast(allocator.alloc(HHATag, hha.tag_count) catch unreachable);

    hha.asset_count = header.asset_count;
    hha.assets = @ptrCast(allocator.alloc(HHAAsset, hha.asset_count) catch unreachable);
    hha.annotations = @ptrCast(allocator.alloc(LoadedHHAAnnotation, hha.asset_count) catch unreachable);

    const default_annotation: LoadedHHAAnnotation = .{
        .source_file_base_name = hha.source_file_name,
        .asset_name = "UNKNOWN",
        .asset_description = "imported by readHHAV0",
        .author = "hha-edit.exe",
    };

    hha.annotations[0] = .{};
    hha.assets[0] = .{};
    hha.tags[0] = .{};

    var dest_asset_index: u32 = 1;
    var asset_type_index: u32 = 0;
    while (asset_type_index < header.asset_type_count) : (asset_type_index += 1) {
        const asset_type: HHAAssetTypeV0 = source_asset_types[asset_type_index];
        var source_asset_index: u32 = asset_type.first_asset_index;
        while (source_asset_index < asset_type.one_past_last_asset_index) : (source_asset_index += 1) {
            const dest_asset: *HHAAsset = &hha.assets[source_asset_index];
            dest_asset.* = source_assets[source_asset_index];
            // dest_asset.first_tag_index = 0;
            // dest_asset.one_past_last_asset_index = 0;

            hha.annotations[source_asset_index] = default_annotation;

            dest_asset_index += 1;
        }
    }
}
fn readHHAV1(source_file: std.fs.File, dest: *LoadedHHA) void {
    _ = source_file;
    _ = dest;
}

fn readHHA(source_file_name: []const u8, allocator: std.mem.Allocator) ?*LoadedHHA {
    const result: ?*LoadedHHA = allocator.create(LoadedHHA) catch null;
    const null_hha: LoadedHHA = .{};
    result.?.* = null_hha;
    result.?.source_file_name = source_file_name;

    if (std.fs.cwd().openFile(source_file_name, .{ .mode = .read_only })) |source_file| {
        defer source_file.close();

        result.?.data_store = readEntireFile(source_file, allocator) catch undefined;

        result.?.magic_value = @as([*]const u32, @ptrCast(@alignCast(result.?.data_store)))[0];
        result.?.source_version = @as([*]const u32, @ptrCast(@alignCast(result.?.data_store)))[1];

        if (result.?.magic_value == file_formats.HHA_MAGIC_VALUE) {
            if (result.?.source_version == 0) {
                readHHAV0(source_file, result.?, allocator);
                result.?.valid = true;
            } else if (result.?.source_version == 0) {
                readHHAV1(source_file, result.?);
                result.?.valid = true;
            } else {
                std.log.err("Unrecognized HHA version: {d}", .{result.?.source_version});
            }
        } else {
            std.log.err("Magic value is not HHAF.", .{});
        }
    } else |err| {
        std.log.err("Unable to open file {s} for reading. {s}", .{ source_file_name, @errorName(err) });
    }

    return result;
}

fn writeHHA(opt_source: ?*LoadedHHA, dest_file_name: []const u8) void {
    if (!fileExists(dest_file_name)) {
        if (opt_source) |source| {
            if (source.valid) {
                if (std.fs.cwd().createFile(dest_file_name, .{})) |dest| {
                    _ = dest;
                } else |err| {
                    std.log.err("Unable to open file {s} for writing. {s}", .{ dest_file_name, @errorName(err) });
                }
            } else {
                std.log.err("Source HHA was not valid, so not writing to {s}.", .{dest_file_name});
            }
        }
    } else {
        std.log.err("{s} must not exist.", .{dest_file_name});
    }
}

fn fileExists(file_name: []const u8) bool {
    var result: bool = false;

    const opt_file: ?std.fs.File = std.fs.cwd().openFile(file_name, .{ .mode = .read_only }) catch null;
    defer if (opt_file) |file| file.close();

    if (opt_file != null) {
        result = true;
    }

    return result;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 4) {
        if (std.mem.eql(u8, args[1], "-rewrite")) {
            const source_file_name: []const u8 = args[2];
            const dest_file_name: []const u8 = args[3];

            const hha: ?*LoadedHHA = readHHA(source_file_name, allocator);
            writeHHA(hha, dest_file_name);
        }
    } else if (args.len == 3) {
        if (std.mem.eql(u8, args[1], "-info")) {
            const file_name: []const u8 = args[2];

            if (readHHA(file_name, allocator)) |hha| {
                std.log.info("Magic value: {s}", .{std.mem.toBytes(hha.magic_value)[0..4]});
                std.log.info("Version: {d}", .{hha.source_version});
            }
        } else if (std.mem.eql(u8, args[1], "-create")) {
            const file_name: []const u8 = args[2];

            if (!fileExists(file_name)) {
                const opt_dest: ?std.fs.File = std.fs.cwd().openFile(file_name, .{ .mode = .write_only }) catch null;
                defer if (opt_dest) |dest| dest.close();

                if (std.fs.cwd().createFile(file_name, .{})) |dest| {
                    const header: HHAHeader = .{
                        .tag_count = 0,
                        .asset_count = 0,
                    };

                    var buf: [1024]u8 = undefined;
                    var file_writer = dest.writer(&buf);
                    const writer = &file_writer.interface;

                    try writer.writeAll(std.mem.asBytes(&header)[0..@sizeOf(HHAHeader)]);
                    try writer.flush();
                } else |err| {
                    std.log.err("Unable to open file {s} for writing. {s}", .{ file_name, @errorName(err) });
                }
            } else {
                std.log.err("File {s} already exists.", .{file_name});
            }
        }
    } else {
        std.log.err("Usage: {s} -create (dest.hha)", .{args[0]});
        std.log.err("Usage: {s} -rewrite (source.hha) (dest.hha)", .{args[0]});
        std.log.err("Usage: {s} -info (source.hha)", .{args[0]});
    }
}
