const std = @import("std");

const Command = enum {
    echo,
    exit,
    type,
    external,

    pub fn fromString(str: []const u8) ?Command {
        const command = std.meta.stringToEnum(Command, str);
        return command;
    }
};

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    const env = init.environ_map;
    const PATH_string = env.get("PATH").?;

    while (true) {
        const alloc = init.arena.allocator();

        try stdout.interface.print("$ ", .{});

        const input_str = try stdin.interface.takeDelimiter('\n') orelse "";
        const input = try parseArgs(alloc, input_str);
        if (input.items.len == 0) continue;

        const command = Command.fromString(input.items[0]) orelse Command.external;
        switch (command) {
            .echo => try stdout.interface.print("{s}\n", .{try std.mem.join(alloc, " ", input.items[1..])}),
            .exit => break,
            .type => {
                const executable_name = input.items[1];
                if (Command.fromString(executable_name) != null) {
                    try stdout.interface.print("{s} is a shell builtin\n", .{executable_name});
                } else {
                    // find executable
                    const executable_path = try findExecutablePath(alloc, init.io, PATH_string, executable_name);
                    if (executable_path != null) {
                        try stdout.interface.print("{s} is {s}\n", .{ executable_name, executable_path.? });
                    } else {
                        try stdout.interface.print("{s}: not found\n", .{executable_name});
                    }
                }
            },
            .external => {
                const executable_path = try findExecutablePath(alloc, init.io, PATH_string, input.items[0]);
                if (executable_path != null) {
                    const res = try std.process.run(alloc, init.io, .{
                        .argv = input.items,
                        .environ_map = env,
                    });
                    try stdout.interface.print("{s}", .{res.stdout});
                } else {
                    try stdout.interface.print("{s}: command not found\n", .{input.items[0]});
                }
            },
        }
    }
}

/// Helper which parses a line into a list of args
fn parseArgs(alloc: std.mem.Allocator, line: []const u8) !std.ArrayList([]const u8) {
    var out = try std.ArrayList([]const u8).initCapacity(alloc, 16);

    // parse line
    var buf = try std.ArrayList(u8).initCapacity(alloc, 16);
    var in_quote = false;
    for (line) |c| {
        if (c == ' ' and !in_quote) {
            try out.append(alloc, try buf.toOwnedSlice(alloc));
        } else if (c == '\'') {
            in_quote = !in_quote;
        } else {
            try buf.append(alloc, c);
        }
    }

    // trailing arg
    try out.append(alloc, try buf.toOwnedSlice(alloc));

    return out;
}

/// Helper which, given a user's PATH, searches for an executable and if found returns the path to the executable
fn findExecutablePath(alloc: std.mem.Allocator, io: std.Io, PATH_string: []const u8, name: []const u8) !?[]const u8 {
    const path_sep = std.Io.Dir.path.delimiter;

    var paths = std.mem.splitScalar(u8, PATH_string, path_sep);

    while (paths.next()) |p| {
        const dir = (std.Io.Dir.openDirAbsolute(io, p, .{
            .access_sub_paths = false,
        }) catch continue);
        defer dir.close(io);
        dir.access(io, name, .{ .execute = true }) catch continue;
        return try std.Io.Dir.path.join(alloc, &.{ p, name });
    }
    return null;
}
