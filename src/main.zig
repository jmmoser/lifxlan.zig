const std = @import("std");
const network = @import("network.zig");
// const network = @import("network");
const router = @import("router.zig");
const devicesMod = @import("devices.zig");
const commands = @import("commands.zig");
const clientMod = @import("client.zig");
const encoding = @import("encoding.zig");
const constants = @import("constants.zig");

var gSock: *network.Socket = undefined;
var client: *clientMod.Client = undefined;
var devices: devicesMod.Devices = undefined;

fn onSendFn(message: []const u8, port: u16, address: []const u8, _: ?[12]u8) anyerror!void {
    // std.debug.print("Parsing address {any}\n", .{address});
    // const addr = network.Address.IPv4.init(address[0], address[1], address[2], address[3]);
    const addr = try network.Address.IPv4.parse(address);
    const endpoint: network.EndPoint = .{ .address = network.Address{ .ipv4 = addr }, .port = port };
    _ = gSock.sendTo(endpoint, message) catch |err| {
        std.debug.print("Failed to send message to {any}: {any}\n", .{ endpoint, err });
    };
}

fn onDeviceAdded(device: *devicesMod.Device) void {
    // std.debug.print("Device added: {s}\n", .{device.serialNumber});

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

    gSock = &sock;

    var rt = try router.Router.init(allocator, .{
        .handlers = null,
        .onSend = onSendFn,
    });
    defer rt.deinit();

    devices = devicesMod.Devices.init(allocator, .{
        .onAdded = onDeviceAdded,
    });
    defer devices.deinit();

    client = try clientMod.Client.init(allocator, .{
        .router = &rt,
        .onMessage = struct {
            fn handler(header: encoding.Header, payload: []const u8, serialNumber: [12]u8) void {
                switch (header.type) {
                    @intFromEnum(constants.Type.StateService) => {
                        std.debug.print("Client received StateService message from {s} at {d}: {any}\n", .{
                            serialNumber,
                            header.source,
                            payload,
                        });
                    },
                    @intFromEnum(constants.Type.StateLabel) => {
                        std.debug.print("Client received StateLabel message from {s} at {d}: {any}\n", .{
                            serialNumber,
                            header.source,
                            payload,
                        });
                    },
                    else => {},
                }
            }
        }.handler,
    });
    defer client.deinit();

    try client.broadcast(commands.GetServiceCommand());

    var read_thread = try std.Thread.spawn(.{}, socketReader, .{
        &sock,
        &rt,
    });
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

        var addressBuffer: [15]u8 = undefined;
        const formattedAddress = std.fmt.bufPrint(&addressBuffer, "{d}.{d}.{d}.{d}", .{
            recv_result.sender.address.ipv4.value[0],
            recv_result.sender.address.ipv4.value[1],
            recv_result.sender.address.ipv4.value[2],
            recv_result.sender.address.ipv4.value[3],
        }) catch {
            continue;
        };
        _ = devices.register(result.serialNumber, recv_result.sender.port, formattedAddress, result.header.target.*) catch {};
    }
}
