const std = @import("std");
const shared = @import("shared.zig");
const types = @import("types.zig");
const debug_interface = @import("debug_interface.zig");

// Types.
const DebugTable = debug_interface.DebugTable;
const PlatformMemoryBlock = shared.PlatformMemoryBlock;
const PlatformMemoryBlockFlags = shared.PlatformMemoryBlockFlags;
const String = types.String;
const Buffer = types.Buffer;
const DebugInterface = debug_interface.DebugInterface;
const DebugEvent = debug_interface.DebugEvent;

// Build options.
pub const INTERNAL = @import("build_options").internal;

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
    pub fn pushSize(
        self: *MemoryArena,
        size: MemoryIndex,
        in_params: ?ArenaPushParams,
        comptime source: std.builtin.SourceLocation,
    ) [*]u8 {
        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushSize") else "";
        return pushSize_(self, size, in_params, guid);
    }

    pub fn pushSize_(
        self: *MemoryArena,
        size: MemoryIndex,
        in_params: ?ArenaPushParams,
        comptime guid: [*:0]const u8,
    ) [*]u8 {
        var result: [*]u8 = undefined;
        const params = in_params orelse ArenaPushParams.default();

        std.debug.assert(params.alignment <= 128);
        std.debug.assert(types.isPow2(params.alignment));

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

            DebugInterface.blockAllocation(self.current_block, guid);
        }

        std.debug.assert((self.current_block.?.used + aligned_size) <= self.current_block.?.size);

        const alignment_offset = self.getAlignmentOffset(params.alignment);
        const offset_in_block: usize = self.current_block.?.used + alignment_offset;
        result = @ptrCast(self.current_block.?.base + offset_in_block);
        self.current_block.?.used += aligned_size;

        std.debug.assert(aligned_size >= size);

        // This is just to guarantee that nobody passed in an alignment on their first allocation that was greater
        // than the page alignment.
        std.debug.assert(self.current_block.?.used <= self.current_block.?.size);

        if (params.flags & @intFromEnum(ArenaPushFlag.ClearToZero) != 0) {
            zeroSize(size, @ptrCast(result));
        }

        DebugInterface.recordAllocation(self.current_block, guid, aligned_size, size, offset_in_block);

        return result;
    }

    pub fn pushStruct(
        self: *MemoryArena,
        comptime T: type,
        params: ?ArenaPushParams,
        comptime source: std.builtin.SourceLocation,
    ) *T {
        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushStruct") else "";
        return @as(*T, @ptrCast(@alignCast(pushSize_(self, @sizeOf(T), params, guid))));
    }

    pub fn pushArray(
        self: *MemoryArena,
        count: MemoryIndex,
        comptime T: type,
        params: ?ArenaPushParams,
        comptime source: std.builtin.SourceLocation,
    ) [*]T {
        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushArray") else "";
        return @as([*]T, @ptrCast(@alignCast(pushSize_(self, @sizeOf(T) * count, params, guid))));
    }

    pub fn pushStringZ(
        self: *MemoryArena,
        source_string: [*:0]const u8,
        comptime source: std.builtin.SourceLocation,
    ) [*:0]const u8 {
        var size: u32 = types.stringLength(source_string);

        // Include the sentinel.
        size += 1;

        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushStringZ") else "";
        var dest = self.pushSize_(size, ArenaPushParams.noClear(), guid);

        var char_index: u32 = 0;
        while (char_index < size) : (char_index += 1) {
            dest[char_index] = source_string[char_index];
        }

        return @ptrCast(dest);
    }

    pub fn pushBuffer(
        self: *MemoryArena,
        size: usize,
        comptime source: std.builtin.SourceLocation,
    ) Buffer {
        var result: Buffer = .{ .count = size };
        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushBuffer") else "";
        result.data = @ptrCast(self.pushSize_(result.count, null, guid));
        return result;
    }

    pub fn pushString(
        self: *MemoryArena,
        source_string: [*:0]const u8,
        comptime source: std.builtin.SourceLocation,
    ) String {
        var result: String = .{
            .count = types.stringLength(source_string),
        };
        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushString") else "";
        result.data = @ptrCast(self.pushCopy_(result.count, @ptrCast(@constCast(source_string)), guid));
        return result;
    }

    pub fn pushStringSized(
        self: *MemoryArena,
        source_string: String,
        comptime source: std.builtin.SourceLocation,
    ) String {
        var result: String = .{
            .count = source_string.count,
        };
        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushStringSized") else "";
        result.data = @ptrCast(self.pushCopy_(result.count, @ptrCast(@constCast(source_string.data)), guid));
        return result;
    }

    pub fn pushAndNullTerminateString(
        self: *MemoryArena,
        length: u32,
        source_string: [*:0]const u8,
        comptime source: std.builtin.SourceLocation,
    ) [*:0]const u8 {
        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushAndNullTerminateString") else "";
        var dest = self.pushSize_(length + 1, ArenaPushParams.noClear(), guid);

        var char_index: u32 = 0;
        while (char_index < length) : (char_index += 1) {
            dest[char_index] = source_string[char_index];
        }
        dest[length] = 0;

        return @ptrCast(dest);
    }

    pub fn pushCopy(
        self: *MemoryArena,
        size: MemoryIndex,
        source_string: *const anyopaque,
        comptime source: std.builtin.SourceLocation,
    ) *anyopaque {
        const guid = comptime if (INTERNAL) DebugEvent.debugName(source, null, "pushCopy") else "";
        return self.pushCopy_(size, source_string, guid);
    }

    pub fn pushCopy_(
        self: *MemoryArena,
        size: MemoryIndex,
        source_string: *const anyopaque,
        comptime guid: [*:0]const u8,
    ) *anyopaque {
        return shared.copy(size, source_string, @ptrCast(self.pushSize_(size, null, guid)));
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
            DebugInterface.blockFree(current_block);
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
            DebugInterface.blockTruncate(current_block);
        }

        std.debug.assert(self.temp_count > 0);
        self.temp_count -= 1;
    }

    pub fn keepTemporaryMemory(self: *MemoryArena, temp_memory: TemporaryMemory) void {
        _ = temp_memory;
        std.debug.assert(self.temp_count > 0);
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

    const struct_ptr: *anyopaque = bootstrap.pushSize(struct_size, params, @src());
    const arena_ptr: *MemoryArena = @ptrFromInt(@intFromPtr(struct_ptr) + offset_to_arena);
    arena_ptr.* = bootstrap;

    return struct_ptr;
}
