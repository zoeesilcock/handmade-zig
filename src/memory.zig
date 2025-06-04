const std = @import("std");
const shared = @import("shared.zig");
const debug_interface = @import("debug_interface.zig");

// Types.
const DebugTable = debug_interface.DebugTable;

pub const MemoryIndex = usize;

pub const TemporaryMemory = struct {
    arena: *MemoryArena,
    base: [*]u8,
    used: MemoryIndex,
};

const ArenaPushFlag = enum(u32) {
    ClearToZero = 0x1,
};

pub const ArenaPushParams = extern struct {
    flags: u32,
    alignment: u32,

    pub fn default() ArenaPushParams {
        return ArenaPushParams{
            .flags = @intFromEnum(ArenaPushFlag.ClearToZero),
            .alignment = 4,
        };
    }

    pub fn aligned(alignment: u32, clear: bool) ArenaPushParams {
        var result = ArenaPushParams.default();
        if (clear) {
            result.flags |= @intFromEnum(ArenaPushFlag.ClearToZero);
        } else {
            result.flags &= ~@intFromEnum(ArenaPushFlag.ClearToZero);
        }
        result.alignment = alignment;
        return result;
    }

    pub fn alignedNoClear(alignment: u32) ArenaPushParams {
        var result = ArenaPushParams.default();
        result.flags &= ~@intFromEnum(ArenaPushFlag.ClearToZero);
        result.alignment = alignment;
        return result;
    }

    pub fn noClear() ArenaPushParams {
        var result = ArenaPushParams.default();
        result.flags &= ~@intFromEnum(ArenaPushFlag.ClearToZero);
        return result;
    }
};

const MemoryBlockFooter = extern struct {
    base: [*]u8 = undefined,
    size: MemoryIndex = 0,
    used: MemoryIndex = 0,
};

pub const MemoryArena = extern struct {
    size: MemoryIndex = 0,
    base: [*]u8 = undefined,
    used: MemoryIndex = 0,
    minimum_block_size: MemoryIndex = 0,
    block_count: u32 = 0,
    temp_count: i32 = 0,

    pub fn setMinimumBlockSize(self: *MemoryArena, minimum_block_size: MemoryIndex) void {
        self.minimum_block_size = minimum_block_size;
    }

    fn getAlignmentOffset(self: *MemoryArena, alignment: MemoryIndex) MemoryIndex {
        var alignment_offset: MemoryIndex = 0;
        const result_pointer: MemoryIndex = @intFromPtr(self.base + self.used);
        const alignment_mask: MemoryIndex = alignment - 1;

        if (result_pointer & alignment_mask != 0) {
            alignment_offset = alignment - (result_pointer & alignment_mask);
        }

        return alignment_offset;
    }

    pub fn getRemainingSize(self: *MemoryArena, in_params: ?ArenaPushParams) MemoryIndex {
        const params = in_params orelse ArenaPushParams.default();
        return self.size - (self.used + self.getAlignmentOffset(params.alignment));
    }

    pub fn makeSubArena(self: *MemoryArena, arena: *MemoryArena, size: MemoryIndex, params: ?ArenaPushParams) void {
        arena.size = size;
        arena.base = self.pushSize(size, params);
        arena.used = 0;
        arena.temp_count = 0;
    }

    pub fn getEffectiveSizeFor(self: *MemoryArena, size: MemoryIndex, in_params: ?ArenaPushParams) MemoryIndex {
        const params = in_params orelse ArenaPushParams.default();
        const alignment_offset = self.getAlignmentOffset(params.alignment);
        const aligned_size = size + alignment_offset;
        return aligned_size;
    }

    pub fn hasRoomFor(self: *MemoryArena, size: MemoryIndex, params: ?ArenaPushParams) bool {
        const effective_size = self.getEffectiveSizeFor(size, params);
        return (self.used + effective_size) <= self.size;
    }

    fn getFooter(self: *MemoryArena) *MemoryBlockFooter {
        const result: *MemoryBlockFooter = @ptrFromInt(@intFromPtr(self.base) + self.size);
        return result;
    }

    pub fn pushSize(self: *MemoryArena, size: MemoryIndex, in_params: ?ArenaPushParams) [*]u8 {
        const params = in_params orelse ArenaPushParams.default();
        var aligned_size = self.getEffectiveSizeFor(size, params);

        if ((self.used + aligned_size) > self.size) {
            if (self.minimum_block_size == 0) {
                self.minimum_block_size = 1024 * 1024;
            }

            const save: MemoryBlockFooter = .{
                .base = self.base,
                .size = self.size,
                .used = self.used,
            };

            aligned_size = size; // The base will automatically be aligned now.
            const block_size: MemoryIndex = @max(aligned_size + @sizeOf(MemoryBlockFooter), self.minimum_block_size);
            self.size = block_size - @sizeOf(MemoryBlockFooter);
            self.base = @ptrCast(shared.platform.allocateMemory(block_size).?);
            self.used = 0;
            self.block_count += 1;

            const footer = self.getFooter();
            footer.* = save;
        }

        std.debug.assert((self.used + aligned_size) <= self.size);

        const alignment_offset = self.getAlignmentOffset(params.alignment);
        const result: [*]u8 = @ptrCast(self.base + self.used + alignment_offset);
        self.used += aligned_size;

        std.debug.assert(aligned_size >= size);

        if (params.flags & @intFromEnum(ArenaPushFlag.ClearToZero) != 0) {
            zeroSize(size, @ptrCast(result));
        }

        return result;
    }

    pub fn pushStruct(self: *MemoryArena, comptime T: type, params: ?ArenaPushParams) *T {
        return @as(*T, @ptrCast(@alignCast(pushSize(self, @sizeOf(T), params))));
    }

    pub fn pushArray(self: *MemoryArena, count: MemoryIndex, comptime T: type, params: ?ArenaPushParams) [*]T {
        return @as([*]T, @ptrCast(@alignCast(pushSize(self, @sizeOf(T) * count, params))));
    }

    pub fn pushString(self: *MemoryArena, source: [*:0]const u8) [*:0]const u8 {
        var size: u32 = 0;

        var char_index: u32 = 0;
        while (source[char_index] != 0) : (char_index += 1) {
            size += 1;
        }

        // Include the sentinel.
        size += 1;

        var dest = self.pushSize(size, ArenaPushParams.noClear());

        char_index = 0;
        while (char_index < size) : (char_index += 1) {
            dest[char_index] = source[char_index];
        }

        return @ptrCast(dest);
    }

    pub fn pushAndNullTerminateString(self: *MemoryArena, length: u32, source: [*:0]const u8) [*:0]const u8 {
        var dest = self.pushSize(length + 1, ArenaPushParams.noClear());

        var char_index: u32 = 0;
        while (char_index < length) : (char_index += 1) {
            dest[char_index] = source[char_index];
        }
        dest[length] = 0;

        return @ptrCast(dest);
    }

    pub fn pushCopy(self: *MemoryArena, size: MemoryIndex, source: *anyopaque) *anyopaque {
        return copy(size, source, @ptrCast(self.pushSize(size, null)));
    }

    pub fn beginTemporaryMemory(self: *MemoryArena) TemporaryMemory {
        const result = TemporaryMemory{
            .arena = self,
            .base = self.base,
            .used = self.used,
        };

        self.temp_count += 1;

        return result;
    }

    fn freeLastBlock(self: *MemoryArena) void {
        const free: [*]u8 = self.base;
        const footer: *MemoryBlockFooter = self.getFooter();

        self.base = footer.base;
        self.size = footer.size;
        self.used = footer.used;

        shared.platform.deallocateMemory(free);

        self.block_count -= 1;
    }

    pub fn endTemporaryMemory(self: *MemoryArena, temp_memory: TemporaryMemory) void {
        const arena: *MemoryArena = temp_memory.arena;

        while (@intFromPtr(arena.base) != @intFromPtr(temp_memory.base)) {
            arena.freeLastBlock();
        }

        std.debug.assert(self.used >= temp_memory.used);
        self.used = temp_memory.used;
        std.debug.assert(self.temp_count > 0);
        self.temp_count -= 1;
    }

    pub fn clear(self: *MemoryArena) void {
        while (self.block_count > 0) {
            self.freeLastBlock();
        }
    }

    pub fn checkArena(self: *MemoryArena) void {
        std.debug.assert(self.temp_count == 0);
    }
};

pub fn zeroSize(size: MemoryIndex, ptr: *anyopaque) void {
    var byte: [*]u8 = @ptrCast(ptr);
    var index = size;
    while (index > 0) : (index -= 1) {
        byte[0] = 0;
        byte += 1;
    }
}

pub fn zeroStruct(comptime T: type, ptr: *T) void {
    zeroSize(@sizeOf(T), @ptrCast(ptr));
}

pub fn zeroArray(count: u32, ptr: *anyopaque) void {
    zeroSize(@sizeOf(ptr) * count, ptr);
}

pub fn copy(size: MemoryIndex, source_init: *anyopaque, dest_init: *anyopaque) *anyopaque {
    var source: [*]u8 = @ptrCast(source_init);
    var dest: [*]u8 = @ptrCast(dest_init);

    var index: MemoryIndex = size;
    while (index > 0) : (index -= 1) {
        dest[0] = source[0];

        source += 1;
        dest += 1;
    }

    return dest_init;
}

pub fn bootstrapPushStruct(comptime T: type, comptime arena_member: []const u8, params: ?ArenaPushParams) *T {
    return @as(*T, @ptrCast(@alignCast(bootsrapPushSize(@sizeOf(T), @offsetOf(T, arena_member), null, params))));
}

pub fn bootsrapPushSize(
    struct_size: MemoryIndex,
    offset_to_arena: MemoryIndex,
    mimimum_block_size: ?MemoryIndex,
    params: ?ArenaPushParams,
) *anyopaque {
    var bootstrap: MemoryArena = .{};
    bootstrap.minimum_block_size = mimimum_block_size orelse 0;
    const struct_ptr: *anyopaque = bootstrap.pushSize(struct_size, params);
    const arena_ptr: *MemoryArena = @ptrFromInt(@intFromPtr(struct_ptr) + offset_to_arena);
    arena_ptr.* = bootstrap;
    return struct_ptr;
}
