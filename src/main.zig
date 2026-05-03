const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});

    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    while (true) {
        try stdout.interface.print("$ ", .{});
        const command = try stdin.interface.takeDelimiter('\n');

        var parts = std.mem.splitScalar(u8, command.?, ' ');

        if (std.mem.eql(u8, "exit", parts.peek().?)) {
            break;
        } else if (std.mem.eql(u8, "echo", parts.peek().?)) {
            try stdout.interface.print("{s}\n", .{command.?[5..]});
        } else if (std.mem.eql(u8, "type", parts.peek().?)) {
            _ = parts.next();
            // check if built-in
            if (std.mem.eql(u8, "exit", parts.peek().?) or
                std.mem.eql(u8, "echo", parts.peek().?) or
                std.mem.eql(u8, "type", parts.peek().?))
            {
                try stdout.interface.print("{s} is a shell builtin\n", .{parts.peek().?});
            } else {
                try stdout.interface.print("{s}: command not found\n", .{parts.peek().?});
            }
        } else {
            try stdout.interface.print("{s}: command not found\n", .{command.?});
        }
    }
}
