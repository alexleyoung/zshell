const std = @import("std");

const Command = enum {
    echo,
    exit,
    type,
    external,
};

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    const env = init.environ_map;
    const PATH_string = env.get("PATH") orelse return error.MissingPath;

    var iter_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer iter_arena.deinit();
    while (true) {
        defer _ = iter_arena.reset(.retain_capacity);
        const alloc = iter_arena.allocator();

        try stdout.interface.print("$ ", .{});

        const input_str = try stdin.interface.takeDelimiter('\n') orelse "";
        const args = try parseArgs(alloc, input_str);
        if (args.len == 0) continue;

        const command = std.meta.stringToEnum(Command, args[0]) orelse Command.external;
        switch (command) {
            .echo => try stdout.interface.print("{s}\n", .{try std.mem.join(alloc, " ", args[1..])}),
            .exit => break,
            .type => {
                if (args.len < 2) {
                    try stdout.interface.print("type: missing argument\n", .{});
                    continue;
                }
                const executable_name = args[1];
                if (std.meta.stringToEnum(Command, executable_name)) |_| {
                    try stdout.interface.print("{s} is a shell builtin\n", .{executable_name});
                } else {
                    // find executable
                    const executable_path = try findExecutablePath(alloc, init.io, PATH_string, executable_name);
                    if (executable_path) |path| {
                        try stdout.interface.print("{s} is {s}\n", .{ executable_name, path });
                    } else {
                        try stdout.interface.print("{s}: not found\n", .{executable_name});
                    }
                }
            },
            .external => {
                const executable_path = try findExecutablePath(alloc, init.io, PATH_string, args[0]);
                if (executable_path != null) {
                    const res = try std.process.run(alloc, init.io, .{
                        .argv = args,
                        .environ_map = env,
                    });
                    try stdout.interface.print("{s}", .{res.stdout});
                } else {
                    try stdout.interface.print("{s}: command not found\n", .{args[0]});
                }
            },
        }
    }
}

/// Helper which parses a line into a list of args
fn parseArgs(alloc: std.mem.Allocator, line: []const u8) ![][]const u8 {
    var out = try std.ArrayList([]const u8).initCapacity(alloc, 16);

    // parser states
    const State = enum { normal, single, double };
    var state = State.normal;

    // parse line
    var buf = try std.ArrayList(u8).initCapacity(alloc, 16);
    var escape = false;
    for (line) |c| {
        if (escape) {
            try buf.append(alloc, c);
            escape = false;
            continue;
        }
        switch (state) {
            .normal => switch (c) {
                ' ' => if (buf.items.len != 0)
                    try out.append(alloc, try buf.toOwnedSlice(alloc)),
                '\\' => escape = true,
                '\'' => state = .single,
                '\"' => state = .double,
                else => try buf.append(alloc, c),
            },
            .single => switch (c) {
                '\'' => state = .normal,
                else => try buf.append(alloc, c),
            },
            .double => switch (c) {
                '"' => state = .normal,
                '\\' => escape = true,
                else => try buf.append(alloc, c),
            },
        }
    }

    // trailing arg
    // TODO: update this so we prompt for continuation
    if (buf.items.len != 0)
        try out.append(alloc, try buf.toOwnedSlice(alloc));

    return out.items;
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
