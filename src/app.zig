const std = @import("std");
const clap = @import("clap");
const VirtualMachine = @import("./vm.zig").VirtualMachine;
const Instruction = @import("./instruction.zig").Instruction;
const InstructionsWriter = @import("./instruction.zig").InstructionsWriter;
const InstructionsReader = @import("./instruction.zig").InstructionsReader;
const Parser = @import("./parser.zig").Parser;

pub fn main() anyerror!void {
    const alloc = std.heap.page_allocator;

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help          Display this help and exit.              ") catch unreachable,
        clap.Param(clap.Help){
            .takes_value = true,
        },
    };

    var iter = try clap.args.OsIterator.init(alloc);
    defer iter.deinit();

    // Parse the arguments
    var args = try clap.ComptimeClap(clap.Help, &params).parse(alloc, clap.args.OsIterator, &iter);
    defer args.deinit();

    if (args.flag("--help")) {
        const stderr_file = std.io.getStdErr();
        var stderr_out_stream = stderr_file.outStream();

        try clap.help(stderr_out_stream, &params);
    } else {
        const positionals = args.positionals();

        if (positionals.len == 0) {
            std.debug.print("Please provide a file to run.", .{});
            return;
        }

        var parser = try Parser.initFile(alloc, positionals[0]);
        defer parser.deinit();

        var reader = parser.parse() catch |err| {
            if (parser.err_message) |msg| {
                std.debug.print("ERROR Ln {}, Col {}: {}\n", .{ parser.position.line + 1, parser.position.column + 1, msg });
            } else {
                std.debug.print("ERROR Ln {}, Col {}\n", .{ parser.position.line + 1, parser.position.column + 1 });
            }

            std.debug.print("\t{}\n", .{parser.getCurrentLine()});

            return;
        };

        var vm = VirtualMachine.init(alloc, reader);
        defer vm.deinit();

        vm.execute() catch |err| {
            var msg: []const u8 = switch (err) {
                error.RuntimeError => vm.registers.err.?,
                else => @errorName(err),
            };

            if (parser.source_map.find(vm.last_instruction)) |span| {
                std.debug.print("Runtime Error in Ln {}, Col {}: {}\n", .{ span.start.line + 1, span.start.column + 1, msg });
                std.debug.print("\t{}\n", .{parser.getSourceSpan(span.start, span.end)});
            } else {
                std.debug.print("Runtime Error: {}\n", .{msg});
                std.debug.print("Instruction Address: {}\n", .{vm.last_instruction});
            }
        };
    }
}
