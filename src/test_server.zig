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

const label = "Macbook Pro";
const StateLabelPayload: *const [32]u8 = label ++ [_]u8{0} ** (32 - label.len);

const StateVersionPayload = [_]u8{
    0x01, 0x00, 0x00, 0x00,
    94,   0x00, 0x00, 0x00,
};

fn encodeResponse(
    buffer: []u8,
    req: []const u8,
    commandType: u16,
    payload: ?[]const u8,
) void {
    encoding.encode(
        buffer,
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
    try network.init();
    defer network.deinit();

    var sock = try network.Socket.create(.ipv4, .udp);
    defer sock.close();
    try sock.setBroadcast(true);

    try sock.bind(try network.EndPoint.parse("0.0.0.0:56700"));

    var buffer: [1024]u8 = undefined;
    while (true) {
        std.debug.print("Waiting for message...\n", .{});
        const recv_result = try sock.receiveFrom(&buffer);
        const slice = buffer[0..recv_result.numberOfBytes];
        const responseFlags = encoding.getHeaderResponseFlags(slice, 0);
        const ackRequired = encoding.getHeaderAcknowledgeRequired(responseFlags);
        if (ackRequired) {
            var responseBuffer: [1024]u8 = undefined;
            encodeResponse(&responseBuffer, slice, @intFromEnum(constants.CommandType.Acknowledgement), null);

            _ = sock.sendTo(recv_result.sender, &responseBuffer) catch |err| {
                std.debug.print("Failed to send message to {any}: {any}\n", .{ recv_result.sender, err });
            };
        }

        var responseBuffer: [1024]u8 = undefined;

        switch (encoding.getHeaderType(slice, 0)) {
            @intFromEnum(constants.CommandType.GetService) => {
                std.debug.print("Received GetService from {any}\n", .{recv_result.sender});

                encodeResponse(&responseBuffer, slice, @intFromEnum(constants.CommandType.StateService), &StateServicePayload);

                _ = sock.sendTo(recv_result.sender, &responseBuffer) catch |err| {
                    std.debug.print("Failed to send message to {any}: {any}\n", .{ recv_result.sender, err });
                };
            },
            @intFromEnum(constants.CommandType.GetColor) => {
                std.debug.print("Received GetColor from {any}\n", .{recv_result.sender});

                encodeResponse(&responseBuffer, slice, @intFromEnum(constants.CommandType.LightState), &LightStatePayload);

                _ = sock.sendTo(recv_result.sender, &responseBuffer) catch |err| {
                    std.debug.print("Failed to send message to {any}: {any}\n", .{ recv_result.sender, err });
                };
            },
            @intFromEnum(constants.CommandType.GetLabel) => {
                std.debug.print("Received GetLabel from {any}\n", .{recv_result.sender});

                encodeResponse(&responseBuffer, slice, @intFromEnum(constants.CommandType.StateLabel), StateLabelPayload);

                _ = sock.sendTo(recv_result.sender, &responseBuffer) catch |err| {
                    std.debug.print("Failed to send message to {any}: {any}\n", .{ recv_result.sender, err });
                };
            },
            @intFromEnum(constants.CommandType.GetVersion) => {
                std.debug.print("Received GetVersion from {any}\n", .{recv_result.sender});

                encodeResponse(&responseBuffer, slice, @intFromEnum(constants.CommandType.StateVersion), &StateVersionPayload);

                _ = sock.sendTo(recv_result.sender, &responseBuffer) catch |err| {
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
