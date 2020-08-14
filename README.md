# zig-stack-vm

A reimplementation of a university project in zig. Implements a simple stack-based
bytecode virtual machine.

## Installation
This project was developed on Zig 0.6. Zig is a fast moving language, newer versions
might not be able to compile it.

```bash
git clone https://github.com/pedromsilvapt/zig-stack-vm.git
cd zig-stack-vm
zig build
```

Optionally one can build the application in release mode to get better
execution performance (at the expense of compilation speed).

```bash
zig build -Drelease-fast
```

## Usage
The compiled application can be ran directly from the command line, and accepts
one file path as an argument.
```bash
./zig-cache/bin/stackvm examples/fib.ir
```

Aditionally one can also embed the virtual machine in a custom application easily.
Just add the package path in your build file and require it like so.

```zig
const std = @import("std");
const svm = @import("stack-vm");
const Parser = svm.Parser;
const VirtualMachine = svm.VirtualMachine;

pub fn main () !void {
    // Like most libraries in zig, this project is allocator-agnostic,
    // This means you have to pass in an allocator yourself.
    // The page_allocator uses direct calls to mmap, and thus is not recommended
    // for real world use directly. However, Zig currently does not have a 
    // General Purpose Allocator yet, so we can use it just for testing purposes,
    // or pass in the std.heap.c_allocator, which requires linking against 
    // libc when compiling the project
    const allocator = std.heap.page_allocator;
    
    const source = 
        \\ pushs "Type your name, please.\n"
        \\ writes
        \\ read
        \\ pushs "Hello, "
        \\ writes
        \\ writes
        \\ pushs "!\n"
        \\ writes
        ;

    var parser = try Parser.init(allocator, source);
    defer parser.deinit();

    var bytecode = try parser.parse();

    // Takes ownership of the bytecode and is responsible for freeing it on deinit
    var vm = VirtualMachine.init(allocator, bytecode);
    defer vm.deinit();

    try vm.execute();
}
```
