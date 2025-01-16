const std = @import("std");
const network = @import("network.zig");
// const network = @import("network");
const router = @import("router.zig");
const devicesMod = @import("devices.zig");
const commands = @import("commands.zig");
const clientMod = @import("client.zig");

var gSock: *network.Socket = undefined;
var client: *clientMod.Client = undefined;
var devices: devicesMod.Devices = undefined;

// fn onSendFn(message: []const u8, port: u16, address: []const u8, _: ?[12]u8) void {
//     _ = address;
//     const addr: network.EndPoint = .{ .address = network.Address{ .ipv4 = network.Address.IPv4.broadcast }, .port = port };
//     _ = gSock.sendTo(addr, message) catch return;
// }
fn onSendFn(message: []const u8, port: u16, address: []const u8, _: ?[12]u8) anyerror!void {
    const addr = try network.Address.IPv4.parse(address);
    const endpoint: network.EndPoint = .{ .address = network.Address{ .ipv4 = addr }, .port = port };
    _ = gSock.sendTo(endpoint, message) catch return;
}

fn onDeviceAdded(device: *devicesMod.Device) void {
    std.debug.print("Device added: {s}\n", .{device.serialNumber});

    client.send(commands.GetLabelCommand(), device) catch |err| {
        std.debug.print("Failed to send GetLabelCommand to device: {s}\n", .{device.serialNumber});
        std.debug.print("Error: {any}\n", .{err});
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

    // Store the pointer globally (not always ideal, but simple for an example).
    gSock = &sock;

    var rt = try router.Router.init(allocator, .{
        .handlers = null,
        .onSend = onSendFn,
    });
    defer rt.deinit();

    // Create devices manager
    devices = devicesMod.Devices.init(allocator, .{
        .onAdded = onDeviceAdded,
    });
    defer devices.deinit();

    // Create client
    client = try clientMod.Client.init(allocator, .{ .router = &rt });
    defer client.deinit();

    // Broadcast GetService command
    try client.broadcast(commands.GetServiceCommand());

    var read_thread = try std.Thread.spawn(.{}, socketReader, .{
        &sock,
        &rt,
    });
    // read_thread.detach();
    read_thread.join();
}

const ReadContext = struct {
    sock: *network.Socket,
    router: *router.Router,
};

fn socketReader(sock: *network.Socket, rt: *router.Router) !void {
    var buffer: [1024]u8 = undefined;
    while (true) {
        const recv_result = try sock.receiveFrom(&buffer);
        const result = try rt.receive(buffer[0..recv_result.numberOfBytes]);
        _ = devices.register(result.serialNumber, recv_result.sender.port, &recv_result.sender.address.ipv4.value, result.header.target.*) catch {};

        std.debug.print("Received message from serial number: {s}: {any}\n", .{ result.serialNumber, result.payload });
        // std.debug.print("Header: {any}\n", .{result.header});
        // std.debug.print("Payload: {any}\n", .{result.payload});
        // std.debug.print("Payload length: {any}\n", .{result.payload.len});
    }
}
