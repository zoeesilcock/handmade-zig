const std = @import("std");
const shared = @import("shared");

// Types.
const Tokenizer = shared.tokenizer.Tokenizer;
const Token = shared.tokenizer.Token;
const String = shared.types.String;

const MetaStruct = struct {
    name: []const u8,
    next: ?*MetaStruct,
};

var first_meta_struct: *MetaStruct = undefined;

pub fn parseIntrospectable(tokenizer: *Tokenizer, stdout: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    _ = tokenizer.requireToken(.OpenParen);

    if (tokenizer.parsing()) {
        try parseIntrospectionParams(tokenizer);

        var token = tokenizer.getToken();
        var previous_token: ?Token = null;
        var opt_type_token: ?Token = null;
        var opt_name_token: ?Token = null;
        while (true) : (token = tokenizer.getToken()) {
            if (token.token_type == .OpenBrace) {
                opt_type_token = previous_token;
                // tokenizer.advanceChars(-1);
                break;
            }

            if (token.token_type == .Equals) {
                opt_name_token = previous_token;
            }

            previous_token = token;
        }

        if (opt_type_token) |type_token| {
            if (type_token.equals("struct")) {
                try parseStruct(tokenizer, opt_name_token.?, stdout, allocator);
            } else {
                try stdout.print("ERROR: Introspection is only supported for structs right now :(.\n", .{});
            }
        }
    }
}

pub fn parseStruct(
    tokenizer: *Tokenizer,
    name_token: Token,
    stdout: *std.Io.Writer,
    allocator: std.mem.Allocator,
) !void {
    // if (tokenizer.optionalToken(.OpenBrace)) {
    try stdout.print(
        "pub const {s}Members = [_]MemberDefinition{{\n",
        .{name_token.text.data[0..name_token.text.count]},
    );
    while (true) {
        const member_token: Token = tokenizer.getToken();

        if (member_token.token_type == .CloseBrace or
            (member_token.token_type == .Identifier and member_token.equals("pub")))
        {
            break;
        } else {
            try parseMember(tokenizer, member_token, name_token, stdout);
        }
    }
    try stdout.print("}};\n", .{});

    const opt_meta: ?*MetaStruct = allocator.create(MetaStruct) catch null;
    if (opt_meta) |meta| {
        meta.name = allocator.dupe(u8, name_token.text.data[0..name_token.text.count]) catch "unknown";
        meta.next = first_meta_struct;
        first_meta_struct = meta;
    }
    // }
}

pub fn parseMember(
    tokenizer: *Tokenizer,
    member_name_token: Token,
    struct_type_token: Token,
    stdout: *std.Io.Writer,
) !void {
    if (true) {
        var is_pointer: bool = false;
        var parsing: bool = true;
        var opt_previous_token: ?Token = null;
        var opt_member_type_token: ?Token = null;
        while (parsing) {
            var token: Token = tokenizer.getToken();

            switch (token.token_type) {
                .Asterisk => {
                    is_pointer = true;
                    // opt_previous_token = token;
                    // token = tokenizer.getToken();
                },
                .Identifier => {
                    if (opt_member_type_token == null) {
                        if (opt_previous_token) |previous_token| {
                            if (previous_token.token_type == .Asterisk or
                                previous_token.token_type == .Colon or
                                previous_token.token_type == .Period)
                            {
                                opt_member_type_token = token;
                            }
                        }
                    }
                },
                .OpenBracket => {
                    // is_array
                    tokenizer.eatAllUntil(']');
                    token = tokenizer.getToken();
                    opt_member_type_token = token;
                },
                .Comma, .EndOfStream => {
                    parsing = false;
                },
                else => {},
            }

            opt_previous_token = token;
        }

        if (opt_member_type_token) |member_type_token| {
            try stdout.print(
                "    .{{ .field_type = .{s}, .field_name = \"{s}\", .field_offset = @offsetOf({s}, \"{s}\"), .flags = {s} }},\n",
                .{
                    member_type_token.text.data[0..member_type_token.text.count],
                    member_name_token.text.data[0..member_name_token.text.count],
                    struct_type_token.text.data[0..struct_type_token.text.count],
                    member_name_token.text.data[0..member_name_token.text.count],
                    if (is_pointer) ".IsPointer" else ".None",
                },
            );
        } else {
            try stdout.print("ERROR: Missing member type.\n", .{});
        }
    } else {
        var is_pointer: bool = false;
        const token: Token = tokenizer.getToken();
        switch (token.token_type) {
            .Asterisk => {
                is_pointer = true;
                parseMember(tokenizer, token);
            },
            else => {},
        }

        try stdout.print(
            "shared.debugValue({s});\n",
            .{member_name_token.text.data[0..member_name_token.text.count]},
        );
        tokenizer.eatAllUntil(',');
    }
}

pub fn parseIntrospectionParams(tokenizer: *Tokenizer) !void {
    while (true) {
        const token: Token = tokenizer.getToken();

        if (token.token_type == .CloseParen or token.token_type == .EndOfStream) {
            break;
        }
    }
}

pub fn main(init: std.process.Init) anyerror!void {
    const allocator = init.gpa;

    var stdout_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout: *std.Io.Writer = &stdout_writer.interface;

    const file_names = [_][]const u8{
        "src/sim.zig",
        "src/math.zig",
        "src/world.zig",
    };

    for (file_names) |file_name| {
        const file_contents: String = readEntireFile(file_name, allocator, init.io);
        // defer allocator.free(file_contents.data);

        var tokenizer: Tokenizer = .init(file_contents, .fromSlice(file_name));
        var parsing: bool = true;
        while (parsing) {
            const token: Token = tokenizer.getToken();
            switch (token.token_type) {
                .EndOfStream => {
                    parsing = false;
                },
                .Unknown => {},
                .Comment => {
                    if (token.equals("introspect")) {
                        try parseIntrospectable(&tokenizer, stdout, allocator);
                    }
                },
                else => {
                    // try stdout.print("{d}: {s}\n", .{ @intFromEnum(token.token_type), token.text[0..token.text.count] });
                },
            }
        }
    }

    try stdout.print("pub fn dumpKnownStruct(member_ptr: *anyopaque, member: *const MemberDefinition, next_indent_level: u32) void {{\n", .{});
    try stdout.print("    var buffer: [128]u8 = undefined;\n", .{});
    try stdout.print("    switch (member.field_type) {{\n", .{});
    var opt_meta: ?*MetaStruct = first_meta_struct;
    while (opt_meta) |meta| : (opt_meta = meta.next) {
        try stdout.print("        .{s} => {{\n", .{meta.name});
        try stdout.print("            debug.textLine(std.fmt.bufPrintZ(&buffer, \"{{s}}\", .{{member.field_name}}) catch \"unknown\");\n", .{});
        try stdout.print("            debug.debugDumpStruct(member_ptr, @ptrCast(&{s}Members), {s}Members.len, next_indent_level);\n", .{ meta.name, meta.name });
        try stdout.print("        }},\n", .{});
    }
    try stdout.print("        else => {{}},\n", .{});
    try stdout.print("    }}\n", .{});
    try stdout.print("}}\n", .{});
}

const EntireFile = struct {
    content_size: u32 = 0,
    contents: []const u8 = undefined,
};

fn readEntireFile(file_name: []const u8, allocator: std.mem.Allocator, io: std.Io) String {
    var result: String = .empty;

    if (std.Io.Dir.cwd().openFile(io, file_name, .{ .mode = .read_only })) |file| {
        defer file.close(io);

        var file_reader = file.reader(io, &.{});
        const contents = file_reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(u32))) catch "";
        result.data = @ptrCast(@constCast(contents));
        result.count = @intCast(contents.len);
    } else |err| {
        std.log.err("Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}
