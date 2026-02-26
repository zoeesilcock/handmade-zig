const std = @import("std");
const shared = @import("shared.zig");
const types = @import("types.zig");
const debug_interface = @import("debug_interface.zig");

// Types.
const DebugTable = debug_interface.DebugTable;
const PlatformMemoryBlock = shared.PlatformMemoryBlock;
const PlatformMemoryBlockFlags = shared.PlatformMemoryBlockFlags;
const String = shared.String;

pub const MemoryIndex = usize;

pub const TemporaryMemory = struct {
    arena: *MemoryArena,
    block: ?*PlatformMemoryBlock = null,
    used: MemoryIndex = 0,
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

pub const ArenaBootstrapParams = extern struct {
    allocation_flags: u64,
    minimum_block_size: MemoryIndex,

    pub fn default() ArenaBootstrapParams {
        return .{
            .allocation_flags = 0,
            .minimum_block_size = 0,
        };
    }

    pub fn nonRestored() ArenaBootstrapParams {
        var result: ArenaBootstrapParams = .default();

        result.allocation_flags = @intFromEnum(PlatformMemoryBlockFlags.NotRestored);

        return result;
    }
};

pub const MemoryArena = extern struct {
    current_block: ?*PlatformMemoryBlock = undefined,
    minimum_block_size: MemoryIndex = 0,
    allocation_flags: u64 = 0,
    temp_count: i32 = 0,

    pub fn setMinimumBlockSize(self: *MemoryArena, minimum_block_size: MemoryIndex) void {
        self.minimum_block_size = minimum_block_size;
    }

    fn getAlignmentOffset(self: *MemoryArena, alignment: MemoryIndex) MemoryIndex {
        var alignment_offset: MemoryIndex = 0;
        if (self.current_block) |current_block| {
            const result_pointer: MemoryIndex = @intFromPtr(current_block.base + current_block.used);
            const alignment_mask: MemoryIndex = alignment - 1;

            if (result_pointer & alignment_mask != 0) {
                alignment_offset = alignment - (result_pointer & alignment_mask);
            }
        }

        return alignment_offset;
    }

    pub fn getEffectiveSizeFor(self: *MemoryArena, size: MemoryIndex, in_params: ?ArenaPushParams) MemoryIndex {
        const params = in_params orelse ArenaPushParams.default();
        const alignment_offset = self.getAlignmentOffset(params.alignment);
        const aligned_size = size + alignment_offset;
        return aligned_size;
    }

    pub fn pushSize(self: *MemoryArena, size: MemoryIndex, in_params: ?ArenaPushParams) [*]u8 {
        var result: [*]u8 = undefined;
        const params = in_params orelse ArenaPushParams.default();

        var aligned_size: MemoryIndex = 0;
        if (self.current_block != null) {
            aligned_size = self.getEffectiveSizeFor(size, params);
        }

        if (self.current_block == null or (self.current_block.?.used + aligned_size) > self.current_block.?.size) {
            aligned_size = size;

            if (self.allocation_flags &
                (@intFromEnum(PlatformMemoryBlockFlags.OverflowCheck) |
                    @intFromEnum(PlatformMemoryBlockFlags.UnderflowCheck)) != 0)
            {
                self.minimum_block_size = 0;
                aligned_size = types.alignPow2(@intCast(size), params.alignment);
            } else if (self.minimum_block_size == 0) {
                self.minimum_block_size = 1024 * 1024;
            }

            const block_size: MemoryIndex = @max(aligned_size, self.minimum_block_size);
            var new_block: *PlatformMemoryBlock =
                @ptrCast(shared.platform.allocateMemory(block_size, self.allocation_flags).?);
            new_block.arena_prev = self.current_block;
            self.current_block = new_block;
        }

        std.debug.assert((self.current_block.?.used + aligned_size) <= self.current_block.?.size);

        const alignment_offset = self.getAlignmentOffset(params.alignment);
        result = @ptrCast(self.current_block.?.base + self.current_block.?.used + alignment_offset);
        self.current_block.?.used += aligned_size;

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

    pub fn pushStringZ(self: *MemoryArena, source: [*:0]const u8) [*:0]const u8 {
        var size: u32 = shared.stringLength(source);

        // Include the sentinel.
        size += 1;

        var dest = self.pushSize(size, ArenaPushParams.noClear());

        var char_index: u32 = 0;
        while (char_index < size) : (char_index += 1) {
            dest[char_index] = source[char_index];
        }

        return @ptrCast(dest);
    }

    pub fn pushString(self: *MemoryArena, source: [*:0]const u8) String {
        var result: String = .{
            .count = shared.stringLength(source),
        };
        result.data = @ptrCast(self.pushCopy(result.count, @ptrCast(@constCast(source))));
        return result;
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
        var result = TemporaryMemory{
            .arena = self,
        };

        result.block = self.current_block;
        if (self.current_block) |current_block| {
            result.used = current_block.used;
        }

        self.temp_count += 1;

        return result;
    }

    fn freeLastBlock(self: *MemoryArena) void {
        if (self.current_block) |current_block| {
            self.current_block = current_block.arena_prev;
            shared.platform.deallocateMemory(current_block);
        }
    }

    pub fn endTemporaryMemory(self: *MemoryArena, temp_memory: TemporaryMemory) void {
        const arena: *MemoryArena = temp_memory.arena;

        while (@intFromPtr(arena.current_block) != @intFromPtr(temp_memory.block)) {
            arena.freeLastBlock();
        }

        if (arena.current_block) |current_block| {
            std.debug.assert(current_block.used >= temp_memory.used);
            current_block.used = temp_memory.used;
            std.debug.assert(self.temp_count > 0);
        }

        self.temp_count -= 1;
    }

    pub fn clear(self: *MemoryArena) void {
        while (self.current_block != null) {
            // Because the arena itself may be stored in the last block,
            // we must ensure that we don't look at it after freeing.
            const this_is_last_block: bool = self.current_block.?.arena_prev == null;
            self.freeLastBlock();
            if (this_is_last_block) {
                break;
            }
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

pub fn copyArray(count: MemoryIndex, comptime T: type, source: *anyopaque, dest: *anyopaque) [*]T {
    return @ptrCast(@alignCast(copy(count * @sizeOf(T), source, dest)));
}

pub fn bootstrapPushStruct(
    comptime T: type,
    comptime arena_member: []const u8,
    bootstrap_params: ?ArenaBootstrapParams,
    params: ?ArenaPushParams,
) *T {
    return @as(*T, @ptrCast(@alignCast(bootsrapPushSize(@sizeOf(T), @offsetOf(T, arena_member), bootstrap_params, params))));
}

pub fn bootsrapPushSize(
    struct_size: MemoryIndex,
    offset_to_arena: MemoryIndex,
    in_bootstrap_params: ?ArenaBootstrapParams,
    params: ?ArenaPushParams,
) *anyopaque {
    const bootstrap_params = in_bootstrap_params orelse ArenaBootstrapParams.default();

    var bootstrap: MemoryArena = .{};
    bootstrap.allocation_flags = bootstrap_params.allocation_flags;
    bootstrap.minimum_block_size = bootstrap_params.minimum_block_size;

    const struct_ptr: *anyopaque = bootstrap.pushSize(struct_size, params);
    const arena_ptr: *MemoryArena = @ptrFromInt(@intFromPtr(struct_ptr) + offset_to_arena);
    arena_ptr.* = bootstrap;

    return struct_ptr;
}
