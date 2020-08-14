const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const RedBlackTree = @import("./rbt.zig").RedBlackTree;
pub const Instruction = @import("./instruction.zig").Instruction;
pub const InstructionsWriter = @import("./instruction.zig").InstructionsWriter;
pub const InstructionsReader = @import("./instruction.zig").InstructionsReader;
pub const Parser = @import("./parser.zig").Parser;

pub const VirtualMachine = struct {
    allocator: *Allocator,
    registers: Registers,
    heap: Heap(Value),
    strings: Heap(u8),
    stack: Stack(Value),
    frames: Stack(StackFrame),
    bytecode: InstructionsReader,

    // Useful for debugging. Gives the position of the last instruction the
    // virtual machine read
    last_instruction: usize = 0,

    pub fn init(allocator: *Allocator, bytecode: InstructionsReader) VirtualMachine {
        var vm = .{
            .allocator = allocator,
            .registers = Registers.init(allocator),
            .heap = Heap(Value).init(allocator),
            .strings = Heap(u8).init(allocator),
            .stack = Stack(Value).init(allocator),
            .frames = Stack(StackFrame).init(allocator),
            .bytecode = bytecode,
        };

        return vm;
    }

    pub fn initFile(allocator: *Allocator, file_path: []const u8) !VirtualMachine {
        var parser = try Parser.initFile(allocator, file_path);
        defer parser.deinit();

        var reader = try parser.parse();

        return VirtualMachine.init(allocator, reader);
    }

    pub fn execute(self: *VirtualMachine) !void {
        while (true) {
            self.last_instruction = self.bytecode.cursor;

            const instruction = try self.bytecode.readInstruction();

            instruction.execute(self) catch |err| {
                return err;
            };

            if (self.registers.err != null) return error.RuntimeError;

            if (self.bytecode.endOfFile() or self.registers.stop) break;
        }
    }

    pub fn deinit(self: *VirtualMachine) void {
        self.heap.deinit();
        self.strings.deinit();
        self.stack.deinit();
        self.frames.deinit();
        self.registers.deinit();
        self.bytecode.deinit();
    }
};

pub const StackFrame = struct {
    frame_pointer: usize = 0,
    code_pointer: usize = 0,

    pub fn init(fp: usize, cp: usize) StackFrame {
        return .{ .frame_pointer = fp, .code_pointer = cp };
    }
};

pub const Registers = struct {
    // Used to allocate space on the heap for runtime error messages
    allocator: *Allocator,

    frame_pointer: usize = 0,
    global_pointer: usize = 0,
    stop: bool = false,
    err: ?[]const u8 = null,

    pub fn init(allocator: *Allocator) Registers {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registers) void {
        if (self.err) |err| self.allocator.free(err);
    }

    pub fn get_code_pointer(vm: *VirtualMachine) usize {
        return vm.bytecode.cursor;
    }

    pub fn set_code_pointer(vm: *VirtualMachine, value: usize) void {
        vm.bytecode.cursor = value;
    }

    pub fn get_stack_pointer(vm: *VirtualMachine) usize {
        return vm.stack.len;
    }

    pub fn set_stack_pointer(vm: *VirtualMachine, value: usize) void {
        // TODO: Should we be able to do this? I dunno
    }
};

pub const Value = union(enum) {
    Integer: i32,
    Float: f64,
    String: []u8,
    AddressHeap: usize,
    AddressString: usize,
    AddressCode: usize,
    AddressStack: usize,
};

fn sliceComparator(comptime T: type) (fn ([]T, []T) i32) {
    return struct {
        fn comp(a: []T, b: []T) i32 {
            const ai = @ptrToInt(a.ptr);
            const bi = @ptrToInt(b.ptr);

            return if (ai < bi) -1 else @boolToInt(ai > bi);
        }
    }.comp;
}

pub fn Heap(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: *Allocator,
        memory: RedBlackTree([]T, comptime sliceComparator(T)),

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .allocator = allocator,
                .memory = RedBlackTree([]T, comptime sliceComparator(T)).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.memory.iterPre(false);

            while (iter.next()) |value| {
                self.allocator.free(value);
            }

            self.memory.deinit();
        }

        fn get(self: *Self, address: usize) ?[]T {
            if (address == 0) return null;

            const search_slice = @ptrCast([*]T, @intToPtr(*T, address))[0..1];

            const node = self.memory.closestSmaller(search_slice) orelse return null;

            return node.value;
        }

        fn getSlice(self: *Self, address: usize, len: usize) ?[]T {
            const whole_slice = self.get(address) orelse return null;

            const offset = address - @ptrToInt(whole_slice.ptr);

            if (offset < 0 or len > whole_slice.len - offset) return null;

            return whole_slice[offset..len];
        }

        fn getRemainingSlice(self: *Self, address: usize) ?[]T {
            const whole_slice = self.get(address) orelse return null;

            const offset = address - @ptrToInt(whole_slice.ptr);

            if (offset < 0) return null;

            return whole_slice[offset..];
        }

        fn getPointer(self: *Self, address: usize) ?*T {
            const slice = self.get(address) orelse return null;

            const offset = address - @ptrToInt(slice.ptr);

            if (offset < 0 or offset >= slice.len) return null;

            return &slice[offset];
        }

        pub fn alloc(self: *Self, size: usize) !usize {
            const slice = try self.allocator.alloc(T, size);

            try self.memory.insert(slice);

            return @ptrToInt(slice.ptr);
        }

        pub fn free(self: *Self, address: usize) void {
            const slice = self.get(address) orelse return;

            self.allocator.free(slice);

            _ = self.memory.delete(slice);
        }

        pub fn load(self: *Self, address: usize) !T {
            const pointer = self.getPointer(address) orelse return error.InvalidAddress;

            return pointer.*;
        }

        pub fn loadMany(self: *Self, address: usize, len: usize) ![]T {
            return self.getSlice(address, len) orelse return error.InvalidAddress;
        }

        pub fn loadAll(self: *Self, address: usize) ![]T {
            return self.getRemainingSlice(address) orelse return error.InvalidAddress;
        }

        pub fn store(self: *Self, address: usize, value: T) !void {
            const pointer = self.getPointer(address) orelse return error.InvalidAddress;

            pointer.* = value;
        }

        pub fn storeMany(self: *Self, address: usize, values: []const T) !void {
            const slice = self.getSlice(address, values.len) orelse return error.InvalidAddress;

            std.mem.copy(T, slice, values);
        }
    };
}

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        list: ArrayList(T),
        len: usize,
        capacity: usize,

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .list = ArrayList(T).init(allocator),
                .len = 0,
                .capacity = 0,
            };
        }

        pub fn initCapacity(allocator: *Allocator, capacity: usize) Self {
            return Self{
                .list = ArrayList(T).init(allocator),
                .len = 0,
                .capacity = capacity,
            };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit();
        }

        pub fn load(self: *const Self, index: usize) !T {
            if (index < 0) return error.OutOfBounds;
            if (index >= self.len) return error.OutOfBounds;

            return self.list.items[index];
        }

        pub fn store(self: *Self, index: usize, value: T) !T {
            if (index < 0) return error.OutOfBounds;
            if (index >= self.len) return error.OutOfBounds;

            defer self.list.items[index] = value;

            return self.list.items[index];
        }

        pub fn storeNoClobber(self: *Self, index: usize, value: T) !void {
            _ = try self.store(index, value);
        }

        pub fn push(self: *Self, value: T) !void {
            defer self.len += 1;
            try self.list.append(value);
        }

        pub fn pop(self: *Self) T {
            defer self.len -= 1;

            return self.list.pop();
        }
    };
}
