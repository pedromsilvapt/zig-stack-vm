pub const VirtualMachine = @import("./vm.zig").VirtualMachine;
pub const Value = @import("./vm.zig").Value;
pub const Registers = @import("./vm.zig").Registers;
pub const Instruction = @import("./instruction.zig").Instruction;
pub const InstructionsWriter = @import("./instruction.zig").InstructionsWriter;
pub const InstructionsReader = @import("./instruction.zig").InstructionsReader;
pub const Parser = @import("./parser.zig").Parser;
pub const SourceMap = @import("./parser.zig").SourceMap;
pub const TextPosition = @import("./parser.zig").TextPosition;
pub const InstructionSpan = @import("./parser.zig").InstructionSpan;

const std = @import("std");
const Allocator = std.mem.Allocator;
const Gpa = std.heap.GeneralPurposeAllocator(.{});

comptime {
    @export(Instruction, .{ .name = "stackvm_instruction_t" });
    @export(TextPosition, .{ .name = "stackvm_textposition_t" });
    @export(InstructionSpan, .{ .name = "stackvm_instructionspan_t" });
    @export(SourceMap, .{ .name = "stackvm_sourcemap_t" });
    @export(ParserExtern, .{ .name = "stackvm_parser_t" });
    @export(ValueExtern, .{ .name = "stackvm_value_t" });
    @export(ValueType, .{ .name = "stackvm_valuetype_t" });
    @export(ValueUnion, .{ .name = "stackvm_valueunion_t" });
}

export fn stackvm_allocator_init() *Allocator {
    var general_purpose_allocator = std.heap.page_allocator.create(Gpa) catch {
        @panic("Could not create allocator.\n");
    };
    
    general_purpose_allocator.* = Gpa {};

    return &general_purpose_allocator.allocator;
}

export fn stackvm_allocator_deinit(allocator: *Allocator) void {
    var general_purpose_allocator = @fieldParentPtr(Gpa, "allocator", allocator);

    _ = general_purpose_allocator.deinit();

    std.heap.page_allocator.destroy(general_purpose_allocator);
}

export fn stackvm_instructionspan_init(instruction: usize, start: TextPosition, end: TextPosition) InstructionSpan {
    return InstructionSpan.init(instruction, start, end);
}

export fn stackvm_instructionspan_init_empty() InstructionSpan {
    return InstructionSpan.init(0, TextPosition.initEmpty(), TextPosition.initEmpty());
}

export fn stackvm_sourcemap_init(allocator: *Allocator) SourceMap {
    return SourceMap.init(allocator);
}

export fn stackvm_sourcemap_deinit(ptr: *SourceMap) void {
    ptr.deinit();
}

export fn stackvm_sourcemap_find(ptr: *SourceMap, bytecode_pos: usize, span_result: *InstructionSpan) bool {
    if (ptr.find(bytecode_pos)) |span| {
        span_result.* = span;
        return true;
    }

    return false;
}

export fn stackvm_sourcemap_move(ptr: *SourceMap) SourceMap {
    return ptr.move();
}

pub const ParserExtern = extern struct {
    parser: *Parser,
    source: [*]u8,
    source_len: usize,
};

export fn stackvm_parser_init(allocator: *Allocator, source: [*]const u8, source_len: usize) ParserExtern {
    var slice = allocator.dupe(u8, source[0..source_len]) catch unreachable;

    var ptr = allocator.create(Parser) catch unreachable;
    ptr.* = Parser.initOwned(allocator, slice);

    return ParserExtern{
        .parser = ptr,
        .source = slice.ptr,
        .source_len = slice.len,
    };
}

export fn stackvm_parser_deinit(parser: *ParserExtern) void {
    const allocator = parser.parser.allocator;

    parser.parser.deinit();

    allocator.destroy(parser.parser);
}

export fn stackvm_parser_get_position(parser: *ParserExtern) TextPosition {
    return parser.parser.position;
}

export fn stackvm_parser_get_source_map(parser: *ParserExtern) SourceMap {
    return parser.parser.source_map;
}

export fn stackvm_parser_get_err_message(parser: *ParserExtern, result_len: *usize) ?[*]const u8 {
    const slice = parser.parser.err_message orelse {
        result_len.* = 0;

        return null;
    };

    result_len.* = slice.len;

    return slice.ptr;
}

export fn stackvm_parser_get_current_line(parser: *ParserExtern, result_len: *usize) ?[*]const u8 {
    const slice = parser.parser.getCurrentLine();

    result_len.* = slice.len;

    return slice.ptr;
}

export fn stackvm_parser_get_source_span(parser: *ParserExtern, start: TextPosition, end: TextPosition, result_len: *usize) ?[*]const u8 {
    const slice = parser.parser.getSourceSpan(start, end);

    result_len.* = slice.len;

    return slice.ptr;
}

export fn stackvm_parser_parse(parser: *ParserExtern) ?*InstructionsReader {
    const allocator = parser.parser.allocator;

    const ptr = allocator.create(InstructionsReader) catch return null;

    ptr.* = parser.parser.parse() catch {
        allocator.destroy(ptr);

        return null;
    };

    return ptr;
}

export fn stackvm_reader_get_len(reader: *InstructionsReader) usize {
    return reader.array.len;
}

export fn stackvm_reader_deinit(reader: *InstructionsReader) void {
    const allocator = reader.allocator.?;

    reader.deinit();

    allocator.destroy(reader);
}

export fn stackvm_reader_destroy(allocator: *Allocator, reader: *InstructionsReader) void {
    allocator.destroy(reader);
}

export fn stackvm_init(allocator: *Allocator, reader: *InstructionsReader) ?*VirtualMachine {
    var ptr = allocator.create(VirtualMachine) catch return null;

    ptr.* = VirtualMachine.init(allocator, reader.*);

    return ptr;
}

export fn stackvm_deinit(vm: *VirtualMachine) void {
    const allocator = vm.allocator;

    vm.deinit();

    allocator.destroy(vm);
}

export fn stackvm_execute(vm: *VirtualMachine) bool {
    vm.execute() catch return false;

    return true;
}

export fn stackvm_get_last_instruction(vm: *VirtualMachine) usize {
    return vm.last_instruction;
}

export fn stackvm_get_err_message(vm: *VirtualMachine, result_len: *usize) ?[*]const u8 {
    const slice = vm.registers.err orelse {
        result_len.* = 0;

        return null;
    };

    result_len.* = slice.len;

    return slice.ptr;
}

export fn stackvm_registers_get_frame_pointer(vm: *VirtualMachine) usize {
    return vm.registers.frame_pointer;
}

export fn stackvm_registers_set_frame_pointer(vm: *VirtualMachine, value: usize) void {
    vm.registers.frame_pointer = value;
}

export fn stackvm_registers_get_global_pointer(vm: *VirtualMachine) usize {
    return vm.registers.global_pointer;
}

export fn stackvm_registers_set_global_pointer(vm: *VirtualMachine, value: usize) void {
    vm.registers.global_pointer = value;
}

export fn stackvm_registers_get_code_pointer(vm: *VirtualMachine) usize {
    return Registers.getCodePointer(vm);
}

export fn stackvm_registers_set_code_pointer(vm: *VirtualMachine, value: usize) void {
    Registers.setCodePointer(vm, value);
}

export fn stackvm_registers_get_stack_pointer(vm: *VirtualMachine) usize {
    return Registers.getStackPointer(vm);
}

export fn stackvm_registers_set_stack_pointer(vm: *VirtualMachine, value: usize) void {
    Registers.setStackPointer(vm, value);
}

pub const ValueExtern = extern struct {
    kind: ValueType,
    value: ValueUnion,

    pub fn init(value_type: ValueType, value: ValueUnion) ValueExtern {
        return .{ .kind = value_type, .value = value };
    }
    pub fn initNone() ValueExtern {
        return .{ .kind = .None, .value = ValueUnion{ .integer = 0 } };
    }

    pub fn initIntern(value: Value) ValueExtern {
        switch (value) {
            .Integer => |val| return ValueExtern.init(.Integer, .{ .integer = val }),
            .Float => |val| return ValueExtern.init(.Float, .{ .float = val }),
            .AddressHeap => |val| return ValueExtern.init(.AddressHeap, .{ .size = val }),
            .AddressString => |val| return ValueExtern.init(.AddressString, .{ .size = val }),
            .AddressCode => |val| return ValueExtern.init(.AddressCode, .{ .size = val }),
            .AddressStack => |val| return ValueExtern.init(.AddressStack, .{ .size = val }),
            .String => unreachable,
        }
    }

    pub fn toIntern(self: *const ValueExtern) ?Value {
        std.debug.print("Test kind {}\n", .{self.kind});
        switch (self.kind) {
            .Integer => return Value{ .Integer = self.value.integer },
            .Float => return Value{ .Float = self.value.float },
            .AddressHeap => return Value{ .AddressHeap = self.value.size },
            .AddressString => return Value{ .AddressString = self.value.size },
            .AddressCode => return Value{ .AddressCode = self.value.size },
            .AddressStack => return Value{ .AddressStack = self.value.size },
            .None => return null,
        }
    }
};

pub const ValueUnion = extern union {
    integer: i32,
    float: f64,
    size: usize,
};

pub const ValueType = extern enum(u8) {
    None = 0,
    Integer = 1,
    Float = 2,
    AddressHeap = 3,
    AddressString = 4,
    AddressCode = 5,
    AddressStack = 6,
};

fn vmPtr(ptr: *u8) *VirtualMachine {
    return @ptrCast(*VirtualMachine, @alignCast(@alignOf(*VirtualMachine), ptr));
}

export fn stackvm_value_int(value: i32) ValueExtern {
    return ValueExtern.init(.Integer, ValueUnion{ .integer = value });
}

export fn stackvm_value_float(value: f64) ValueExtern {
    return ValueExtern.init(.Float, ValueUnion{ .float = value });
}

export fn stackvm_value_size(value_type: ValueType, value: usize) ValueExtern {
    if (value_type == .None or value_type == .Integer or value_type == .Float) {
        return ValueExtern.init(.None, ValueUnion{ .integer = 0 });
    }

    return ValueExtern.init(value_type, ValueUnion{ .size = value });
}

export fn stackvm_stack_get_len(vm: *VirtualMachine) usize {
    return vm.stack.len;
}

export fn stackvm_stack_load(vm: *VirtualMachine, index: usize) ValueExtern {
    var value = vm.stack.load(index) catch return ValueExtern.initNone();

    return ValueExtern.initIntern(value);
}

export fn stackvm_stack_store_int(vm: *VirtualMachine, index: usize, value: i32) void {
    _ = vm.stack.store(index, Value{ .Integer = value }) catch return;
}

export fn stackvm_stack_store_float(vm: *VirtualMachine, index: usize, value: f64) void {
    _ = vm.stack.store(index, Value{ .Float = value }) catch return;
}
export fn stackvm_stack_store_address(vm: *VirtualMachine, index: usize, kind: ValueType, value: usize) void {
    const value_intern = switch (kind) {
        .AddressCode => Value{ .AddressCode = value },
        .AddressHeap => Value{ .AddressHeap = value },
        .AddressString => Value{ .AddressString = value },
        .AddressStack => Value{ .AddressStack = value },
        else => return,
    };

    _ = vm.stack.store(index, value_intern) catch return;
}

export fn stackvm_stack_push_int(vm: *VirtualMachine, value: i32) void {
    _ = vm.stack.push(Value{ .Integer = value }) catch return;
}

export fn stackvm_stack_push_float(vm: *VirtualMachine, value: f64) void {
    _ = vm.stack.push(Value{ .Float = value }) catch return;
}

export fn stackvm_stack_push_address(vm: *VirtualMachine, kind: ValueType, value: usize) void {
    const value_intern = switch (kind) {
        .AddressCode => Value{ .AddressCode = value },
        .AddressHeap => Value{ .AddressHeap = value },
        .AddressString => Value{ .AddressString = value },
        .AddressStack => Value{ .AddressStack = value },
        else => return,
    };

    _ = vm.stack.push(value_intern) catch return;
}

export fn stackvm_stack_pop(vm: *VirtualMachine) ValueExtern {
    return ValueExtern.initIntern(vm.stack.pop() catch return ValueExtern.initNone());
}
