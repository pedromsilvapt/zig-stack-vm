const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const RedBlackTree = @import("./rbt.zig").RedBlackTree;
const Instruction = @import("./instruction.zig").Instruction;
const InstructionsWriter = @import("./instruction.zig").InstructionsWriter;
const InstructionsReader = @import("./instruction.zig").InstructionsReader;

const LabelPlaceholder = struct {
    name: []const u8,
    position: usize,
};

const InstructionParameter = union(enum) {
    String: []const u8, // Should be freed when used
        Float: f64, Integer: i32, Address: usize, Label: []const u8
};

pub const Parser = struct {
    allocator: *Allocator = null,
    source: []const u8,
    owned: bool,
    position: TextPosition = TextPosition.initEmpty(),
    // cursor: usize = 0,
    // line: usize = 0,
    // column: usize = 0,
    err_message: ?[]u8 = null,
    source_map: SourceMap,

    // Parser owns the source
    pub fn init(allocator: *Allocator, source: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .source = source,
            .owned = false,
            .source_map = SourceMap.init(allocator),
        };
    }

    pub fn initOwned(allocator: *Allocator, source: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .source = source,
            .owned = true,
            .source_map = SourceMap.init(allocator),
        };
    }

    // Parser owns the source, but not the file_path
    pub fn initFile(allocator: *Allocator, file_path: []const u8) !Parser {
        const source = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024);

        return Parser{
            .allocator = allocator,
            .source = source,
            .owned = true,
            .source_map = SourceMap.init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        if (self.owned) self.allocator.free(self.source);
        if (self.err_message) |msg| self.allocator.free(msg);
        self.source_map.deinit();
    }

    pub fn endOfFile(self: *Parser) bool {
        return self.position.offset >= self.source.len;
    }

    // The line is still owned by Parser
    // Becomes invalid when deinit is called
    pub fn getCurrentLine(self: *Parser) []const u8 {
        return self.getSourceSpan(self.position, self.position);
        // const start_of_line: usize = self.cursor - self.column;
        // const end_of_line: usize = blk: {
        //     var i = self.cursor;
        //     const l = self.source.len;

        //     while (i < l) : (i += 1) if (self.source[i] == '\n') break;

        //     break :blk i;
        // };

        // return self.source[start_of_line..end_of_line];
    }

    // The returned string is still owned by Parser
    // And becomes invalid when Parser.deinit() is called
    pub fn getSourceSpan(self: *Parser, start: TextPosition, end: TextPosition) []const u8 {
        const start_of_line: usize = start.offset - start.column;
        const end_of_line: usize = blk: {
            var i = end.offset;
            const l = self.source.len;

            while (i < l) : (i += 1) if (self.source[i] == '\n') break;

            break :blk i;
        };

        return self.source[start_of_line..end_of_line];
    }

    pub fn peek(self: *Parser) ?u8 {
        if (self.position.offset < self.source.len) {
            return self.source[self.position.offset];
        }

        return null;
    }

    pub fn read(self: *Parser) ?u8 {
        if (self.position.offset < self.source.len) {
            const char = self.source[self.position.offset];

            self.position.offset += 1;
            self.position.column += 1;

            if (char == '\n') {
                self.position.line += 1;
                self.position.column = 0;
            }

            return char;
        }

        return null;
    }

    pub fn seekTo(self: *Parser, position: TextPosition) void {
        self.position = position;
        // if (self.position.offset > cursor) {
        //     var offset = self.position.offset - cursor;

        //     if (offset > self.column) {
        //         self.column = 0;
        //     } else {
        //         self.column -= offset;
        //     }
        // }

        // self.cursor = cursor;
    }

    pub fn skipWhiteSpace(self: *Parser) void {
        var comment: bool = false;

        while (self.peek()) |char| {
            if (char == ' ' or char == '\t' or char == '\n' or char == '\r') {
                _ = self.read();
            } else if (char == '/') {
                _ = self.read();
                if (comment) {
                    while (self.peek()) |cchar| {
                        _ = self.read();

                        if (cchar == '\n') break;
                    }

                    comment = false;
                } else {
                    comment = true;
                }
            } else {
                break;
            }
        }
    }

    pub fn parseIdentifier(self: *Parser) ![]const u8 {
        const start = self.position;

        while (self.peek()) |char| {
            if ((char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z') or char == '_') {
                _ = self.read();
            } else if (self.position.offset > start.offset and (char >= '0' and char <= '9')) {
                _ = self.read();
            } else {
                break;
            }
        }

        if (self.position.offset > start.offset) {
            return self.source[start.offset..self.position.offset];
        } else {
            return error.NoMatch;
        }
    }

    pub fn parseLabelMarker(self: *Parser) ![]const u8 {
        const identifier = try self.parseIdentifier();

        self.skipWhiteSpace();

        if (self.read()) |char| {
            if (char == ':') {
                return identifier;
            }
        }

        return error.NoMatch;
    }

    pub fn parseInstruction(self: *Parser) !Instruction {
        const identifier = try self.parseIdentifier();

        if (std.mem.eql(u8, identifier, "concat")) return .Concat;
        if (std.mem.eql(u8, identifier, "jump")) return .Jump;
        if (std.mem.eql(u8, identifier, "jz")) return .Jz;
        if (std.mem.eql(u8, identifier, "pusha")) return .PushA;
        if (std.mem.eql(u8, identifier, "call")) return .Call;
        if (std.mem.eql(u8, identifier, "return")) return .Return;
        if (std.mem.eql(u8, identifier, "start")) return .Start;
        if (std.mem.eql(u8, identifier, "nop")) return .Nop;
        if (std.mem.eql(u8, identifier, "stop")) return .Stop;
        if (std.mem.eql(u8, identifier, "err")) return .Err;
        if (std.mem.eql(u8, identifier, "atoi")) return .Atoi;
        if (std.mem.eql(u8, identifier, "atof")) return .Atof;
        if (std.mem.eql(u8, identifier, "itof")) return .Itof;
        if (std.mem.eql(u8, identifier, "ftoi")) return .Ftoi;
        if (std.mem.eql(u8, identifier, "stri")) return .Stri;
        if (std.mem.eql(u8, identifier, "strf")) return .Strf;
        if (std.mem.eql(u8, identifier, "dup")) return .Dup;
        if (std.mem.eql(u8, identifier, "dupn")) return .DupN;
        if (std.mem.eql(u8, identifier, "fadd")) return .FAdd;
        if (std.mem.eql(u8, identifier, "fsub")) return .FSub;
        if (std.mem.eql(u8, identifier, "fmul")) return .FMul;
        if (std.mem.eql(u8, identifier, "fdiv")) return .FDiv;
        if (std.mem.eql(u8, identifier, "finf")) return .FInf;
        if (std.mem.eql(u8, identifier, "finfeq")) return .FInfEq;
        if (std.mem.eql(u8, identifier, "fsup")) return .FSup;
        if (std.mem.eql(u8, identifier, "fsupeq")) return .FSupEq;
        if (std.mem.eql(u8, identifier, "fcos")) return .FCos;
        if (std.mem.eql(u8, identifier, "fsin")) return .FSin;
        if (std.mem.eql(u8, identifier, "alloc")) return .Alloc;
        if (std.mem.eql(u8, identifier, "allocn")) return .AllocN;
        if (std.mem.eql(u8, identifier, "free")) return .Free;
        if (std.mem.eql(u8, identifier, "equal")) return .Equal;
        if (std.mem.eql(u8, identifier, "add")) return .Add;
        if (std.mem.eql(u8, identifier, "sub")) return .Sub;
        if (std.mem.eql(u8, identifier, "mul")) return .Mul;
        if (std.mem.eql(u8, identifier, "div")) return .Div;
        if (std.mem.eql(u8, identifier, "mod")) return .Mod;
        if (std.mem.eql(u8, identifier, "inf")) return .Inf;
        if (std.mem.eql(u8, identifier, "infeq")) return .InfEq;
        if (std.mem.eql(u8, identifier, "sup")) return .Sup;
        if (std.mem.eql(u8, identifier, "supeq")) return .SupEq;
        if (std.mem.eql(u8, identifier, "not")) return .Not;
        if (std.mem.eql(u8, identifier, "load")) return .Load;
        if (std.mem.eql(u8, identifier, "loadn")) return .LoadN;
        if (std.mem.eql(u8, identifier, "swap")) return .Swap;
        if (std.mem.eql(u8, identifier, "debug")) return .Debug;
        if (std.mem.eql(u8, identifier, "writei")) return .WriteI;
        if (std.mem.eql(u8, identifier, "writelni")) return .WritelnI;
        if (std.mem.eql(u8, identifier, "writef")) return .WriteF;
        if (std.mem.eql(u8, identifier, "writelnf")) return .WritelnF;
        if (std.mem.eql(u8, identifier, "writes")) return .WriteS;
        if (std.mem.eql(u8, identifier, "writelns")) return .WritelnS;
        if (std.mem.eql(u8, identifier, "read")) return .Read;
        if (std.mem.eql(u8, identifier, "padd")) return .Padd;
        if (std.mem.eql(u8, identifier, "pop")) return .Pop;
        if (std.mem.eql(u8, identifier, "popn")) return .PopN;
        if (std.mem.eql(u8, identifier, "pushi")) return .PushI;
        if (std.mem.eql(u8, identifier, "pushn")) return .PushN;
        if (std.mem.eql(u8, identifier, "pushf")) return .PushF;
        if (std.mem.eql(u8, identifier, "pushs")) return .PushS;
        if (std.mem.eql(u8, identifier, "pushg")) return .PushG;
        if (std.mem.eql(u8, identifier, "pushl")) return .PushL;
        if (std.mem.eql(u8, identifier, "pushsp")) return .PushSP;
        if (std.mem.eql(u8, identifier, "pushfp")) return .PushFP;
        if (std.mem.eql(u8, identifier, "pushgp")) return .PushGP;
        if (std.mem.eql(u8, identifier, "store")) return .Store;
        if (std.mem.eql(u8, identifier, "storel")) return .StoreL;
        if (std.mem.eql(u8, identifier, "stroeg")) return .StoreG;
        if (std.mem.eql(u8, identifier, "storen")) return .StoreN;

        return error.NoMatch;
    }

    pub fn parseGenericInteger(self: *Parser, comptime T: type) !T {
        const start = self.position;

        while (self.peek()) |char| {
            if (char >= '0' and char <= '9') {
                _ = self.read();
            } else if (self.position.offset == start.offset and (char == '+' or char == '-')) {
                _ = self.read();
            } else {
                break;
            }
        }

        if (self.position.offset > start.offset) {
            const intSlice = self.source[start.offset..self.position.offset];

            return try std.fmt.parseInt(T, intSlice, 10);
        } else {
            return error.NoMatch;
        }
    }

    pub fn parseInteger(self: *Parser) !i32 {
        return self.parseGenericInteger(i32);
    }

    pub fn parseFloat(self: *Parser) !f64 {
        const start = self.position;

        var has_decimals: bool = false;

        while (self.peek()) |char| {
            if (char >= '0' and char <= '9') {
                _ = self.read();
            } else if (self.position.offset == start.offset and (char == '+' or char == '-')) {
                _ = self.read();
            } else if (!has_decimals and char == '.') {
                _ = self.read();
                has_decimals = true;
            } else {
                break;
            }
        }

        if (self.position.offset > start.offset) {
            const floatSlice = self.source[start.offset .. self.position.offset];

            return try std.fmt.parseFloat(f64, floatSlice);
        } else {
            return error.NoMatch;
        }
    }

    pub fn parseAddress(self: *Parser) !usize {
        return self.parseGenericInteger(usize);
    }

    pub fn parseString(self: *Parser) ![]const u8 {
        const start = self.position;

        if (self.peek()) |quote_char| {
            if (quote_char == '"' or quote_char == '\'') {
                _ = self.read();

                var buffer = ArrayList(u8).init(self.allocator);
                defer buffer.deinit();

                var escaping: bool = false;

                while (self.peek()) |char| {
                    if (escaping) {
                        // TODO: Add more escape characters
                        try buffer.append(switch (char) {
                            'n' => '\n',
                            't' => '\t',
                            'r' => '\r',
                            else => char,
                        });

                        escaping = false;
                    } else {
                        if (char == '\\') {
                            escaping = true;
                        } else if (char == quote_char) {
                            _ = self.read();
                            break;
                        } else {
                            try buffer.append(char);
                        }
                    }

                    _ = self.read();
                }

                return buffer.toOwnedSlice();
            }
        }

        return error.NoMatch;
    }

    pub fn parseInstructionParameter(self: *Parser, instruction: Instruction) !?InstructionParameter {
        // return error.NoMatch;
        switch (instruction) {
            //     // ParameterLess
            .Concat, .Call, .Return, .Stop, .Start, .Nop, .Atoi, // String to int
                .Atof, .Itof, .Ftoi, .Stri, // Int to string
                .Strf, // Float to string
                .DupN, .AllocN, .Free, .Equal, // Heap
                .FAdd, .FSub, .FMul, .FDiv, .FInf, .FInfEq, .FSup, .FSupEq, .FCos, .FSin, // Float
                .Add, .Sub, .Mul, .Div, .Mod, .Inf, .InfEq, .Sup, .SupEq, .Not, // Integers
                .LoadN, .Swap, .Debug, .WriteI, .WriteF, .WriteS, .Read, .Padd, // IO
                .WritelnI, .WritelnF, .WritelnS, // NewLine IO
                .PopN, .PushSP, .PushFP, .PushGP, .StoreN => return null,

            // Integer Parameters
            .Dup, .Load, .Pop, .PushI, .PushN, .PushG, .PushL, .Store, .StoreL, .StoreG => return InstructionParameter{ .Integer = try self.parseInteger() },

            // Float Parameters
            .PushF => return InstructionParameter{ .Float = try self.parseFloat() },

            // Address Parameters
            .Jump, .Jz, .PushA, .Alloc => {
                const backtrack = self.position;

                const addr_match = self.parseAddress() catch |err| switch (err) {
                    error.NoMatch => null,
                    else => return err,
                };

                if (addr_match) |addr| {
                    return InstructionParameter{ .Address = addr };
                } else {
                    self.seekTo(backtrack);

                    const label = try self.parseIdentifier();

                    return InstructionParameter{ .Label = label };
                }
            },

            // String Parameters
            .PushS, .Err => return InstructionParameter{ .String = try self.parseString() },
            else => return error.NoMatch,
        }
    }

    pub fn parse(self: *Parser) !InstructionsReader {
        var writer = InstructionsWriter.init(self.allocator);
        defer writer.deinit();

        var label_addresses: StringHashMap(usize) = StringHashMap(usize).init(self.allocator);
        defer label_addresses.deinit();

        var label_placeholders: ArrayList(LabelPlaceholder) = ArrayList(LabelPlaceholder).init(self.allocator);
        defer label_placeholders.deinit();

        while (!self.endOfFile()) {
            self.skipWhiteSpace();

            var backtrack = self.position;

            var label_match = self.parseLabelMarker() catch |err| switch (err) {
                error.NoMatch => null,
                else => return err,
            };

            if (label_match) |label| {
                _ = try label_addresses.put(label, writer.bytecode.items.len);

                continue;
            }

            self.seekTo(backtrack);

            self.source_map.beginInstruction(writer.bytecode.items.len, self.position);

            var instruction_match = self.parseInstruction() catch |err| switch (err) {
                error.NoMatch => null,
                else => return err,
            };

            if (instruction_match) |inst| {
                try writer.writeInstruction(inst);

                self.skipWhiteSpace();

                const parameter = self.parseInstructionParameter(inst) catch |err| switch (err) {
                    error.NoMatch => {
                        self.err_message = try self.allocator.dupe(u8, "No valid instruction parameter.");
                        return err;
                    },
                    else => return err,
                };

                if (parameter) |p| switch (p) {
                    .Float => |float| try writer.writeFloat(float),
                    .Integer => |int| try writer.writeInteger(int),
                    .Address => |addr| try writer.writeSize(addr),
                    .String => |str| {
                        try writer.writeString(str);

                        self.allocator.free(str);
                    },
                    .Label => |lbl| {
                        try label_placeholders.append(LabelPlaceholder{
                            .name = lbl,
                            .position = writer.bytecode.items.len,
                        });

                        try writer.writeSize(0);
                    },
                };

                try self.source_map.endInstruction(self.position);

                continue;
            }

            // What happens when there is not match at all? Return error
            self.err_message = try self.allocator.dupe(u8, "No valid instruction or label matched.");

            return error.NoMatch;
        }

        for (label_placeholders.items) |label| {
            if (label_addresses.getValue(label.name)) |addr| {
                try writer.writeSizeAt(addr, label.position);
            } else {
                return error.MissingLabel;
            }
        }

        return writer.reader();
    }
};

pub const TextPosition = struct {
    line: usize,
    column: usize,
    offset: usize,

    pub fn init(line: usize, column: usize, offset: usize) TextPosition {
        return TextPosition{
            .line = line,
            .column = column,
            .offset = offset,
        };
    }

    pub fn initEmpty() TextPosition {
        return TextPosition.init(0, 0, 0);
    }
};

pub const InstructionSpan = struct {
    instruction: usize,
    start: TextPosition,
    end: TextPosition,
};

pub const SourceMap = struct {
    instructions_positions: RedBlackTree(InstructionSpan, SourceMap.compareSpan),
    current_position: TextPosition,
    current_instruction: usize,

    pub fn init(allocator: *Allocator) SourceMap {
        return SourceMap{
            .instructions_positions = RedBlackTree(InstructionSpan, SourceMap.compareSpan).init(allocator),
            .current_position = TextPosition.initEmpty(),
            .current_instruction = 0,
        };
    }

    pub fn deinit(self: *SourceMap) void {
        self.instructions_positions.deinit();
    }

    pub fn beginInstruction(self: *SourceMap, instruction: usize, position: TextPosition) void {
        self.current_instruction = instruction;
        self.current_position = position;
    }

    pub fn endInstruction(self: *SourceMap, position: TextPosition) !void {
        const span = InstructionSpan{
            .instruction = self.current_instruction,
            .start = self.current_position,
            .end = position,
        };

        try self.instructions_positions.insert(span);
    }

    pub fn find(self: *SourceMap, instruction: usize) ?InstructionSpan {
        const node = self.instructions_positions.closestSmaller(InstructionSpan{
            .instruction = instruction,
            .start = TextPosition.initEmpty(),
            .end = TextPosition.initEmpty(),
        }) orelse return null;

        return node.value;
    }

    pub fn move(self: *SourceMap) SourceMap {
        const destination = SourceMap.init(self.instructions_positions.allocator);

        destination.instructions_positions = self.instructions_positions.move();
        destination.current_position = self.current_position;
        destination.current_instruction = self.current_instruction;

        return destination;
    }

    pub fn compareSpan(a: InstructionSpan, b: InstructionSpan) i32 {
        return if (a.instruction < b.instruction) -1 else @boolToInt(a.instruction > b.instruction);
    }
};
