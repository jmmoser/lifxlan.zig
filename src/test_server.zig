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
    }
}
