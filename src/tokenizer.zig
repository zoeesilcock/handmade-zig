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
    Or,
    Pound,

    String,
    Identifier,
    Number,

    Spacing,
    EndOfLine,
    Comment,
    EndOfStream,
};

pub const Token = struct {
    file_name: String = .empty,
    column_number: u32 = 0,
    line_number: u32 = 0,

    token_type: TokenType = undefined,
    text: String = .empty,
    f32: f32 = 0,
    i32: i32 = 0,

    pub fn equals(self: *const Token, string: [*:0]const u8) bool {
        return shared.stringBufferEquals(self.text, string);
    }

    pub fn isValid(self: *Token) bool {
        return self.token_type != .Unknown;
    }
};

pub const Tokenizer = struct {
    file_name: String = .empty,
    column_number: u32 = 0,
    line_number: u32 = 0,
    error_stream: *stream.Stream = undefined,

    input: String,
    at: [2]u8 = @splat(undefined),

    has_error: bool = false,

    pub fn init(input: String, file_name: String) Tokenizer {
        var result: Tokenizer = .{
            .input = input,
            .column_number = 1,
            .line_number = 1,
            .file_name = file_name,
        };

        result.refill();

        return result;
    }

    pub fn advanceChars(self: *Tokenizer, count: u32) void {
        self.column_number += count;

        _ = self.input.advance(count);
        self.refill();
    }

    pub fn encounteredError(
        self: *Tokenizer,
        opt_on_token: ?Token,
        comptime message: [:0]const u8,
        args: anytype,
    ) void {
        const on_token: Token = opt_on_token orelse self.peekTokenRaw();

        self.has_error = true;
        _ = stream.outputWithSrc(self.error_stream, @src(), "\\#f00%S(%u,%u)\\#fff: \"%S\" - ", .{
            on_token.file_name,
            on_token.line_number,
            on_token.column_number,
            on_token.text,
        });
        _ = stream.outputWithSrc(self.error_stream, @src(), message, args);
        _ = stream.outputWithSrc(self.error_stream, @src(), "\n", .{});
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

    pub fn peekTokenRaw(self: *Tokenizer) Token {
        var temp: Tokenizer = self.*;
        const result: Token = temp.getTokenRaw();
        return result;
    }

    pub fn peekToken(self: *Tokenizer) Token {
        var temp: Tokenizer = self.*;
        const result: Token = temp.getToken();
        return result;
    }

    pub fn getTokenRaw(self: *Tokenizer) Token {
        var token: Token = .{};
        token.file_name = self.file_name;
        token.column_number = self.column_number;
        token.line_number = self.line_number;
        token.text = self.input;

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
            '|' => token.token_type = .Or,
            '#' => token.token_type = .Pound,
            '"' => {
                token.token_type = .String;

                while (self.at[0] != '"') {
                    if (self.at[0] == '\\' and self.at[1] != 0) {
                        self.advanceChars(1);
                    }

                    self.advanceChars(1);
                }

                if (self.at[0] == '"') {
                    self.advanceChars(1);
                }
            },
            else => {
                if (shared.isSpacing(c)) {
                    token.token_type = .Spacing;

                    while (shared.isSpacing(self.at[0])) {
                        self.advanceChars(1);
                    }
                } else if (shared.isEndOfLine(c)) {
                    token.token_type = .EndOfLine;

                    if ((c == '\r' and self.at[0] == '\n') or
                        (c == '\n' and self.at[0] == '\r'))
                    {
                        self.advanceChars(1);
                    }

                    self.column_number = 1;
                    self.line_number += 1;
                } else if (c == '/' and self.at[0] == '/') {
                    token.token_type = .Comment;

                    self.advanceChars(2);

                    while (!shared.isEndOfLine(self.at[0])) {
                        self.advanceChars(1);
                    }

                    // Note: This code path is needed in place of the code above for the simple-preprocessor to work.
                    // Revisit this if we ever need the preprocessor again.
                    //
                    // token.token_type = .Comment;
                    //
                    // self.advanceChars(2);
                    // token.text.data = @constCast(self.input.data);
                    //
                    // while (self.at[0] != 0 and self.at[0] != '(' and !shared.isEndOfLine(self.at[0])) {
                    //     self.advanceChars(1);
                    // }
                } else if (shared.isAlpha(c)) {
                    token.token_type = .Identifier;
                    while (shared.isAlpha(self.at[0]) or shared.isNumber(self.at[0]) or self.at[0] == '_') {
                        self.advanceChars(1);
                    }
                } else if (shared.isNumber(c)) {
                    var number: f32 = @floatFromInt(c - '0');
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
                } else {
                    token.token_type = .Unknown;
                }
            },
        }

        token.text.count = @intFromPtr(self.input.data) - @intFromPtr(token.text.data);

        return token;
    }

    pub fn getToken(self: *Tokenizer) Token {
        var token: Token = .{};

        while (true) {
            token = self.getTokenRaw();
            if (token.token_type == .Spacing or
                token.token_type == .EndOfLine or
                token.token_type == .Comment)
            {
                // Ignore these when we're getting real tokens.
            } else {
                if (token.token_type == .String) {
                    // Skip the quotation marks.
                    if (token.text.count > 0 and token.text.data[0] == '"') {
                        token.text.data += 1;
                        token.text.count -= 1;
                    }

                    if (token.text.count > 0 and token.text.data[token.text.count - 1] == '"') {
                        token.text.count -= 1;
                    }
                }
                break;
            }
        }

        return token;
    }

    pub fn eatAllUntil(self: *Tokenizer, end: u32) void {
        while (self.at[0] != end) {
            self.advanceChars(1);
        }

        self.advanceChars(1);
    }

    pub fn optionalToken(self: *Tokenizer, desired_type: TokenType) bool {
        const token: Token = self.peekToken();
        const result = token.token_type == desired_type;
        if (token.token_type == desired_type) {
            _ = self.getToken();
        }
        return result;
    }

    pub fn requireToken(self: *Tokenizer, desired_type: TokenType) Token {
        const token: Token = self.getToken();

        if (token.token_type != desired_type) {
            self.encounteredError(token, "Unexpected token type (expected %s)", .{@tagName(desired_type)});
        }

        return token;
    }

    pub fn requireIntegerRange(self: *Tokenizer, min_value: i32, max_value: i32) Token {
        const token: Token = self.requireToken(.Number);

        if (token.token_type == .Number) {
            if (token.i32 >= min_value and token.i32 <= max_value) {
                // Valid.
            } else {
                self.encounteredError(token, "Expected a number between %d and %d.", .{ min_value, max_value });
            }
        }

        return token;
    }

    pub fn parsing(self: *Tokenizer) bool {
        return !self.has_error;
    }
};
