const std = @import("std");
const shared = @import("shared.zig");
const types = @import("types.zig");

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
    EndOfStream,
    String,
    Identifier,
    Comment,
};

pub const Token = struct {
    token_type: TokenType = undefined,

    text: String = .empty,
    f32: f32 = 0,
    i32: i32 = 0,

    pub fn equals(self: *const Token, string: [*:0]const u8) bool {
        return shared.stringBufferEquals(self.text, string);
    }
};

pub const Tokenizer = struct {
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

    pub fn encounteredError(self: *Tokenizer, on_token: Token, message: [*:0]const u8) void {
        self.has_error = true;
        _ = on_token;
        _ = message;
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
                } else {
                    token.token_type = .Unknown;
                }
                // else if (shared.isNumber(c)) {
                //     parseNumber();
                // }
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
            self.encounteredError(token, "Unexpected token type");
        }

        return token;
    }

    pub fn parsing(self: *Tokenizer) bool {
        return !self.has_error;
    }
};
