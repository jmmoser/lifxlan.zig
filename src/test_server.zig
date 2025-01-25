const std = @import("std");
const network = @import("network");
const ansi = @import("ansi-term");
const types = @import("types.zig");
const router = @import("router.zig");
const devicesMod = @import("devices.zig");
const commands = @import("commands.zig");
const Client = @import("client.zig");
const encoding = @import("encoding.zig");
const constants = @import("constants.zig");
const utils = @import("utils.zig");

var gSock: *network.Socket = undefined;
var client: *Client.Client = undefined;
const stdout = std.io.getStdOut().writer();

const TARGET: [6]u8 = [_]u8{ 0x97, 0x98, 0x99, 0x100, 0x101, 0x102 };

fn onRespond(allocator: std.mem.Allocator, commandType: u16, payload: []const u8, address: [4]u8, port: u16) anyerror!void {
    const message = encoding.encode(allocator, false, 0, TARGET, false, false, 0, commandType, payload) catch |err| {
        std.debug.print("Failed to encode message: {any}\n", .{err});
        return;
    };
    const addr = network.Address.IPv4.init(address[0], address[1], address[2], address[3]);
    const endpoint: network.EndPoint = .{ .address = network.Address{ .ipv4 = addr }, .port = port };
    _ = gSock.sendTo(endpoint, message) catch |err| {
        std.debug.print("Failed to send message to {any}: {any}\n", .{ endpoint, err });
    };
}

fn onDeviceAdded(device: *devicesMod.Device) void {
    // std.debug.print("Device added: {s}\n", .{device.serialNumber});

    client.send(commands.GetLabelCommand(), device) catch |err| {
        std.debug.print("Failed to send GetLabelCommand to device {s}: {any}\n", .{ device.serialNumber, err });
    };

    client.send(commands.GetColorCommand(), device) catch |err| {
        std.debug.print("Failed to send GetColorCommand to device {s}: {any}\n", .{ device.serialNumber, err });
    };
}

pub fn main() !void {
    try network.init();
    defer network.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sock = try network.Socket.create(.ipv4, .udp);
    defer sock.close();
    try sock.setBroadcast(true);

    gSock = &sock;

    var rt = try router.Router.init(allocator, .{
        .handlers = null,
        .onSend = onSendFn,
    });
    defer rt.deinit();

    var devices = devicesMod.Devices.init(allocator, .{
        .onAdded = onDeviceAdded,
    });
    defer devices.deinit();

    const ClientMessageHandler = struct {
        devices: *devicesMod.Devices,

        pub fn onMessage(self: *const @This(), header: types.Header, payload: []const u8, serialNumber: [12]u8) void {
            _ = self;

            switch (header.type) {
                @intFromEnum(constants.CommandType.StateService) => {
                    // const serviceType: constants.ServiceType = @enumFromInt(payload[0]);
                    // std.debug.print("Client received StateService message from {s}: {s}\n", .{
                    //     serialNumber,
                    //     @tagName(serviceType),
                    // });
                },
                @intFromEnum(constants.CommandType.StateLabel) => {
                    std.debug.print("Client received StateLabel message from {s}: {s}\n", .{
                        serialNumber,
                        payload,
                    });
                },
                @intFromEnum(constants.CommandType.LightState) => {
                    // if (self.devices.get(serialNumber)) |device| {
                    //     client.send(commands.GetColorCommand(), device) catch {};
                    // }

                    var offsetRef = encoding.OffsetRef{ .current = 0 };
                    const color = encoding.decodeLightState(payload, &offsetRef) catch {
                        return;
                    };

                    const rgb = utils.hsbToRgb(color.hue, color.saturation, color.brightness);

                    const sty: ansi.style.Style = .{ .foreground = .{ .RGB = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b } } };
                    stdout.print("{s}: ", .{serialNumber}) catch {};
                    ansi.format.updateStyle(stdout, sty, null) catch {};
                    stdout.print("{s}\n", .{"███████████"}) catch {};
                    ansi.format.updateStyle(stdout, .{}, sty) catch {};

                    // std.debug.print("Client received LightState message from {s} with label '{s}': {any}\n", .{
                    //     serialNumber,
                    //     color.label,
                    //     color,
                    // });
                },
                else => {
                    std.debug.print("Client received unhandled message from {s}: {any}\n", .{
                        serialNumber,
                        header.type,
                    });
                },
            }
        }
    };

    client = try Client.Client.init(allocator, .{
        .router = &rt,
        .onMessage = types.MessageHandler.init(&ClientMessageHandler{ .devices = &devices }),
    });
    defer client.deinit();

    const discover_thread = try std.Thread.spawn(.{}, discoverDevicesThread, .{});
    const getLightStatesThread = try std.Thread.spawn(.{}, getLightStates, .{&devices});

    const read_thread = try std.Thread.spawn(.{}, socketReader, .{
        &sock,
        &rt,
        &devices,
    });
    read_thread.join();
    discover_thread.join();
    getLightStatesThread.join();
}

fn socketReader(sock: *network.Socket, rt: *router.Router, devices: *devicesMod.Devices) !void {
    var buffer: [1024]u8 = undefined;
    while (true) {
        const recv_result = try sock.receiveFrom(&buffer);
        const result = try rt.receive(buffer[0..recv_result.numberOfBytes]);
        // std.debug.print("received message type: {d}\n", .{result.header.type});
        // const serviceType: constants.CommandType = @enumFromInt(result.header.type);
        // std.debug.print("received message payload: {s}\n", .{@tagName(serviceType)});

        _ = devices.register(result.serialNumber, recv_result.sender.port, recv_result.sender.address.ipv4.value, result.header.target.*) catch {};
    }
}

fn discoverDevicesThread() !void {
    while (true) {
        try client.broadcast(commands.GetServiceCommand());
        std.time.sleep(5 * 1000 * 1000 * 1000);
    }
}

fn getLightStates(devices: *devicesMod.Devices) void {
    while (true) {
        var value_iterator = devices.knownDevices.valueIterator();
        while (value_iterator.next()) |value| {
            client.send(commands.GetColorCommand(), value.*) catch |err| {
                std.debug.print("Error sending GetColorCommand: {any}\n", .{err});
            };
        }
        std.time.sleep(1 * 1000 * 1000 * 1000);
    }
}
