const std = @import("std");
const network = @import("network.zig");
const router = @import("router.zig");
const devices = @import("devices.zig");
const commands = @import("commands.zig");
const clientMod = @import("client.zig");

var gSock: ?*network.Socket = null;

/// A free function that matches the router's onSend signature:
fn onSendFn(message: []const u8, port: u16, address: []const u8, _: ?[]const u8) void {
    _ = address;
    // fn onSendFn(message: []const u8, port: u16) void {
    const sock = gSock orelse return; // in case it's not set
    // const addr = network.Address.parse(address) catch return;
    const addr: network.EndPoint = .{ .address = network.Address{ .ipv4 = network.Address.IPv4.broadcast }, .port = port };
    _ = sock.sendTo(addr, message) catch return;
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
    var devs = devices.Devices.init(allocator, .{});
    defer devs.deinit();

    // Create client
    var client = try clientMod.Client.init(allocator, .{ .router = &rt });
    defer client.deinit();

    // Broadcast GetService command
    try client.broadcast(commands.GetServiceCommand());

    var read_thread = try std.Thread.spawn(.{}, readNetwork, .{
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

fn readNetwork(sock: *network.Socket, rt: *router.Router) !void {
    var buffer: [1024]u8 = undefined;
    while (true) {
        const recv_result = try sock.receiveFrom(&buffer);
        const result = try rt.receive(buffer[0..recv_result.numberOfBytes]);

        std.debug.print("Received message from serial number: {s}\n", .{result.serialNumber});
        std.debug.print("Header: {any}\n", .{result.header});
        std.debug.print("Payload: {any}\n", .{result.payload});
        std.debug.print("Payload length: {any}\n", .{result.payload.len});
    }
}
