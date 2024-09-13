const std = @import("std");
const shared = @import("shared");
const file_formats = @import("file_formats");
const math = shared.math;
const intrinsics = shared.intrinsics;

// Types.
const AssetTypeId = shared.AssetTypeId;
const AssetTagId = shared.AssetTagId;
const HHAHeader = file_formats.HHAHeader;
const HHATag = file_formats.HHATag;
const HHAAssetType = file_formats.HHAAssetType;
const HHAAsset = file_formats.HHAAsset;
const HHABitmap = file_formats.HHABitmap;
const HHASound = file_formats.HHASound;
const BitmapId = file_formats.BitmapId;
const SoundId = file_formats.SoundId;
const Color = math.Color;

const ASSET_TYPE_ID_COUNT = shared.ASSET_TYPE_ID_COUNT;

// File formats.
const EntireFile = struct {
    content_size: u32 = 0,
    contents: []const u8 = undefined,
};

fn readEntireFile(file_name: []const u8, allocator: std.mem.Allocator) EntireFile {
    var result = EntireFile{};

    if (std.fs.cwd().openFile(file_name, .{ .mode = .read_only })) |file| {
        defer file.close();

        _ = file.seekFromEnd(0) catch undefined;
        result.content_size = @as(u32, @intCast(file.getPos() catch 0));
        _ = file.seekTo(0) catch undefined;

        const buffer = file.readToEndAlloc(allocator, std.math.maxInt(u32)) catch "";
        result.contents = buffer;
    } else |err| {
        std.debug.print("Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}

const BitmapHeader = packed struct {
    file_type: u16,
    file_size: u32,
    reserved1: u16,
    reserved2: u16,
    bitmap_offset: u32,
    size: u32,
    width: i32,
    height: i32,
    planes: u16,
    bits_per_pxel: u16,
    compression: u32,
    size_of_bitmap: u32,
    horz_resolution: i32,
    vert_resolution: i32,
    colors_used: u32,
    colors_important: u32,
    red_mask: u32,
    green_mask: u32,
    blue_mask: u32,
};

const LoadedBitmap = struct {
    width: i32 = 0,
    height: i32 = 0,
    pitch: i32 = 0,
    memory: ?[*]void,
    free: []const u8,
};

fn loadBMP(
    file_name: []const u8,
    allocator: std.mem.Allocator,
) LoadedBitmap {
    var result: LoadedBitmap = undefined;
    const read_result = readEntireFile(file_name, allocator);

    if (read_result.content_size > 0) {
        result.free = read_result.contents;

        const header = @as(*BitmapHeader, @ptrCast(@alignCast(@constCast(read_result.contents))));

        std.debug.assert(header.height >= 0);
        std.debug.assert(header.compression == 3);

        result.memory = @as([*]void, @ptrCast(@constCast(read_result.contents))) + header.bitmap_offset;
        result.width = header.width;
        result.height = header.height;

        const alpha_mask = ~(header.red_mask | header.green_mask | header.blue_mask);
        const alpha_scan = intrinsics.findLeastSignificantSetBit(alpha_mask);
        const red_scan = intrinsics.findLeastSignificantSetBit(header.red_mask);
        const green_scan = intrinsics.findLeastSignificantSetBit(header.green_mask);
        const blue_scan = intrinsics.findLeastSignificantSetBit(header.blue_mask);

        std.debug.assert(alpha_scan.found);
        std.debug.assert(red_scan.found);
        std.debug.assert(green_scan.found);
        std.debug.assert(blue_scan.found);

        const red_shift_down = @as(u5, @intCast(red_scan.index));
        const green_shift_down = @as(u5, @intCast(green_scan.index));
        const blue_shift_down = @as(u5, @intCast(blue_scan.index));
        const alpha_shift_down = @as(u5, @intCast(alpha_scan.index));

        var source_dest: [*]align(@alignOf(u8)) u32 = @ptrCast(result.memory);
        var x: u32 = 0;
        while (x < header.width) : (x += 1) {
            var y: u32 = 0;
            while (y < header.height) : (y += 1) {
                const color = source_dest[0];
                var texel = Color.new(
                    @floatFromInt((color & header.red_mask) >> red_shift_down),
                    @floatFromInt((color & header.green_mask) >> green_shift_down),
                    @floatFromInt((color & header.blue_mask) >> blue_shift_down),
                    @floatFromInt((color & alpha_mask) >> alpha_shift_down),
                );
                texel = math.sRGB255ToLinear1(texel);

                _ = texel.setRGB(texel.rgb().scaledTo(texel.a()));

                texel = math.linear1ToSRGB255(texel);

                source_dest[0] = texel.packColor1();

                source_dest += 1;
            }
        }
    }

    result.pitch = result.width * shared.BITMAP_BYTES_PER_PIXEL;

    if (false) {
        result.pitch = -result.width * shared.BITMAP_BYTES_PER_PIXEL;
        const offset: usize = @intCast(-result.pitch * (result.height - 1));
        result.memory = @ptrCast(@as([*]u8, @ptrCast(result.memory)) + offset);
    }

    return result;
}

const WaveHeader = extern struct {
    riff_id: u32,
    size: u32,
    wave_id: u32,
};

const WaveChunk = extern struct {
    id: u32,
    size: u32,
};

const WaveFmt = extern struct {
    w_format_tag: u16,
    channels: u16,
    n_samples_per_second: u32,
    n_avg_bytes_per_second: u32,
    n_block_align: u16,
    bits_per_sample: u16,
    cb_size: u16,
    w_valid_width_per_sample: u16,
    dw_channel_mask: u32,
    sub_format: [16]u8,
};

const LoadedSound = struct {
    sample_count: u32,
    channel_count: u32,
    samples: [2]?[*]i16,
    free: []const u8,
};

fn riffCode(a: u32, b: u32, c: u32, d: u32) u32 {
    return @as(u32, a << 0) | @as(u32, b << 8) | @as(u32, c << 16) | @as(u32, d << 24);
}

const WaveChunkId = enum(u32) {
    ChunkID_fmt = riffCode('f', 'm', 't', ' '),
    ChunkID_data = riffCode('d', 'a', 't', 'a'),
    ChunkID_RIFF = riffCode('R', 'I', 'F', 'F'),
    ChunkID_WAVE = riffCode('W', 'A', 'V', 'E'),
    _,
};

const RiffIterator = struct {
    at: [*]u8,
    stop: [*]u8,

    fn nextChunk(self: RiffIterator) RiffIterator {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        const size = (chunk.size + 1) & ~@as(u32, @intCast(1));
        return RiffIterator{ .at = self.at + @sizeOf(WaveChunk) + size, .stop = self.stop };
    }

    fn isValid(self: RiffIterator) bool {
        return @intFromPtr(self.at) < @intFromPtr(self.stop);
    }

    fn getType(self: RiffIterator) ?WaveChunkId {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        return std.meta.intToEnum(WaveChunkId, chunk.id) catch null;
    }

    fn getChunkData(self: RiffIterator) *void {
        return @ptrCast(self.at + @sizeOf(WaveChunk));
    }

    fn getChunkDataSize(self: RiffIterator) u32 {
        const chunk: *WaveChunk = @ptrCast(@alignCast(self.at));
        return chunk.size;
    }
};

fn parseWaveChunkAt(at: *void, stop: *void) RiffIterator {
    return RiffIterator{ .at = @ptrCast(at), .stop = @ptrCast(stop) };
}

pub fn loadWAV(
    file_name: []const u8,
    section_first_sample_index: u32,
    section_sample_count: u32,
    allocator: std.mem.Allocator,
) LoadedSound {
    var result: LoadedSound = undefined;
    const read_result = readEntireFile(file_name, allocator);

    if (read_result.content_size > 0) {
        result.free = read_result.contents;

        const header = @as(*WaveHeader, @ptrCast(@alignCast(@constCast(read_result.contents))));

        std.debug.assert(header.riff_id == @intFromEnum(WaveChunkId.ChunkID_RIFF));
        std.debug.assert(header.wave_id == @intFromEnum(WaveChunkId.ChunkID_WAVE));

        var channel_count: ?u16 = null;
        var sample_data: ?[*]i16 = null;
        var sample_data_size: ?u32 = null;

        const chunk_address = @intFromPtr(header) + @sizeOf(WaveHeader);
        var iterator = parseWaveChunkAt(@ptrFromInt(chunk_address), @ptrFromInt(chunk_address + header.size - 4));
        while (iterator.isValid()) : (iterator = iterator.nextChunk()) {
            if (iterator.getType()) |chunk_type| {
                switch (chunk_type) {
                    .ChunkID_fmt => {
                        const fmt: *WaveFmt = @ptrCast(@alignCast(iterator.getChunkData()));

                        std.debug.assert(fmt.w_format_tag == 1);
                        std.debug.assert(fmt.n_samples_per_second == 48000);
                        std.debug.assert(fmt.bits_per_sample == 16);
                        std.debug.assert(fmt.n_block_align == (@sizeOf(i16) * fmt.channels));

                        channel_count = fmt.channels;
                    },
                    .ChunkID_data => {
                        sample_data = @ptrCast(@alignCast(iterator.getChunkData()));
                        sample_data_size = iterator.getChunkDataSize();
                    },
                    else => {},
                }
            }
        }

        std.debug.assert(channel_count != null and sample_data != null and sample_data_size != null);

        result.channel_count = channel_count.?;
        var sample_count = sample_data_size.? / (channel_count.? * @sizeOf(i16));

        if (sample_data) |data| {
            if (channel_count == 1) {
                result.samples[0] = @ptrCast(data);
                result.samples[1] = null;
            } else if (channel_count == 2) {
                result.samples[0] = @ptrCast(data);
                result.samples[1] = @ptrCast(data + sample_count);

                if (false) {
                    var i: i16 = 0;
                    while (i < sample_count) : (i += 1) {
                        data[2 * @as(usize, @intCast(i)) + 0] = i;
                        data[2 * @as(usize, @intCast(i)) + 1] = i;
                    }
                }

                var sample_index: u32 = 0;
                while (sample_index < sample_count) : (sample_index += 1) {
                    const source = data[2 * sample_index];
                    data[2 * sample_index] = data[sample_index];
                    data[sample_index] = source;
                }
            } else {
                // Invalid channel count in WAV file.
                unreachable;
            }
        }

        // TODO: Load right channels.
        result.channel_count = 1;

        var at_end = true;
        if (section_sample_count != 0) {
            std.debug.assert((section_first_sample_index + section_sample_count) <= sample_count);

            at_end = (section_first_sample_index + section_sample_count) == sample_count;
            sample_count = section_sample_count;

            var channel_index: u32 = 0;
            while (channel_index < result.channel_count) : (channel_index += 1) {
                result.samples[channel_index].? += section_first_sample_index;
            }
        }

        if (at_end) {
            var channel_index: u32 = 0;
            while (channel_index < result.channel_count) : (channel_index += 1) {
                var sample_index: u32 = sample_count;
                while (sample_index < (sample_count + 8)) : (sample_index += 1) {
                    result.samples[channel_index].?[sample_index] = 0;
                }
            }
        }

        result.sample_count = sample_count;
    }

    return result;
}

// Assets.
const AssetType = enum(u32) {
    Sound,
    Bitmap,
};

const AssetSource = struct {
    asset_type: AssetType,
    file_name: []const u8 = undefined,
    first_sample_index: u32,
};

const BitmapAsset = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: [2]f32 = undefined,
};

const AssetBitmapInfo = struct {
    file_name: [*:0]const u8 = undefined,
    alignment_percentage: [2]f32 = undefined,
};

const AssetSoundInfo = struct {
    file_name: [*:0]const u8,
    first_sample_index: u32,
    sample_count: u32,
    next_id_to_play: ?SoundId,
};

const VERY_LARGE_NUMBER = 4096;

pub const Assets = struct {
    tag_count: u32 = 0,
    tags: [VERY_LARGE_NUMBER]HHATag = [1]HHATag{undefined} ** VERY_LARGE_NUMBER,

    asset_count: u32 = 0,
    asset_sources: [VERY_LARGE_NUMBER]AssetSource = [1]AssetSource{undefined} ** VERY_LARGE_NUMBER,
    assets: [VERY_LARGE_NUMBER]HHAAsset = [1]HHAAsset{undefined} ** VERY_LARGE_NUMBER,

    asset_type_count: u32 = 0,
    asset_types: [ASSET_TYPE_ID_COUNT]HHAAssetType = [1]HHAAssetType{HHAAssetType{}} ** ASSET_TYPE_ID_COUNT,

    debug_asset_type: ?*HHAAssetType = null,
    asset_index: u32 = 0,

    fn beginAssetType(self: *Assets, type_id: AssetTypeId) void {
        std.debug.assert(self.debug_asset_type == null);

        self.debug_asset_type = &self.asset_types[type_id.toInt()];
        self.debug_asset_type.?.type_id = @intFromEnum(type_id);
        self.debug_asset_type.?.first_asset_index = self.asset_count;
        self.debug_asset_type.?.one_past_last_asset_index = self.debug_asset_type.?.first_asset_index;
    }

    fn addBitmapAsset(self: *Assets, file_name: []const u8, alignment_percentage_x: ?f32, alignment_percentage_y: ?f32) ?BitmapId {
        std.debug.assert(self.debug_asset_type != null);

        var result: ?BitmapId = null;

        if (self.debug_asset_type) |asset_type| {
            std.debug.assert(asset_type.one_past_last_asset_index < self.assets.len);

            result = BitmapId{ .value = asset_type.one_past_last_asset_index };
            const source: *AssetSource = &self.asset_sources[result.?.value];
            const hha: *HHAAsset = &self.assets[result.?.value];
            self.debug_asset_type.?.one_past_last_asset_index += 1;

            hha.first_tag_index = self.tag_count;
            hha.one_past_last_tag_index = self.tag_count;
            hha.info = .{
                .bitmap = HHABitmap{
                    .dim = .{ 0, 0 },
                    .alignment_percentage = .{
                        alignment_percentage_x orelse 0.5,
                        alignment_percentage_y orelse 0.5,
                    },
                },
            };

            source.asset_type = .Bitmap;
            source.file_name = file_name;

            self.asset_index = result.?.value;
        }

        return result;
    }

    fn addSoundAsset(self: *Assets, file_name: []const u8) ?SoundId {
        return self.addSoundSectionAsset(file_name, 0, 0);
    }

    fn addSoundSectionAsset(self: *Assets, file_name: []const u8, first_sample_index: u32, sample_count: u32) ?SoundId {
        std.debug.assert(self.debug_asset_type != null);

        var result: ?SoundId = null;

        if (self.debug_asset_type) |asset_type| {
            std.debug.assert(asset_type.one_past_last_asset_index < self.assets.len);

            result = SoundId { .value = asset_type.one_past_last_asset_index };
            const source: *AssetSource = &self.asset_sources[result.?.value];
            const hha: *HHAAsset = &self.assets[result.?.value];

            self.debug_asset_type.?.one_past_last_asset_index += 1;

            hha.first_tag_index = self.tag_count;
            hha.one_past_last_tag_index = self.tag_count;
            hha.info = .{
                .sound = HHASound{
                    .channel_count = 0,
                    .sample_count = sample_count,
                    .next_id_to_play = SoundId{ .value = 0 },
                },
            };

            source.asset_type = .Sound;
            source.file_name = file_name;
            source.first_sample_index = first_sample_index;

            self.asset_index = result.?.value;
        }

        return result;
    }

    fn addTag(self: *Assets, tag_id: AssetTagId, value: f32) void {
        std.debug.assert(self.asset_index != 0);

        var hha = &self.assets[self.asset_index];
        hha.one_past_last_tag_index += 1;
        const tag: *HHATag = &self.tags[self.tag_count];
        self.tag_count += 1;

        tag.id = tag_id.toInt();
        tag.value = value;
    }

    fn endAssetType(self: *Assets) void {
        if (self.debug_asset_type) |asset_type| {
            self.asset_count = asset_type.one_past_last_asset_index;
            self.debug_asset_type = null;
            self.asset_index = 0;
        }
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Prepare the asset pack.
    var result = Assets{
        .asset_count = 1,
        .tag_count = 1,
        .debug_asset_type = null,
        .asset_index = 0,
    };

    result.beginAssetType(.Shadow);
    _ = result.addBitmapAsset("test/test_hero_shadow.bmp", 0.5, 0.15668203);
    result.endAssetType();

    result.beginAssetType(.Tree);
    _ = result.addBitmapAsset("test2/tree00.bmp", 0.49382716, 0.29565218);
    result.endAssetType();

    result.beginAssetType(.Sword);
    _ = result.addBitmapAsset("test2/rock03.bmp", 0.5, 0.65625);
    result.endAssetType();

    result.beginAssetType(.Grass);
    _ = result.addBitmapAsset("test2/grass00.bmp", null, null);
    _ = result.addBitmapAsset("test2/grass01.bmp", null, null);
    result.endAssetType();

    result.beginAssetType(.Stone);
    _ = result.addBitmapAsset("test2/ground00.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground01.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground02.bmp", null, null);
    _ = result.addBitmapAsset("test2/ground03.bmp", null, null);
    result.endAssetType();

    result.beginAssetType(.Tuft);
    _ = result.addBitmapAsset("test2/tuft00.bmp", null, null);
    _ = result.addBitmapAsset("test2/tuft01.bmp", null, null);
    _ = result.addBitmapAsset("test2/tuft02.bmp", null, null);
    result.endAssetType();

    const angle_right: f32 = 0;
    const angle_back: f32 = 0.25 * shared.TAU32;
    const angle_left: f32 = 0.5 * shared.TAU32;
    const angle_front: f32 = 0.75 * shared.TAU32;
    const hero_align_x = 0.5;
    const hero_align_y = 0.156682029;

    result.beginAssetType(.Head);
    _ = result.addBitmapAsset("test/test_hero_right_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_head.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    result.beginAssetType(.Cape);
    _ = result.addBitmapAsset("test/test_hero_right_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_cape.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    result.beginAssetType(.Torso);
    _ = result.addBitmapAsset("test/test_hero_right_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_right);
    _ = result.addBitmapAsset("test/test_hero_back_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_back);
    _ = result.addBitmapAsset("test/test_hero_left_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_left);
    _ = result.addBitmapAsset("test/test_hero_front_torso.bmp", hero_align_x, hero_align_y);
    result.addTag(.FacingDirection, angle_front);
    result.endAssetType();

    result.beginAssetType(.Bloop);
    _ = result.addSoundAsset("test3/bloop_00.wav");
    _ = result.addSoundAsset("test3/bloop_01.wav");
    _ = result.addSoundAsset("test3/bloop_02.wav");
    _ = result.addSoundAsset("test3/bloop_03.wav");
    result.endAssetType();

    result.beginAssetType(.Crack);
    _ = result.addSoundAsset("test3/crack_00.wav");
    result.endAssetType();

    result.beginAssetType(.Drop);
    _ = result.addSoundAsset("test3/drop_00.wav");
    result.endAssetType();

    result.beginAssetType(.Glide);
    _ = result.addSoundAsset("test3/glide_00.wav");
    result.endAssetType();

    result.beginAssetType(.Music);
    const one_music_chunk = 2 * 48000;
    const total_music_sample_count = 7468095;
    var first_sample_index: u32 = 0;
    var last_music: ?SoundId = null;
    while (first_sample_index < total_music_sample_count) : (first_sample_index += one_music_chunk) {
        var sample_count = total_music_sample_count - first_sample_index;
        if (sample_count > one_music_chunk) {
            sample_count = one_music_chunk;
        }

        const this_music = result.addSoundSectionAsset("test3/music_test.wav", first_sample_index, sample_count);
        if (last_music) |last| {
            if (this_music) |this| {
                result.assets[last.value].info.sound.next_id_to_play = this;
            }
        }

        last_music = this_music;
    }
    result.endAssetType();

    result.beginAssetType(.Glide);
    _ = result.addSoundAsset("test3/puhp_00.wav");
    _ = result.addSoundAsset("test3/puhp_01.wav");
    result.endAssetType();

    // Open or create a file.
    var opt_out: ?std.fs.File = null;
    const file_path = "test.hha";
    if (std.fs.cwd().openFile(file_path, .{ .mode = .write_only })) |file| {
        opt_out = file;
    } else |err| {
        std.debug.print("Unable to open '{s}': {s}", .{ file_path, @errorName(err) });

        opt_out = std.fs.cwd().createFile(file_path, .{}) catch |create_err| {
            std.debug.print("Unable to create '{s}': {s}", .{ file_path, @errorName(create_err) });
            std.process.exit(1);
        };
    }

    // Write the results out to the file.
    if (opt_out) |out| {
        defer out.close();

        var header = HHAHeader{
            .tag_count = result.tag_count,
            .asset_type_count = ASSET_TYPE_ID_COUNT,
            .asset_count = result.asset_count,
        };

        const tag_array_size: u32 = header.tag_count * @sizeOf(HHATag);
        const asset_type_array_size: u32 = header.asset_type_count * @sizeOf(HHAAssetType);
        const asset_array_size: u32 = header.asset_count * @sizeOf(HHAAsset);

        header.tags = @sizeOf(HHAHeader);
        header.asset_types = header.tags + tag_array_size;
        header.assets = header.asset_types + asset_type_array_size;
        header.assets = (header.assets + @alignOf(HHAAsset) - 1) & ~@as(u32, @alignOf(HHAAsset) - 1);

        var bytes_written: usize = 0;
        bytes_written += try out.write(std.mem.asBytes(&header));
        // std.debug.print("Bytes written after header: {d}\n", .{ bytes_written });
        // std.debug.print("Tags: Expected: {d}, actual: {d}\n", .{header.tags, bytes_written});
        bytes_written += try out.write(std.mem.asBytes(&result.tags)[0..tag_array_size]);
        // std.debug.print("Bytes written after tags: {d}\n", .{ bytes_written });
        // std.debug.print("Asset types: Expected: {d}, actual: {d}\n", .{header.asset_types, bytes_written});
        bytes_written += try out.write(std.mem.asBytes(&result.asset_types));
        // std.debug.print("Bytes written after asset types: {d}\n", .{ bytes_written });
        // std.debug.print("Assets: Expected: {d}, actual: {d}\n", .{header.assets, bytes_written});

        try out.seekBy(asset_array_size);
        var asset_index: u32 = 1;
        while (asset_index < header.asset_count) : (asset_index += 1) {
            const source: *AssetSource = &result.asset_sources[asset_index];
            var dest: *HHAAsset = &result.assets[asset_index];

            dest.data_offset = try out.getPos();

            switch (source.asset_type) {
                .Bitmap => {
                    const bmp = loadBMP(source.file_name, allocator);
                    defer allocator.free(bmp.free);

                    dest.info.bitmap.dim[0] = @intCast(bmp.width);
                    dest.info.bitmap.dim[1] = @intCast(bmp.height);

                    std.debug.assert((bmp.width * 4) == bmp.pitch);
                    const size: usize = @as(usize, @intCast(bmp.width)) * @as(usize, @intCast(bmp.height * 4));
                    const bytes: []const u8 = @as([*]const u8, @ptrCast(bmp.memory.?))[0..size];
                    bytes_written += try out.write(bytes);
                    // std.debug.print("Expected size: {d}, size: {d}\n", .{ size, bytes.len });
                    // std.debug.print("Bytes written after bmp: {d}\n", .{ bytes_written });
                },
                .Sound => {
                    const wav = loadWAV(source.file_name, source.first_sample_index, dest.info.sound.sample_count, allocator);
                    defer allocator.free(wav.free);

                    dest.info.sound.sample_count = wav.sample_count;
                    dest.info.sound.channel_count = wav.channel_count;

                    var channel_index: u32 = 0;
                    while (channel_index < wav.channel_count) : (channel_index += 1) {
                        const size: usize = dest.info.sound.sample_count * @sizeOf(i16);
                        const bytes: []const u8 = @as([*]const u8, @ptrCast(wav.samples[channel_index].?))[0..size];
                        bytes_written += try out.write(bytes);
                        // std.debug.print("Expected size: {d}, size: {d}\n", .{ size, bytes.len });
                        // std.debug.print("Bytes written after wav: {d}\n", .{ bytes_written });
                    }
                }
            }
        }
        try out.seekTo(header.assets);
        bytes_written += try out.write(std.mem.asBytes(&result.assets)[0..asset_array_size]);

        if (gpa.detectLeaks()) {
            std.log.debug("Memory leaks detected.\n", .{});
        }

        std.debug.print("Bytes written: {d}", .{ bytes_written });
    }
}
