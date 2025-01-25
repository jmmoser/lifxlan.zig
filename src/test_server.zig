const std = @import("std");
const network = @import("network");
const ansi = @import("ansi-term");
const types = @import("types.zig");
const devicesMod = @import("devices.zig");
const commands = @import("commands.zig");
const encoding = @import("encoding.zig");
const constants = @import("constants.zig");
const utils = @import("utils.zig");

const stdout = std.io.getStdOut().writer();

fn encodeResponse(
    allocator: std.mem.Allocator,
    req: []const u8,
    commandType: u16,
) ![]u8 {
    return encoding.encode(
        allocator,
        encoding.getHeaderTagged(req, 0),
        encoding.getHeaderSource(req, 0),
        TARGET,
        false,
        false,
        encoding.getHeaderSequence(req, 0),
        commandType,
        null,
    );
}

const TARGET: [6]u8 = [_]u8{ 0x97, 0x98, 0x99, 0x100, 0x101, 0x102 };
pub fn main() !void {
    try network.init();
    defer network.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sock = try network.Socket.create(.ipv4, .udp);
    defer sock.close();
    try sock.setBroadcast(true);

    var buffer: [1024]u8 = undefined;
    while (true) {
        const recv_result = try sock.receiveFrom(&buffer);
        const slice = buffer[0..recv_result.numberOfBytes];
        const responseFlags = encoding.getHeaderResponseFlags(slice);
        const ackRequired = encoding.getHeaderAcknowledgeRequired(responseFlags);
        if (ackRequired) {
            const message = encodeResponse(allocator, slice, constants.CommandType.Acknowledgement) catch |err| {
                std.debug.print("Failed to encode response: {any}\n", .{err});
                continue;
            };
            defer allocator.free(message);
            sock.sendTo(recv_result.sender, message) catch |err| {
                std.debug.print("Failed to send message to {any}: {any}\n", .{ recv_result.sender, err });
            };
        }

        switch (encoding.getHeaderType(slice, 0)) {
            constants.CommandType.GetService => {
                std.debug.print("Received GetService from {any}\n", .{recv_result.sender});
            },
            else => {
                std.debug.print("Received unknown message from {any}\n", .{recv_result.sender});
            },
        }
    }
}
