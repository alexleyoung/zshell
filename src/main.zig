const std = @import("std");

const Command = enum {
    echo,
    exit,
    type,
    invalid,

    pub fn fromString(str: []const u8) ?Command {
        const command = std.meta.stringToEnum(Command, str);
        return command;
    }
};

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    while (true) {
        try stdout.interface.print("$ ", .{});

        const input = try stdin.interface.takeDelimiter('\n') orelse "";

        var iterator = std.mem.splitAny(u8, input, " ");
        const command = Command.fromString(iterator.next().?) orelse .invalid;
        const args = iterator.rest();

        switch (command) {
            .echo => {
                try stdout.interface.print("{s}\n", .{args});
            },
            .exit => {
                break;
            },
            .type => if (Command.fromString(args) != null)
                try stdout.interface.print("{s} is a shell builtin\n", .{args})
            else
                try stdout.interface.print("{s}: not found\n", .{args}),
            .invalid => try stdout.interface.print("{s}: command not found\n", .{input}),
        }
    }
}
