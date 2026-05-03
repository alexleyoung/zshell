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
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const env = init.environ_map;
    const PATH_string = env.get("PATH").?;

    while (true) {
        _ = arena.reset(.retain_capacity);
        const alloc = arena.allocator();

        try stdout.interface.print("$ ", .{});

        const input = try stdin.interface.takeDelimiter('\n') orelse "";
        var inp_iter = std.mem.splitScalar(u8, input, ' ');

        // parse input into array(list) of strings
        var input_arr = try std.ArrayList([]const u8).initCapacity(alloc, 16);
        while (inp_iter.next()) |inp| {
            try input_arr.append(alloc, inp);
        }
        if (input_arr.items.len == 0) continue;

        const command = Command.fromString(input_arr.items[0]) orelse Command.external;
        switch (command) {
            .echo => try stdout.interface.print("{s}\n", .{try std.mem.join(alloc, " ", input_arr.items[1..])}),
            .exit => break,
            .type => {
                const executable_name = input_arr.items[1];
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
                const executable_path = try findExecutablePath(alloc, init.io, PATH_string, input_arr.items[0]);
                if (executable_path != null) {
                    const res = try std.process.run(alloc, init.io, .{
                        .argv = input_arr.items,
                        .environ_map = env,
                    });
                    try stdout.interface.print("{s}", .{res.stdout});
                } else {
                    try stdout.interface.print("{s}: command not found\n", .{input});
                }
            },
        }
    }
}

pub fn findExecutablePath(alloc: std.mem.Allocator, io: std.Io, PATH_string: []const u8, name: []const u8) !?[]const u8 {
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
