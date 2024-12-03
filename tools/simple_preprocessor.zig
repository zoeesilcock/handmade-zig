const std = @import("std");

const TokenType = enum(u32) {
    Unknown,
    Comma,
    Colon,
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

const Tokenizer = struct {
    at: [*]const u8,

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
            }
        }

        return token;
    }

    fn eatAllWhitespace(self: *Tokenizer) void {
        while (true) {
            if (isWhitespace(self.at[0])) {
                self.at += 1;
            } else if (self.at[0] == '/' and self.at[1] == '/') {
                self.at += 2;

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

            std.debug.print("const MemberDefinition_{s} = .{{\n", .{ name_token.text[0..name_token.text_length] });
            while (true) {
                const member_token: Token = self.getToken();

                if (member_token.token_type == .CloseBrace or (member_token.token_type == .Identifier and member_token.equals("pub"))) {
                    break;
                } else {
                    self.parseMember(member_token);
                }
            }
            std.debug.print("}}\n", .{});
        }
    }

    pub fn parseMember(self: *Tokenizer, member_name_token: Token) void {
        if (true) {
            var is_pointer: bool = false;
            var parsing: bool = true;
            while (parsing) {
                var token: Token = self.getToken();

                switch(token.token_type) {
                    .Asterisk => {
                        is_pointer = true;
                        token = self.getToken();
                    },
                    .Comma, .EndOfStream => {
                        parsing = false;
                    },
                    else => {},
                }
            }

            // std.debug.print("shared.debugValue({s});\n", .{ member_name_token.text[0..member_name_token.text_length] });
            std.debug.print("    {{\"{s}\"}},\n", .{ member_name_token.text[0..member_name_token.text_length] });
            self.eatAllUntil(',');
        } else {
            var is_pointer: bool = false;
            const token: Token = self.getToken();
            switch(token.token_type) {
                .Asterisk => {
                    is_pointer = true;
                    self.parseMember(token);
                },
                else => {},
            }

            std.debug.print("shared.debugValue({s});\n", .{ member_name_token.text[0..member_name_token.text_length] });
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
    const file = readEntireFile("src/sim.zig", allocator);

    var tokenizer: Tokenizer = .{ .at = @ptrCast(file.contents) };
    var parsing: bool = true;
    while (parsing) {
        const token: Token = tokenizer.getToken();
        switch (token.token_type) {
            .EndOfStream => {
                std.debug.print("{d}: End of stream\n", .{ @intFromEnum(token.token_type) });
                parsing = false;
            },
            .Unknown => {},
            .Identifier => {
                if (token.equals("introspect")) {
                    tokenizer.parseIntrospectable();
                }
            },
            else => {
                // std.debug.print("{d}: {s}\n", .{ @intFromEnum(token.token_type), token.text[0..token.text_length] });
            }
        }
    }
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

        const buffer = file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, @alignOf(u32), 0) catch "";
        result.contents = buffer;
    } else |err| {
        std.debug.print("Cannot find file '{s}': {s}", .{ file_name, @errorName(err) });
    }

    return result;
}

