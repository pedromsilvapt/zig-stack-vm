const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const VirtualMachine = @import("./vm.zig").VirtualMachine;
const Registers = @import("./vm.zig").Registers;
const StackFrame = @import("./vm.zig").StackFrame;
const Value = @import("./vm.zig").Value;

pub const Instruction = enum(u8) {
    Concat,
    // Control
    Jump,
    Jz, // Jump Conditional
    PushA,
    Call,
    Return,
    Start,
    Nop,
    Stop,
    Err,

    // Convert
    Atoi, // String to int
    Atof,
    Itof,
    Ftoi,
    Stri, // Int to string
    Strf, // Float to string

    Dup,
    DupN,

    FAdd,
    FSub,
    FMul,
    FDiv,
    FInf,
    FInfEq,
    FSup,
    FSupEq,
    FCos,
    FSin,

    Alloc,
    AllocN,
    Free,
    Equal,

    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Inf,
    InfEq,
    Sup,
    SupEq,
    Not,

    Load,
    LoadN,

    Swap,
    Debug,

    WriteI,
    WritelnI,
    WriteF,
    WritelnF,
    WriteS,
    WritelnS,
    Read,

    Padd,

    Pop,
    PopN,
    PushI,
    PushN,
    PushF,
    PushS,
    PushG,
    PushL,
    PushSP,
    PushFP,
    PushGP,

    Store,
    StoreL,
    StoreG,
    StoreN,

    pub fn execute(self: Instruction, vm: *VirtualMachine) !void {
        // std.debug.print("Executing instruction {}\n", .{self});
        return switch (self) {
            .Jump => instJump(vm),
            .Jz => instJz(vm), // Jump Conditional
            .PushA => instPushA(vm),
            .Call => instCall(vm),
            .Return => instReturn(vm),
            .Start => {},
            .Nop => {},
            .Stop => instStop(vm),
            .Err => instErr(vm),

            .Concat => instConcat(vm),

            // Convert
            .Atoi => instAtoi(vm), // String to int
            .Atof => instAtof(vm),
            .Itof => instItof(vm),
            .Ftoi => instFtoi(vm),
            .Stri => instStri(vm), // Int to string
            .Strf => instStrf(vm), // Float to string

            .Dup => instDup(vm),
            .DupN => instDupN(vm),

            .FAdd => instFAdd(vm),
            .FSub => instFSub(vm),
            .FMul => instFMul(vm),
            .FDiv => instFDiv(vm),
            .FInf => instFInf(vm),
            .FInfEq => instFInfEq(vm),
            .FSup => instFSup(vm),
            .FSupEq => instFSupEq(vm),
            .FCos => instFCos(vm),
            .FSin => instFSin(vm),

            .Alloc => instAlloc(vm),
            .AllocN => instAllocN(vm),
            .Free => instFree(vm),
            .Equal => instEqual(vm),

            .Add => instAdd(vm),
            .Sub => instSub(vm),
            .Mul => instMul(vm),
            .Div => instDiv(vm),
            .Mod => instMod(vm),
            .Inf => instInf(vm),
            .InfEq => instInfEq(vm),
            .Sup => instSup(vm),
            .SupEq => instSupEq(vm),
            .Not => instNot(vm),

            .Load => instLoad(vm),
            .LoadN => instLoadN(vm),

            .Swap => instSwap(vm),
            .Debug => {},

            .WriteI => instWriteI(vm),
            .WritelnI => instWritelnI(vm),
            .WriteF => instWriteF(vm),
            .WritelnF => instWritelnF(vm),
            .WriteS => instWriteS(vm),
            .WritelnS => instWritelnS(vm),
            .Read => instRead(vm),

            .Padd => instPadd(vm),

            .Pop => instPop(vm),
            .PopN => instPopN(vm),
            .PushI => instPushI(vm),
            .PushN => instPushN(vm),
            .PushF => instPushF(vm),
            .PushS => instPushS(vm),
            .PushG => instPushG(vm),
            .PushL => instPushL(vm),
            .PushSP => instPushSP(vm),
            .PushFP => instPushFP(vm),
            .PushGP => instPushGP(vm),

            .Store => instStore(vm),
            .StoreL => instStoreL(vm),
            .StoreG => instStoreG(vm),
            .StoreN => instStoreN(vm),

            else => error.InstructionNotSupported,
        };
    }
};

fn padd(address: usize, offset: i32) usize {
    if (offset > 0) {
        return address + @intCast(usize, offset);
    } else {
        return address - @intCast(usize, offset * -1);
    }
}

pub inline fn instCall(vm: *VirtualMachine) !void {
    const address = vm.stack.pop().AddressCode;

    const frame = StackFrame.init(vm.registers.frame_pointer, Registers.get_code_pointer(vm));

    try vm.frames.push(frame);

    vm.registers.frame_pointer = Registers.get_stack_pointer(vm);
    Registers.set_code_pointer(vm, address);
}

pub inline fn instReturn(vm: *VirtualMachine) !void {
    const frame = vm.frames.pop();

    while (Registers.get_stack_pointer(vm) > vm.registers.frame_pointer) {
        _ = vm.stack.pop();
    }

    vm.registers.frame_pointer = frame.frame_pointer;
    Registers.set_code_pointer(vm, frame.code_pointer);
}

pub inline fn instStop(vm: *VirtualMachine) !void {
    vm.registers.stop = true;
}

pub inline fn instErr(vm: *VirtualMachine) !void {
    vm.registers.err = try vm.registers.allocator.dupe(u8, try vm.bytecode.readString());
}

pub inline fn instJump(vm: *VirtualMachine) !void {
    const address = try vm.bytecode.readSize();

    Registers.set_code_pointer(vm, address);
}

pub inline fn instJz(vm: *VirtualMachine) !void {
    const address = try vm.bytecode.readSize();

    const condition = vm.stack.pop().Integer;

    if (condition == 0) {
        Registers.set_code_pointer(vm, address);
    }
}

pub inline fn instPushA(vm: *VirtualMachine) !void {
    const address = try vm.bytecode.readSize();

    try vm.stack.push(.{ .AddressCode = address });
}

pub inline fn instAtoi(vm: *VirtualMachine) !void {
    const addr = vm.stack.pop().AddressString;

    const slice = try vm.strings.loadAll(addr);

    const int = try std.fmt.parseInt(i32, slice, 10);

    try vm.stack.push(.{ .Integer = int });
}

pub inline fn instAtof(vm: *VirtualMachine) !void {
    const addr = vm.stack.pop().AddressString;

    const slice = try vm.strings.loadAll(addr);

    const float = try std.fmt.parseFloat(f64, slice);

    try vm.stack.push(.{ .Float = float });
}

pub inline fn instItof(vm: *VirtualMachine) !void {
    const int = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Float = @intToFloat(f64, int) });
}

pub inline fn instFtoi(vm: *VirtualMachine) !void {
    const float = vm.stack.pop().Float;

    try vm.stack.push(.{ .Integer = @floatToInt(i32, float) });
}

pub inline fn instStri(vm: *VirtualMachine) !void {
    const int = vm.stack.pop().Integer;

    var buf: [11]u8 = undefined;

    var len = std.fmt.formatIntBuf(&buf, int, 10, false, std.fmt.FormatOptions{});

    const address = try vm.strings.alloc(len);

    try vm.strings.storeMany(address, buf[0..len]);

    try vm.stack.push(.{ .AddressString = address });
}

pub inline fn instStrf(vm: *VirtualMachine) !void {
    const float = vm.stack.pop().Float;

    // TODO:
    // var buf: [30]u8 = undefined;

    // var len = std.fmt.formatFloatDecimal(buf, float, 10, false, std.fmt.FormatOptions{});

    // const address = try vm.strings.alloc(len);

    // try vm.strings.storeMany(address, buf[0..len]);

    // try vm.stack.push(.{ .AddressString = address });
}

pub inline fn instDup(vm: *VirtualMachine) !void {
    const n = try vm.bytecode.readInteger();

    const pointer = Registers.get_stack_pointer(vm);

    var i: i32 = 0;

    while (i < n) : (i += 1) {
        try vm.stack.push(try vm.stack.load(padd(pointer, -n + i)));
    }
}

pub inline fn instDupN(vm: *VirtualMachine) !void {
    const n = vm.stack.pop().Integer;

    const pointer = Registers.get_stack_pointer(vm);

    var i: i32 = 0;

    while (i < n) : (i += 1) {
        try vm.stack.push(try vm.stack.load(padd(pointer, -n + i)));
    }
}

pub inline fn instAlloc(vm: *VirtualMachine) !void {
    const size = try vm.bytecode.readSize();

    const address = try vm.heap.alloc(size);

    try vm.stack.push(.{ .AddressHeap = address });
}

pub inline fn instAllocN(vm: *VirtualMachine) !void {
    const size = vm.stack.pop().Integer;

    if (size <= 0) return error.InvalidOperand;

    const address = try vm.heap.alloc(@intCast(usize, size));

    try vm.stack.push(.{ .AddressHeap = address });
}

pub inline fn instFree(vm: *VirtualMachine) !void {
    const address = vm.stack.pop();

    vm.heap.free(address.AddressHeap);
}

pub inline fn instEqual(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop();
    const op1 = vm.stack.pop();

    // TODO: Improve type checking
    const equal = switch (op1) {
        .Float => |num| num == op2.Float,
        .Integer => |num| num == op2.Integer,
        .String => |str| std.mem.eql(u8, str, op2.String),
        .AddressCode => |addr| addr == op2.AddressCode,
        .AddressHeap => |addr| addr == op2.AddressHeap,
        .AddressStack => |addr| addr == op2.AddressStack,
        .AddressString => |addr| addr == op2.AddressString,
    };

    try vm.stack.push(.{ .Integer = @boolToInt(equal) });
}

pub inline fn instFAdd(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Float;
    const op1 = vm.stack.pop().Float;

    try vm.stack.push(.{ .Float = op1 + op2 });
}

pub inline fn instFSub(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Float;
    const op1 = vm.stack.pop().Float;

    try vm.stack.push(.{ .Float = op1 - op2 });
}

pub inline fn instFMul(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Float;
    const op1 = vm.stack.pop().Float;

    try vm.stack.push(.{ .Float = op1 * op2 });
}

pub inline fn instFDiv(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Float;
    const op1 = vm.stack.pop().Float;

    try vm.stack.push(.{ .Float = op1 / op2 });
}

pub inline fn instFInf(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Float;
    const op1 = vm.stack.pop().Float;

    try vm.stack.push(.{ .Integer = @boolToInt(op1 < op2) });
}

pub inline fn instFInfEq(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Float;
    const op1 = vm.stack.pop().Float;

    try vm.stack.push(.{ .Integer = @boolToInt(op1 <= op2) });
}

pub inline fn instFSup(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Float;
    const op1 = vm.stack.pop().Float;

    try vm.stack.push(.{ .Integer = @boolToInt(op1 > op2) });
}

pub inline fn instFSupEq(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Float;
    const op1 = vm.stack.pop().Float;

    try vm.stack.push(.{ .Integer = @boolToInt(op1 >= op2) });
}

pub inline fn instFCos(vm: *VirtualMachine) !void {
    const op = vm.stack.pop().Float;

    try vm.stack.push(.{ .Float = std.math.cos(op) });
}

pub inline fn instFSin(vm: *VirtualMachine) !void {
    const op = vm.stack.pop().Float;

    try vm.stack.push(.{ .Float = std.math.sin(op) });
}

pub inline fn instAdd(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = op1 + op2 });
}

pub inline fn instSub(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = op1 - op2 });
}

pub inline fn instMul(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = op1 * op2 });
}

pub inline fn instDiv(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = @divFloor(op1, op2) });
}

pub inline fn instMod(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = @mod(op1, op2) });
}

pub inline fn instInf(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = @boolToInt(op1 < op2) });
}

pub inline fn instInfEq(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = @boolToInt(op1 <= op2) });
}

pub inline fn instSup(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = @boolToInt(op1 > op2) });
}

pub inline fn instSupEq(vm: *VirtualMachine) !void {
    const op2 = vm.stack.pop().Integer;
    const op1 = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = @boolToInt(op1 >= op2) });
}

pub inline fn instNot(vm: *VirtualMachine) !void {
    const op = vm.stack.pop().Integer;

    try vm.stack.push(.{ .Integer = @boolToInt(!(op != 0)) });
}

pub inline fn instLoad(vm: *VirtualMachine) !void {
    const address = vm.stack.pop();

    const offset = try vm.bytecode.readInteger();

    // TODO: GC
    var value = switch (address) {
        .AddressHeap => |addr| try vm.heap.load(padd(addr, offset)),
        .AddressStack => |addr| try vm.stack.load(padd(addr, offset)),
        else => return error.InvalidOperand,
    };

    try vm.stack.push(value);
}

pub inline fn instLoadN(vm: *VirtualMachine) !void {
    const offset = vm.stack.pop().Integer;

    const address = vm.stack.pop();

    // TODO: GC
    var value = switch (address) {
        .AddressHeap => |addr| try vm.heap.load(padd(addr, offset)),
        .AddressStack => |addr| try vm.stack.load(padd(addr, offset)),
        else => return error.InvalidOperand,
    };

    try vm.stack.push(value);
}

pub inline fn instSwap(vm: *VirtualMachine) !void {
    const value1 = vm.stack.pop();
    const value2 = vm.stack.pop();

    try vm.stack.push(value1);
    try vm.stack.push(value2);
}

pub inline fn instWriteI(vm: *VirtualMachine) !void {
    const int = vm.stack.pop().Integer;

    // _ = try std.format.format(std.io.getStdOut(), )
    try std.io.getStdOut().writer().print("{}", .{int});
}

pub inline fn instWritelnI(vm: *VirtualMachine) !void {
    const int = vm.stack.pop().Integer;

    // _ = try std.format.format(std.io.getStdOut(), )
    try std.io.getStdOut().writer().print("{}\n", .{int});
}

pub inline fn instWriteF(vm: *VirtualMachine) !void {
    const float = vm.stack.pop().Float;

    // _ = try std.format.format(std.io.getStdOut(), )
    try std.io.getStdOut().writer().print("{d}", .{float});
}

pub inline fn instWritelnF(vm: *VirtualMachine) !void {
    const float = vm.stack.pop().Float;

    // _ = try std.format.format(std.io.getStdOut(), )
    try std.io.getStdOut().writer().print("{d}\n", .{float});
}

pub inline fn instWriteS(vm: *VirtualMachine) !void {
    const str_addr = vm.stack.pop().AddressString;

    const str = try vm.strings.loadAll(str_addr);

    _ = try std.io.getStdOut().write(str);
}

pub inline fn instWritelnS(vm: *VirtualMachine) !void {
    const str_addr = vm.stack.pop().AddressString;

    const str = try vm.strings.loadAll(str_addr);

    _ = try std.io.getStdOut().write(str);
    _ = try std.io.getStdOut().write("\n");
}

pub inline fn instRead(vm: *VirtualMachine) !void {
    const max_input_size = 1024 * 1024;

    var read_slice = try std.io.getStdIn().reader().readUntilDelimiterAlloc( //
        vm.allocator, '\n', max_input_size // Parameters
    );

    errdefer vm.allocator.free(read_slice);

    if (read_slice.len > 0 and read_slice[read_slice.len - 1] == '\n') {
        read_slice = read_slice[0 .. read_slice.len - 1];
    }

    if (read_slice.len > 0 and read_slice[read_slice.len - 1] == '\r') {
        read_slice = read_slice[0 .. read_slice.len - 1];
    }

    try vm.strings.memory.insert(read_slice);
    errdefer vm.strings.memory.delete(read_slice);

    const address = @ptrToInt(read_slice.ptr);

    try vm.stack.push(Value{ .AddressString = address });
}

pub inline fn instConcat(vm: *VirtualMachine) !void {
    var s2 = vm.stack.pop().AddressString;
    var s1 = vm.stack.pop().AddressString;

    const s1_value = try vm.strings.loadAll(s1);
    const s2_value = try vm.strings.loadAll(s2);

    // TODO: When to free s1 and s2?
    var address = try vm.strings.alloc(s1_value.len + s2_value.len);
    errdefer vm.strings.free(address);

    try vm.strings.storeMany(address, s1_value);
    try vm.strings.storeMany(address + s1_value.len, s2_value);

    try vm.stack.push(Value{ .AddressString = address });
}

pub inline fn instPadd(vm: *VirtualMachine) !void {
    const offset = vm.stack.pop().Integer;

    var address = vm.stack.pop();

    // TODO: GC
    address = switch (address) {
        .AddressCode => |addr| Value{ .AddressCode = padd(addr, offset) },
        .AddressHeap => |addr| Value{ .AddressHeap = padd(addr, offset) },
        .AddressStack => |addr| Value{ .AddressStack = padd(addr, offset) },
        .AddressString => |addr| Value{ .AddressString = padd(addr, offset) },
        else => return error.InvalidOperand,
    };

    try vm.stack.push(address);
}

pub inline fn instPop(vm: *VirtualMachine) !void {
    const n = try vm.bytecode.readInteger();

    var i: i32 = 0;
    while (i < n) : (i += 1) {
        _ = vm.stack.pop();
    }
}

pub inline fn instPopN(vm: *VirtualMachine) !void {
    const n = vm.stack.pop().Integer;

    var i: i32 = 0;
    while (i < n) : (i += 1) {
        _ = vm.stack.pop();
    }
}

pub inline fn instPushI(vm: *VirtualMachine) !void {
    const n = try vm.bytecode.readInteger();

    try vm.stack.push(Value{ .Integer = n });
}

pub inline fn instPushN(vm: *VirtualMachine) !void {
    const n = try vm.bytecode.readInteger();

    var i: i32 = 0;
    while (i < n) : (i += n) {
        try vm.stack.push(Value{ .Integer = 0 });
    }
}

pub inline fn instPushF(vm: *VirtualMachine) !void {
    const n = try vm.bytecode.readFloat();

    try vm.stack.push(Value{ .Float = n });
}

pub inline fn instPushS(vm: *VirtualMachine) !void {
    const n = try vm.bytecode.readString();

    const address = try vm.strings.alloc(n.len);
    errdefer vm.strings.free(address);

    try vm.strings.storeMany(address, n);

    try vm.stack.push(Value{ .AddressString = address });
}

pub inline fn instPushG(vm: *VirtualMachine) !void {
    const n = try vm.bytecode.readInteger();

    const index = padd(vm.registers.global_pointer, n);

    const value = try vm.stack.load(index);

    try vm.stack.push(value);
}

pub inline fn instPushL(vm: *VirtualMachine) !void {
    const n = try vm.bytecode.readInteger();

    const index = padd(vm.registers.frame_pointer, n);

    const value = try vm.stack.load(index);

    try vm.stack.push(value);
}

pub inline fn instPushSP(vm: *VirtualMachine) !void {
    try vm.stack.push(Value{ .AddressStack = Registers.get_stack_pointer(vm) });
}

pub inline fn instPushFP(vm: *VirtualMachine) !void {
    try vm.stack.push(Value{ .AddressStack = vm.registers.frame_pointer });
}

pub inline fn instPushGP(vm: *VirtualMachine) !void {
    try vm.stack.push(Value{ .AddressStack = vm.registers.global_pointer });
}

pub inline fn instStore(vm: *VirtualMachine) !void {
    // We read the value we want to store from the operands stack
    const value = vm.stack.pop();

    // And also the address to store it in, from the operands stack
    const address = vm.stack.pop();

    // Additionally we also accept an offset for the address, as a parameter
    const offset = try vm.bytecode.readInteger();

    switch (address) {
        .AddressHeap => |addr| {
            // TODO: GC
            _ = try vm.heap.store(padd(addr, offset), value);
        },
        .AddressStack => |addr| {
            // TODO: GC
            _ = try vm.stack.store(padd(addr, offset), value);
        },
        else => return error.InvalidOperand,
    }
}

pub inline fn instStoreL(vm: *VirtualMachine) !void {
    // We read the value we want to store from the operands stack
    const value = vm.stack.pop();

    // Additionally we also accept an offset for the address, as a parameter
    const offset = try vm.bytecode.readInteger();

    const frame_pointer = vm.registers.frame_pointer;

    // TODO: GC
    _ = try vm.stack.store(padd(frame_pointer, offset), value);
}

pub inline fn instStoreG(vm: *VirtualMachine) !void {
    // We read the value we want to store from the operands stack
    const value = vm.stack.pop();

    // Additionally we also accept an offset for the address, as a parameter
    const offset = try vm.bytecode.readInteger();

    const global_pointer = vm.registers.global_pointer;

    // TODO: GC
    _ = try vm.stack.store(padd(global_pointer, offset), value);
}

pub inline fn instStoreN(vm: *VirtualMachine) !void {
    const value = vm.stack.pop();

    // Additionally we also accept an offset for the address, as a parameter
    const offset = vm.stack.pop().Integer;

    // And also the address to store it in, from the operands stack
    const address = vm.stack.pop();

    switch (address) {
        .AddressHeap => |addr| {
            // TODO: GC
            _ = try vm.heap.store(padd(addr, offset), value);
        },
        .AddressStack => |addr| {
            // TODO: GC
            _ = try vm.stack.store(padd(addr, offset), value);
        },
        else => return error.InvalidOperand,
    }
}

pub const InstructionsWriter = struct {
    bytecode: ArrayList(u8),
    cursor: ?usize = null,

    pub fn init(allocator: *Allocator) InstructionsWriter {
        return .{ .bytecode = ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *InstructionsWriter) void {
        self.bytecode.deinit();
    }

    pub fn write(self: *InstructionsWriter, byte: u8) !void {
        if (self.cursor) |cur| {
            self.bytecode.items[cur] = byte;

            self.cursor = cur + 1;
        } else {
            try self.bytecode.append(byte);
        }
    }

    pub fn writeSlice(self: *InstructionsWriter, byte: []const u8) !void {
        if (self.cursor) |cur| {
            std.mem.copy(u8, self.bytecode.items[cur..], byte);

            self.cursor = cur + byte.len;
        } else {
            try self.bytecode.appendSlice(byte);
        }
    }

    pub fn writeInstruction(self: *InstructionsWriter, instr: Instruction) !void {
        try self.write(@enumToInt(instr));
    }

    pub fn writeString(self: *InstructionsWriter, str: []const u8) !void {
        try self.writeSize(str.len);

        try self.writeSlice(str);
    }

    pub fn writeIntegerSized(self: *InstructionsWriter, comptime T: type, comptime size: usize, value: T) !void {
        var bytes: [size]u8 = undefined;

        comptime var i = 0;
        inline while (i < size) : (i += 1) {
            bytes[i] = @intCast(u8, (value >> (8 * (size - 1 - i))) & 0xFF);
        }

        try self.writeSlice(&bytes);
    }

    pub fn writeSize(self: *InstructionsWriter, value: usize) !void {
        return self.writeIntegerSized(usize, 8, value);
    }

    pub fn writeSizeAt(self: *InstructionsWriter, value: usize, cursor: usize) !void {
        self.cursor = cursor;
        try self.writeSize(value);
        self.cursor = null;
    }

    pub fn writeInteger(self: *InstructionsWriter, value: i32) !void {
        return self.writeIntegerSized(i32, 4, value);
    }

    pub fn writeFloat(self: *InstructionsWriter, value: f64) !void {
        return self.writeSize(@bitCast(usize, value));
    }

    // Transfers ownership of the byte array
    pub fn reader(self: *InstructionsWriter) InstructionsReader {
        return InstructionsReader.initOwned(self.bytecode.allocator, self.bytecode.toOwnedSlice());
    }
};

pub const InstructionsReader = struct {
    allocator: ?*Allocator,
    owned: bool,
    array: []const u8,
    cursor: usize,

    pub fn init(array: []const u8) InstructionsReader {
        return .{
            .allocator = null,
            .owned = false,
            .array = array,
            .cursor = 0,
        };
    }

    pub fn initOwned(allocator: *Allocator, array: []const u8) InstructionsReader {
        return .{
            .allocator = allocator,
            .owned = true,
            .array = array,
            .cursor = 0,
        };
    }

    pub fn deinit(self: *InstructionsReader) void {
        if (self.owned) {
            self.allocator.?.free(self.array);
        }
    }

    pub fn endOfFile(self: *InstructionsReader) bool {
        return self.cursor >= self.array.len;
    }

    pub fn read(self: *InstructionsReader) !u8 {
        if (self.cursor + 1 > self.array.len) return error.OutOfBounds;

        defer self.cursor += 1;

        return self.array[self.cursor];
    }

    pub fn readSlice(self: *InstructionsReader, n: usize) ![]const u8 {
        if (self.cursor + n > self.array.len) return error.OutOfBounds;

        defer self.cursor += n;

        return self.array[self.cursor .. self.cursor + n];
    }

    pub fn readInstruction(self: *InstructionsReader) !Instruction {
        return @intToEnum(Instruction, try self.read());
    }

    pub fn readIntegerSized(self: *InstructionsReader, comptime T: type) !T {
        const size: comptime_int = switch (@typeInfo(T)) {
            .Int => |t| t.bits / 8,
            else => @compileError("Expected an integer type."),
        };

        const slice = try self.readSlice(size);

        var res: T = 0;

        comptime var i = 0;
        inline while (i < size) : (i += 1) {
            res |= @intCast(T, slice[i]) << (8 * (size - 1 - i));
        }

        return res;
    }

    pub fn readSize(self: *InstructionsReader) !usize {
        return self.readIntegerSized(usize);
    }

    pub fn readInteger(self: *InstructionsReader) !i32 {
        // return (@intCast(i32, slice[0]) << 24) | (@intCast(i32, slice[1]) << 16) | (@intCast(i32, slice[2]) << 8) | @intCast(i32, slice[3]);
        return self.readIntegerSized(i32);
    }

    pub fn readFloat(self: *InstructionsReader) !f64 {
        return @bitCast(f64, try self.readSize());
    }

    pub fn readString(self: *InstructionsReader) ![]const u8 {
        const len = try self.readSize();

        return self.readSlice(len);
    }
};
