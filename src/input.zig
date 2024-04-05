const std = @import("std");
const defs = @import("definitions.zig");

const InputError = error{
    OutOfMemory,
    EndOfInput,
    NotImplemented,
    PrintError,
    UnexpectedToken,
};

const Tokenizer = struct {
    source: []const u8,
    index: usize,

    const Self = @This();
    const Token = struct {
        value: []const u8,
        kind: TokenType,
    };
    const TokenType = enum {
        Keyword,
        Identifier,
        ParanenthesisOpen,
        ParanenthesisClose,
        Comma,
        Type,
        EndOfFile,
    };

    fn next(self: *Self) InputError!u8 {
        if (self.index >= self.source.len) {
            return InputError.EndOfInput;
        }
        const c = self.source[self.index];
        self.index += 1;
        return c;
    }

    fn handleError(self: Self, err: InputError, start: usize) InputError!Token {
        if (err != InputError.EndOfInput) {
            return err;
        }
        return Token{
            .value = self.source[start..self.index],
            .kind = .EndOfFile,
        };
    }

    fn skipWhitespace(self: *Self) void {
        while (std.ascii.isWhitespace(self.source[self.index])) : (self.index += 1) {
            if (self.index >= self.source.len) {
                break;
            }
        }
    }

    fn tokenizeKeyword(self: *Self, start: usize, keyword: []const u8) InputError!Token {
        var i: usize = 0;
        while (i < keyword.len) : (i += 1) {
            if (self.next()) |char| {
                if (char != keyword[i]) {
                    self.index -= 1;
                    break;
                }
            } else |err| {
                return self.handleError(err, i);
            }
        }
        return Token{
            .value = self.source[start..self.index],
            .kind = .Keyword,
        };
    }

    fn anyOf(char: u8, chars: []const u8) bool {
        for (chars) |c| {
            if (char == c) {
                return true;
            }
        }
        return false;
    }

    fn tokenizeType(self: *Self) InputError!Token {
        const start = self.index;
        while (self.next()) |char| {
            if (std.ascii.isControl(char) or std.ascii.isWhitespace(char) or anyOf(char, "(,)")) {
                break;
            }
        } else |err| {
            var t = try self.handleError(err, start);
            t.kind = .Type;
            return t;
        }

        self.index -= 1;
        return Token{
            .value = self.source[start .. self.index - 1],
            .kind = .Type,
        };
    }

    fn nextToken(self: *Self) InputError!Token {
        self.skipWhitespace();
        const current = self.index;
        if (self.next()) |char| {
            switch (char) {
                '(' => return Token{
                    .value = self.source[current..self.index],
                    .kind = .ParanenthesisOpen,
                },
                ')' => return Token{
                    .value = self.source[current..self.index],
                    .kind = .ParanenthesisClose,
                },
                ',' => return Token{
                    .value = self.source[current..self.index],
                    .kind = .Comma,
                },
                'f' => {
                    const c = if (self.next()) |c| c else |err| return self.handleError(err, current);
                    if (c == 'n') return Token{ .value = self.source[current..self.index], .kind = .Keyword } else {
                        self.index = current;
                        return self.tokenizeType();
                    }
                },
                else => {
                    self.index = current;
                    return self.tokenizeType();
                },
            }
        } else |err| {
            return self.handleError(err, current);
        }
    }
};

const Parser = struct {
    tokenizer: Tokenizer,

    const Self = @This();

    fn init(source: []const u8) Self {
        return Self{
            .tokenizer = Tokenizer{
                .source = source,
                .index = 0,
            },
        };
    }

    fn expectToken(self: *Self, kind: Tokenizer.TokenType, should_print: bool) !Tokenizer.Token {
        const token = try self.tokenizer.nextToken();
        if (token.kind == kind) {
            return token;
        } else if (token.kind != kind and should_print) {
            const stdout_file = std.io.getStdOut().writer();
            var bw = std.io.bufferedWriter(stdout_file);
            const out = bw.writer();

            out.print("\nERROR: {}\n", .{InputError.UnexpectedToken}) catch return InputError.PrintError;
            out.print("    expected token of kind {}\n", .{kind}) catch return InputError.PrintError;
            out.print("    but got {} ('{s}')\n", .{
                token.kind,
                token.value,
            }) catch return InputError.PrintError;
            bw.flush() catch return InputError.PrintError;

            return error.UnexpectedToken;
        }

        return error.UnexpectedToken;
    }

    fn parseParams(self: *Self, alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
        var params = std.ArrayList([]const u8).init(alloc);
        while (self.expectToken(.Type, true)) |token| {
            try params.append(try alloc.dupe(u8, token.value));
            const comma = self.expectToken(.Comma, false);
            if (comma) |_| {} else |err| {
                if (err == error.UnexpectedToken) {
                    self.tokenizer.index -= 1;
                    break;
                } else {
                    return err;
                }
            }
        } else |err| {
            if (err != error.EndOfInput and err != error.UnexpectedToken) {
                return err;
            }
        }
        return params;
    }

    fn parse(self: *Self, alloc: std.mem.Allocator) !defs.FunctionDef {
        _ = try self.expectToken(.Keyword, true);
        const identifier = self.expectToken(.Type, true) catch null;
        _ = try self.expectToken(.ParanenthesisOpen, true);
        const params = try self.parseParams(alloc);
        _ = try self.expectToken(.ParanenthesisClose, true);
        const returnType = try self.expectToken(.Type, true);
        return defs.FunctionDef{
            .alloc = alloc,
            .name = if (identifier) |id| try alloc.dupe(u8, id.value) else try alloc.alloc(u8, 0),
            .return_type = try alloc.dupe(u8, returnType.value),
            .params = params,
        };
    }
};

pub fn parse(alloc: std.mem.Allocator, source: []const u8) !defs.FunctionDef {
    var parser = Parser.init(source);
    return parser.parse(alloc);
}
