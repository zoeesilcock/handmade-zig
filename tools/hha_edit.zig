const std = @import("std");
const shared = @import("shared");
const file_formats = @import("file_formats");
const math = shared.math;
const intrinsics = shared.intrinsics;

// Types.
const HHAHeader = file_formats.HHAHeader;

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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 3) {
        if (std.mem.eql(u8, args[1], "-create")) {
            const file_name: []const u8 = args[2];

            var opt_dest: ?std.fs.File = std.fs.cwd().openFile(file_name, .{ .mode = .read_only }) catch null;
            defer if (opt_dest) |dest| dest.close();

            if (opt_dest == null) {
                opt_dest = std.fs.cwd().openFile(file_name, .{ .mode = .write_only }) catch null;

                if (std.fs.cwd().createFile(file_name, .{})) |dest| {
                    const header: HHAHeader = .{
                        .tag_count = 0,
                        .asset_count = 0,
                        .asset_type_count = 0,
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
        std.log.err("Usage: {s} -create (filename.hha)", .{args[0]});
    }
}
