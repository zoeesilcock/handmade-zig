const std = @import("std");

const TokenType = enum(u32) {
    Unknown,
    Comma,
    Colon,
    Period,
    SemiColon,
    Asterisk,
    OpenParen,
    CloseParen,
    OpenBracket,
    CloseBracket,
    OpenBrace,
    CloseBrace,
    Equals,
    EndOfStream,
    String,
    Identifier,
};

const Token = struct {
    token_type: TokenType = undefined,

    text_length: usize = undefined,
    text: [*]const u8 = undefined,

    pub fn equals(self: *const Token, string: []const u8) bool {
        var index: u32 = 0;
        while (index < self.text_length) : (index += 1) {
            if (self.text[index] != string[index]) {
                return false;
            }
        }
        return self.text_length == string.len;
    }
};

fn isAlpha(char: u32) bool {
    return (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z');
}

fn isNumber(char: u32) bool {
    return char >= '0' and char <= '9';
}

fn isWhitespace(char: u32) bool {
    return char == ' ' or char == '\t' or isEndOfLine(char);
}

fn isEndOfLine(char: u32) bool {
    return char == '\n' or char == '\r';
}

const MetaStruct = struct {
    name: []const u8,
    next: ?*MetaStruct,
};

var first_meta_struct: *MetaStruct = undefined;

const Tokenizer = struct {
    at: [*]const u8,
    allocator: std.mem.Allocator,

    pub fn getToken(self: *Tokenizer) Token {
        self.eatAllWhitespace();

        var token: Token = .{
            .text_length = 1,
            .text = self.at,
        };
        const c = self.at[0];
        self.at += 1;

        switch (c) {
            0 => token.token_type = .EndOfStream,
            ':' => token.token_type = .Colon,
            ';' => token.token_type = .SemiColon,
            ',' => token.token_type = .Comma,
            '*' => token.token_type = .Asterisk,
            '(' => token.token_type = .OpenParen,
            ')' => token.token_type = .CloseParen,
            '[' => token.token_type = .OpenBracket,
            ']' => token.token_type = .CloseBracket,
            '{' => token.token_type = .OpenBrace,
            '}' => token.token_type = .CloseBrace,
            '=' => token.token_type = .Equals,
            '.' => token.token_type = .Period,
            '"' => {
                token.token_type = .String;
                token.text = self.at;
                while (self.at[0] != '"') {
                    if (self.at[0] == '\\' and self.at[1] != 0) {
                        self.at += 1;
                    }

                    self.at += 1;
                }

                token.text_length = @intFromPtr(self.at) - @intFromPtr(token.text);

                if (self.at[0] == '"') {
                    self.at += 1;
                }
            },
            else => {
                if (isAlpha(c)) {
                    token.token_type = .Identifier;
                    while (isAlpha(self.at[0]) or isNumber(self.at[0]) or self.at[0] == '_') {
                        self.at += 1;
                    }

                    token.text_length = @intFromPtr(self.at) - @intFromPtr(token.text);
                } else {
                    token.token_type = .Unknown;
                }
                // else if (isNumber(c)) {
                //     parseNumber();
                // }
            },
        }

        return token;
    }

    fn eatAllWhitespace(self: *Tokenizer) void {
        while (true) {
            if (isWhitespace(self.at[0])) {
                self.at += 1;
            } else if (self.at[0] == '/' and self.at[1] == '/') {
                self.at += 2;

                var token = self.getToken();
                if (token.equals("introspect")) {
                    self.parseIntrospectable();
                }

                while (self.at[0] != 0 and !isEndOfLine(self.at[0])) {
                    self.at += 1;
                }
            } else {
                break;
            }
        }
    }

    fn eatAllUntil(self: *Tokenizer, end: u32) void {
        while (self.at[0] != end) {
            self.at += 1;
        }

        self.at += 1;
    }

    pub fn requireToken(self: *Tokenizer, token_type: TokenType) bool {
        const token: Token = self.getToken();
        return token.token_type == token_type;
    }

    pub fn parseIntrospectable(self: *Tokenizer) void {
        if (self.requireToken(.OpenParen)) {
            self.parseIntrospectionParams();

            var token = self.getToken();
            var previous_token: ?Token = null;
            var opt_type_token: ?Token = null;
            var opt_name_token: ?Token = null;
            while (true) : (token = self.getToken()) {
                if (token.token_type == .OpenBrace) {
                    opt_type_token = previous_token;
                    self.at -= 1;
                    break;
                }

                if (token.token_type == .Equals) {
                    opt_name_token = previous_token;
                }

                previous_token = token;
            }

            if (opt_type_token) |type_token| {
                if (type_token.equals("struct")) {
                    self.parseStruct(opt_name_token.?);
                } else {
                    std.debug.print("ERROR: Introspection is only supported for structs right now :(.\n", .{});
                }
            }
        } else {
            std.debug.print("ERROR: Missing parentheses.\n", .{});
        }
    }

    pub fn parseStruct(self: *Tokenizer, name_token: Token) void {
        if (self.requireToken(.OpenBrace)) {
            std.debug.print("pub const {s}Members = [_]MemberDefinition{{\n", .{name_token.text[0..name_token.text_length]});
            while (true) {
                const member_token: Token = self.getToken();

                if (member_token.token_type == .CloseBrace or (member_token.token_type == .Identifier and member_token.equals("pub"))) {
                    break;
                } else {
                    self.parseMember(member_token, name_token);
                }
            }
            std.debug.print("}};\n", .{});

            const opt_meta: ?*MetaStruct = self.allocator.create(MetaStruct) catch null;
            if (opt_meta) |meta| {
                meta.name = self.allocator.dupe(u8, name_token.text[0..name_token.text_length]) catch "unknown";
                meta.next = first_meta_struct;
                first_meta_struct = meta;
            }
        }
    }

    pub fn parseMember(self: *Tokenizer, member_name_token: Token, struct_type_token: Token) void {
        if (true) {
            var is_pointer: bool = false;
            var parsing: bool = true;
            var opt_previous_token: ?Token = null;
            var opt_member_type_token: ?Token = null;
            while (parsing) {
                var token: Token = self.getToken();

                switch (token.token_type) {
                    .Asterisk => {
                        is_pointer = true;
                        // opt_previous_token = token;
                        // token = self.getToken();
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
                        self.eatAllUntil(']');
                        token = self.getToken();
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
                std.debug.print(
                    "    .{{ .field_type = .{s}, .field_name = \"{s}\", .field_offset = @offsetOf({s}, \"{s}\"), .flags = {s} }},\n",
                    .{
                        member_type_token.text[0..member_type_token.text_length],
                        member_name_token.text[0..member_name_token.text_length],
                        struct_type_token.text[0..struct_type_token.text_length],
                        member_name_token.text[0..member_name_token.text_length],
                        if (is_pointer) ".IsPointer" else ".None",
                    },
                );
            } else {
                std.debug.print("ERROR: Missing member type.\n", .{});
            }
        } else {
            var is_pointer: bool = false;
            const token: Token = self.getToken();
            switch (token.token_type) {
                .Asterisk => {
                    is_pointer = true;
                    self.parseMember(token);
                },
                else => {},
            }

            std.debug.print("shared.debugValue({s});\n", .{member_name_token.text[0..member_name_token.text_length]});
            self.eatAllUntil(',');
        }
    }

    pub fn parseIntrospectionParams(self: *Tokenizer) void {
        while (true) {
            const token: Token = self.getToken();

            if (token.token_type == .CloseParen or token.token_type == .EndOfStream) {
                break;
            }
        }
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const file_names = [_][]const u8{
        "src/sim.zig",
        "src/math.zig",
        "src/world.zig",
    };

    for (file_names) |file_name| {
        const file = readEntireFile(file_name, allocator);
        var tokenizer: Tokenizer = .{ .at = @ptrCast(file.contents), .allocator = allocator };
        var parsing: bool = true;
        while (parsing) {
            const token: Token = tokenizer.getToken();
            switch (token.token_type) {
                .EndOfStream => {
                    parsing = false;
                },
                .Unknown => {},
                .Identifier => {
                    // if (token.equals("introspect")) {
                    //     tokenizer.parseIntrospectable();
                    // }
                },
                else => {
                    // std.debug.print("{d}: {s}\n", .{ @intFromEnum(token.token_type), token.text[0..token.text_length] });
                },
            }
        }
    }

    std.debug.print("pub fn dumpKnownStruct(member_ptr: *anyopaque, member: *const MemberDefinition, next_indent_level: u32) void {{\n", .{});
    std.debug.print("    var buffer: [128]u8 = undefined;\n", .{});
    std.debug.print("    switch(member.field_type) {{\n", .{});
    var opt_meta: ?*MetaStruct = first_meta_struct;
    while (opt_meta) |meta| : (opt_meta = meta.next) {
        std.debug.print("        .{s} => {{\n", .{meta.name});
        std.debug.print("            debug.textLine(std.fmt.bufPrintZ(&buffer, \"{{s}}\", .{{ member.field_name }}) catch \"unknown\");\n", .{});
        std.debug.print("            debug.debugDumpStruct(member_ptr, @ptrCast(&{s}Members), {s}Members.len, next_indent_level);\n", .{ meta.name, meta.name });
        std.debug.print("        }},\n", .{});
    }
    std.debug.print("        else => {{}},\n", .{});
    std.debug.print("    }}\n", .{});
    std.debug.print("}}\n", .{});
}

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

        const buffer = file.readToEndAllocOptions(
            allocator,
            std.math.maxInt(u32),
            null,
            .fromByteUnits(@alignOf(u32)),
            0,
        ) catch "";
        result.contents = buffer;
    } else |err| {
        std.debug.print("Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}
