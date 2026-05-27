const tokenizer_mod = @import("tokenizer.zig");

// Types.
const Tokenizer = tokenizer_mod.Tokenizer;
const Token = tokenizer_mod.Token;

pub fn parseHHT(tokenizer: *Tokenizer) void {
    while (tokenizer.parsing()) {
        const token: Token = tokenizer.getToken();

        if (token.token_type == .Comment) {
            continue;
        }

        if (token.token_type == .Identifier) {
            parseTopLevelBlock(tokenizer, token);
        } else if (token.token_type == .EndOfStream) {
            break;
        } else {
            tokenizer.encounteredError(token, "Unexpected top-level token.");
            break;
        }
    }
}

fn parseTopLevelBlock(
    tokenizer: *Tokenizer,
    block_token: Token,
) void {
    const block_types = [_][*:0]const u8{
        "default",
        "block",
        "body",
        "character",
        "cover",
        "hand",
        "head",
        "item",
        "obstacles",
        "plate",
    };

    var found: bool = false;
    var file_name: Token = .{};

    if (block_token.equals("default")) {
        found = true;
    } else {
        var block_type_index: u32 = 0;
        while (block_type_index < block_types.len) : (block_type_index += 1) {
            if (block_token.equals(block_types[block_type_index])) {
                file_name = tokenizer.requireToken(.String);
                found = true;
            }
        }
    }

    if (found) {
        _ = tokenizer.requireToken(.OpenBrace);
        while (tokenizer.parsing()) {
            const token: Token = tokenizer.getToken();
            if (token.token_type == .CloseBrace) {
                break;
            } else if (token.equals("Author")) {
                _ = tokenizer.requireToken(.Equals);
                const author: Token = tokenizer.requireToken(.String);
                _ = author;
                _ = tokenizer.requireToken(.SemiColon);
            } else if (token.equals("Description")) {
                _ = tokenizer.requireToken(.Equals);
                const description: Token = tokenizer.requireToken(.String);
                _ = description;
                _ = tokenizer.requireToken(.SemiColon);
            } else if (token.equals("Tags")) {
                _ = tokenizer.requireToken(.Equals);
                parseTagList(tokenizer);
            } else {
                tokenizer.encounteredError(token, "Expected field name.");
            }
        }
        _ = tokenizer.requireToken(.SemiColon);
    } else {
        tokenizer.encounteredError(block_token, "Unexpected block type.");
    }
}

fn parseTagList(tokenizer: *Tokenizer) void {
    while (tokenizer.parsing()) {
        const token: Token = tokenizer.getToken();
        if (token.token_type == .SemiColon) {
            break;
        } else if (token.token_type == .Identifier) {
            // Tag to ID.

            const comma_check: Token = tokenizer.getToken();
            if (comma_check.token_type == .SemiColon) {
                break;
            } else if (comma_check.token_type != .Comma) {
                tokenizer.encounteredError(token, "Expected comma or semicolon.");
            }
        } else if (token.token_type == .Comma) {} else {
            tokenizer.encounteredError(token, "Expected a tag name.");
        }
    }
}
