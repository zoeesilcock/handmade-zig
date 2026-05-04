const shared = @import("shared.zig");
const math = @import("math.zig");
const sim = @import("sim.zig");
const entities = @import("entities.zig");
const file_formats = @import("file_formats.zig");
const world_gen = @import("world_gen.zig");
const world_mod = @import("world.zig");
const brains = @import("brains.zig");
const std = @import("std");

pub const shadow_alpha = 0.5;

// Types.
const Vector3 = math.Vector3;
const Color = math.Color;
const Color3 = math.Color3;
const Entity = entities.Entity;
const EntityFlags = entities.EntityFlags;
const EntityVisiblePiece = entities.EntityVisiblePiece;
const EntityVisiblePieceFlag = entities.EntityVisiblePieceFlag;
const TraversableReference = entities.TraversableReference;
const BitmapPiece = entities.BitmapPiece;
const Rectangle3 = math.Rectangle3;
const SimRegion = sim.SimRegion;
const WorldGenerator = world_gen.WorldGenerator;
const WorldPosition = world_mod.WorldPosition;
const AssetTagId = file_formats.AssetTagId;
const AssetBasicCategory = file_formats.AssetBasicCategory;
const HHAAlignPointType = file_formats.HHAAlignPointType;
const BrainId = brains.BrainId;
const BrainSlot = brains.BrainSlot;
const BrainHero = brains.BrainHero;
const BrainSnake = brains.BrainSnake;
const BrainMonster = brains.BrainMonster;
const BrainFamiliar = brains.BrainFamiliar;

pub const GenEntityTag = struct {
    tag_id: AssetTagId,
    value: f32,
};

pub const createEntityType: type =
    fn (region: *SimRegion, world_position: WorldPosition, standing_on: TraversableReference) *Entity;

pub const GenEntity = struct {
    next: ?*GenEntity,
    creator: *const createEntityType = undefined,

    tags: [14]GenEntityTag,
    tag_count: u32,
    flags: u32,
};

pub fn makeSimpleGroundedCollision(
    x_dimension: f32,
    y_dimension: f32,
    z_dimension: f32,
    opt_z_offset: ?f32,
) Rectangle3 {
    const z_offset: f32 = opt_z_offset orelse 0;
    const result: Rectangle3 = .fromCenterDimension(
        Vector3.new(0, 0, 0.5 * z_dimension + z_offset),
        Vector3.new(x_dimension, y_dimension, z_dimension),
    );

    return result;
}

pub fn addPiece(
    entity: *Entity,
    category: AssetBasicCategory,
    height: f32,
    offset: Vector3,
    color: Color,
    opt_movement_flags: ?u32,
) *EntityVisiblePiece {
    return addPieceV3(entity, category, .new(0, height, 0), offset, color, opt_movement_flags);
}

pub fn connectPiece(
    entity: *Entity,
    parent: *EntityVisiblePiece,
    parent_type: HHAAlignPointType,
    child: *EntityVisiblePiece,
    child_type: HHAAlignPointType,
) void {
    std.debug.assert(child.isBitmap());

    const bitmap: *BitmapPiece = &child.extra.bitmap;
    bitmap.parent_piece = @intCast(
        @as([*]EntityVisiblePiece, @ptrCast(parent)) - @as([*]EntityVisiblePiece, @ptrCast(&entity.pieces)),
    );
    bitmap.parent_align_type = @intCast(@intFromEnum(parent_type));
    bitmap.child_align_type = @intCast(@intFromEnum(child_type));

    std.debug.assert(@intFromPtr(parent) < @intFromPtr(child));
}

pub fn connectPieceToWorld(
    entity: *Entity,
    child: *EntityVisiblePiece,
    child_type: HHAAlignPointType,
) void {
    _ = entity;

    std.debug.assert(child.isBitmap());

    const bitmap: *BitmapPiece = &child.extra.bitmap;
    bitmap.parent_piece = 0;
    bitmap.parent_align_type = @intCast(@intFromEnum(HHAAlignPointType.None));
    bitmap.child_align_type = @intCast(@intFromEnum(child_type));
}

fn addPieceLight(
    entity: *Entity,
    radius: f32,
    offset: Vector3,
    emission: f32,
    color: Color3,
) *EntityVisiblePiece {
    return addPieceV3(
        entity,
        .None,
        .new(radius, radius, radius),
        offset,
        color.toColor(emission),
        @intFromEnum(EntityVisiblePieceFlag.Light),
    );
}

pub fn addPieceV3(
    entity: *Entity,
    category: AssetBasicCategory,
    dimension: Vector3,
    offset: Vector3,
    color: Color,
    opt_movement_flags: ?u32,
) *EntityVisiblePiece {
    std.debug.assert(entity.piece_count < entity.pieces.len);

    var piece: *EntityVisiblePiece = &entity.pieces[entity.piece_count];
    entity.piece_count += 1;

    piece.category = category;
    piece.dimension = dimension;
    piece.offset = offset;
    piece.color = color;
    piece.flags = opt_movement_flags orelse 0;

    return piece;
}

pub fn addEntity(region: *SimRegion) *Entity {
    const entity: *Entity = sim.createEntity(region, sim.allocateEntityId(region));

    entity.x_axis = .new(1, 0);
    entity.y_axis = .new(0, 1);

    return entity;
}

pub fn placeEntity(region: *SimRegion, entity: *Entity, chunk_position: WorldPosition) void {
    entity.position = world_mod.subtractPositions(region.world, &chunk_position, &region.origin);
}

fn initHitPoints(entity: *Entity, count: u32) void {
    std.debug.assert(count <= entity.hit_points.len);

    entity.hit_point_max = count;

    var hit_point_index: u32 = 0;
    while (hit_point_index < entity.hit_point_max) : (hit_point_index += 1) {
        const hit_point = &entity.hit_points[hit_point_index];

        hit_point.flags = 0;
        hit_point.filled_amount = shared.HIT_POINT_SUB_COUNT;
    }
}

pub fn addCat(region: *SimRegion, world_position: WorldPosition, standing_on: TraversableReference) *Entity {
    var entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    // entity.brain_slot = BrainSlot.forField(BrainCat, "body");
    // entity.brain_id = sim.addBrain(region);
    entity.occupying = standing_on;

    const body: *EntityVisiblePiece = addPiece(entity, .Body, 1, .new(0, 0, 0), .white(), null);
    const head: *EntityVisiblePiece = addPiece(entity, .Head, 1, .new(0, 0, 0.1), .white(), null);

    connectPieceToWorld(entity, body, .Default);
    connectPiece(entity, body, .BaseOfNeck, head, .Default);

    _ = world_position;
    const position: WorldPosition = world_mod.mapIntoChunkSpace(
        region.world,
        region.origin,
        standing_on.getSimSpaceTraversable().position,
    );
    placeEntity(region, entity, position);

    return entity;
}

pub fn addOrphan(region: *SimRegion, world_position: WorldPosition, standing_on: TraversableReference) *Entity {
    var entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    // entity.brain_slot = BrainSlot.forField(BrainOrphan, "body");
    // entity.brain_id = sim.addBrain(region);
    entity.occupying = standing_on;

    const body: *EntityVisiblePiece = addPiece(entity, .Body, 1, .new(0, 0, 0), .white(), null);
    const head: *EntityVisiblePiece = addPiece(entity, .Head, 1, .new(0, 0, 0.1), .white(), null);

    connectPieceToWorld(entity, body, .Default);
    connectPiece(entity, body, .BaseOfNeck, head, .Default);

    _ = world_position;
    const position: WorldPosition = world_mod.mapIntoChunkSpace(
        region.world,
        region.origin,
        standing_on.getSimSpaceTraversable().position,
    );
    placeEntity(region, entity, position);

    return entity;
}

fn addMonster(region: *SimRegion, world_position: WorldPosition, standing_on: TraversableReference) void {
    var entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forField(BrainMonster, "body");
    entity.brain_id = sim.addBrain(region);
    entity.occupying = standing_on;

    initHitPoints(entity, 3);

    _ = addPiece(entity, .Shadow, 4.5, .zero(), .new(1, 1, 1, 0.5), null);
    _ = addPiece(entity, .Body, 4.5, .zero(), .white(), null);

    placeEntity(region, entity, world_position);
}

fn addSnakeSegment(
    region: *SimRegion,
    world_position: WorldPosition,
    standing_on: TraversableReference,
    brain_id: BrainId,
    segment_index: u32,
) void {
    var entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forIndexedField(BrainSnake, "segments", segment_index);
    entity.brain_id = brain_id;
    entity.occupying = standing_on;

    initHitPoints(entity, 3);

    _ = addPiece(entity, .Shadow, 1.5, .zero(), .new(1, 1, 1, 0.5), null);
    _ = addPiece(entity, if (segment_index != 0) .Body else .Head, 1.5, .zero(), .white(), null);
    addPieceLight(entity, 0.1, .new(0, 0, 0.5), 1.0, .new(1, 1, 0));

    placeEntity(region, entity, world_position);
}

pub fn addLamp(
    region: *SimRegion,
    world_position: WorldPosition,
    color: Color3,
) void {
    const entity = addEntity(region);

    _ = addPieceLight(entity, 0.5, .new(0, 0, 2.5), 1.0, color);

    placeEntity(region, entity, world_position);
}

fn addFamiliar(region: *SimRegion, world_position: WorldPosition, standing_on: TraversableReference) void {
    const entity = addEntity(region);

    entity.addFlags(EntityFlags.Collides.toInt());

    entity.brain_slot = BrainSlot.forField(BrainFamiliar, "head");
    entity.brain_id = sim.addBrain(region);
    entity.occupying = standing_on;

    _ = addPiece(entity, .Shadow, 2.5, .zero(), .new(1, 1, 1, shadow_alpha), null);
    _ = addPiece(entity, .Head, 2.5, .zero(), .white(), @intFromEnum(EntityVisiblePieceFlag.BobOffset));

    placeEntity(region, entity, world_position);
}
