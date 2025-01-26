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

const PORT: u32 = constants.PORT;

const StateServicePayload = [_]u8{
    0x01,
    @truncate(PORT & 0xFF),
    @truncate((PORT >> 8) & 0xFF),
    @truncate((PORT >> 16) & 0xFF),
    @truncate((PORT >> 24) & 0xFF),
};

const LightStatePayload = [_]u8{
    0xaa, 0xaa, // hue
    0x02, 0x03, // saturation
    0x04, 0x05, // brightness
    0x06, 0x07, // kelvin
    0x08, 0x09, // duration
};

fn encodeResponse(
    allocator: std.mem.Allocator,
    req: []const u8,
    commandType: u16,
    payload: ?[]const u8,
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
        payload,
    );
}

const TARGET: [6]u8 = [_]u8{ 0x98, 0x76, 0x54, 0x32, 0x10, 0xcd };
pub fn main() !void {
    var fixedBuffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fixedBuffer);
    const allocator = fba.allocator();

    // const StateServiceResponse = encoding.encode(allocator, false, 0, TARGET, false, false, 0, @intFromEnum(constants.CommandType.StateService), &StateServicePayload) catch |err| {
    //     std.debug.print("Failed to encode response: {any}\n", .{err});
    //     return;
    // };

    try network.init();
    defer network.deinit();

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    var sock = try network.Socket.create(.ipv4, .udp);
    defer sock.close();
    try sock.setBroadcast(true);

    // try sock.bind(network.SocketAddress.init(.ipv4, "0.0.0.0", 56700));
    try sock.bind(try network.EndPoint.parse("0.0.0.0:56700"));

    var buffer: [1024]u8 = undefined;
    while (true) {
        std.debug.print("Waiting for message...\n", .{});
        const recv_result = try sock.receiveFrom(&buffer);
        const slice = buffer[0..recv_result.numberOfBytes];
        const responseFlags = encoding.getHeaderResponseFlags(slice, 0);
        const ackRequired = encoding.getHeaderAcknowledgeRequired(responseFlags);
        if (ackRequired) {
            const message = encodeResponse(allocator, slice, @intFromEnum(constants.CommandType.Acknowledgement), null) catch |err| {
                std.debug.print("Failed to encode response: {any}\n", .{err});
                continue;
            };
            defer allocator.free(message);
            _ = sock.sendTo(recv_result.sender, message) catch |err| {
                std.debug.print("Failed to send message to {any}: {any}\n", .{ recv_result.sender, err });
            };
        }

        switch (encoding.getHeaderType(slice, 0)) {
            @intFromEnum(constants.CommandType.GetService) => {
                std.debug.print("Received GetService from {any}\n", .{recv_result.sender});

                const res = encodeResponse(allocator, slice, @intFromEnum(constants.CommandType.StateService), &StateServicePayload) catch |err| {
                    std.debug.print("Failed to encode response: {any}\n", .{err});
                    continue;
                };
                defer allocator.free(res);

                _ = sock.sendTo(recv_result.sender, res) catch |err| {
                    std.debug.print("Failed to send message to {any}: {any}\n", .{ recv_result.sender, err });
                };
            },
            @intFromEnum(constants.CommandType.GetColor) => {
                std.debug.print("Received GetColor from {any}\n", .{recv_result.sender});

                const res = encodeResponse(allocator, slice, @intFromEnum(constants.CommandType.LightState), &LightStatePayload) catch |err| {
                    std.debug.print("Failed to encode response: {any}\n", .{err});
                    continue;
                };
                defer allocator.free(res);

                _ = sock.sendTo(recv_result.sender, res) catch |err| {
                    std.debug.print("Failed to send message to {any}: {any}\n", .{ recv_result.sender, err });
                };
            },
            else => {
                const res = encoding.decodeHeader(slice, 0);
                std.debug.print("Received unknown message from {any}\n", .{res});
            },
        }
    }
}
