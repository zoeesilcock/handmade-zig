const std = @import("std");
const shared = @import("shared.zig");
const types = @import("types.zig");
const stream = @import("stream.zig");

// Types.
const String = types.String;

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

    String,
    Identifier,
    Number,

    Comment,
    EndOfStream,
};

pub const Token = struct {
    file_name: [:0]const u8 = "",
    line_number: u32 = 0,

    token_type: TokenType = undefined,
    text: String = .empty,
    f32: f32 = 0,
    i32: i32 = 0,

    pub fn equals(self: *const Token, string: [*:0]const u8) bool {
        return shared.stringBufferEquals(self.text, string);
    }
};

pub const Tokenizer = struct {
    file_name: [:0]const u8 = "",
    line_number: u32 = 0,
    error_stream: *stream.Stream = undefined,

    input: String,
    at: [2]u8 = [1]u8{undefined} ** 2,

    has_error: bool = false,

    pub fn init(input: String) Tokenizer {
        var result: Tokenizer = .{
            .input = input,
        };

        result.refill();

        return result;
    }

    pub fn advanceChars(self: *Tokenizer, count: u32) void {
        _ = self.input.advance(count);
        self.refill();
    }

    pub fn encounteredError(self: *Tokenizer, on_token: Token, comptime message: [:0]const u8, args: anytype) void {
        self.has_error = true;
        _ = stream.output(on_token.file_name, on_token.line_number, self.error_stream, message, args);
    }

    pub fn encounteredErrorUnknown(self: *Tokenizer, comptime message: [:0]const u8, args: anytype) void {
        self.has_error = true;
        _ = stream.output(self.file_name, self.line_number, self.error_stream, message, args);
    }

    fn refill(self: *Tokenizer) void {
        if (self.input.count == 0) {
            self.at[0] = 0;
            self.at[1] = 0;
        } else if (self.input.count == 1) {
            self.at[0] = self.input.data[0];
            self.at[1] = 0;
        } else {
            self.at[0] = self.input.data[0];
            self.at[1] = self.input.data[1];
        }
    }

    pub fn getToken(self: *Tokenizer) Token {
        self.eatAllWhitespace();

        var token: Token = .{ .text = self.input };
        if (token.text.count > 0) {
            token.text.count = 0;
        }

        token.file_name = self.file_name;
        token.line_number = self.line_number;

        const c = self.at[0];
        self.advanceChars(1);
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
            '/' => {
                if (self.at[0] == '/') {
                    self.advanceChars(2);

                    token.token_type = .Comment;
                    token.text.data = @constCast(self.input.data);

                    while (self.at[0] != 0 and self.at[0] != '(' and !shared.isEndOfLine(self.at[0])) {
                        self.advanceChars(1);
                    }

                    token.text.count = @intFromPtr(self.input.data) - @intFromPtr(token.text.data);
                }
            },
            '"' => {
                token.token_type = .String;
                token.text = self.input;
                while (self.at[0] != '"') {
                    if (self.at[0] == '\\' and self.at[1] != 0) {
                        self.advanceChars(1);
                    }

                    self.advanceChars(1);
                }

                token.text.count = @intFromPtr(self.input.data) - @intFromPtr(token.text.data);

                if (self.at[0] == '"') {
                    self.advanceChars(1);
                }
            },
            else => {
                if (shared.isAlpha(c)) {
                    token.token_type = .Identifier;
                    while (shared.isAlpha(self.at[0]) or shared.isNumber(self.at[0]) or self.at[0] == '_') {
                        self.advanceChars(1);
                    }

                    token.text.count = @intFromPtr(self.input.data) - @intFromPtr(token.text.data);
                } else if (shared.isNumber(c)) {
                    var number: f32 = 0;
                    while (shared.isNumber(self.at[0])) {
                        const digit: f32 = @floatFromInt(self.at[0] - '0');
                        number = number * 10 + digit;

                        self.advanceChars(1);
                    }

                    if (self.at[0] == '.') {
                        var coefficient: f32 = 0.1;
                        while (shared.isNumber(self.at[0])) {
                            const digit: f32 = @floatFromInt(self.at[0] - '0');
                            number = digit * coefficient;
                            coefficient *= 0.1;

                            self.advanceChars(1);
                        }
                    }

                    token.token_type = .Number;
                    token.f32 = number;
                    token.i32 = @intFromFloat(number);
                    token.text.count = @intFromPtr(self.input.data) - @intFromPtr(token.text.data);
                } else {
                    token.token_type = .Unknown;
                }
            },
        }

        return token;
    }

    fn eatAllWhitespace(self: *Tokenizer) void {
        while (true) {
            if (shared.isWhitespace(self.at[0])) {
                self.advanceChars(1);
            } else {
                break;
            }
        }
    }

    pub fn eatAllUntil(self: *Tokenizer, end: u32) void {
        while (self.at[0] != end) {
            self.advanceChars(1);
        }

        self.advanceChars(1);
    }

    pub fn optionalToken(self: *Tokenizer, desired_type: TokenType) bool {
        const token: Token = self.getToken();
        return token.token_type == desired_type;
    }

    pub fn requireToken(self: *Tokenizer, desired_type: TokenType) Token {
        const token: Token = self.getToken();

        if (token.token_type != desired_type) {
            self.encounteredError(token, "Unexpected token type", .{});
        }

        return token;
    }

    pub fn parsing(self: *Tokenizer) bool {
        return !self.has_error;
    }
};
