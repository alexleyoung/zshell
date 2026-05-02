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
            _ = parts.next();
            while (parts.next()) |part| {
                try stdout.interface.print("{s}", .{part});
                try stdout.interface.print(" ", .{});
            }
            try stdout.interface.print("\n", .{});
        } else {
            try stdout.interface.print("{s}: command not found\n", .{command.?});
        }
    }
}
