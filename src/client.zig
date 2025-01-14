const std = @import("std");
const constants = @import("constants.zig");
const encoding = @import("encoding.zig");
const router = @import("router.zig");
const devices = @import("devices.zig");
const commands = @import("commands.zig");

// fn getResponseKey(serialNumber: []const u8, sequence: u8) ![64]u8 {
//     var key: [64]u8 = undefined;
//     const result = try std.fmt.bufPrint(&key, "{s}:{d}", .{ serialNumber, sequence });
//     @memcpy(key[0..result.len], result);
//     return key;
//     // var key: [64]u8 = undefined;
//     // return std.fmt.bufPrint(&key, "{s}:{d}", .{ serialNumber, sequence }) catch |err| {
//     //     return err;
//     // };
// }
fn getResponseKey(serialNumber: [12]u8, sequence: u8) ![64]u8 {
    var key: [64]u8 = undefined;
    std.debug.print("Serial number: {s}\n", .{serialNumber});
    _ = try std.fmt.bufPrint(&key, "{s}:{d}", .{ serialNumber, sequence });
    return key;
}

fn incrementSequence(sequence: ?u8) u8 {
    if (sequence) |seq| {
        return (seq + 1) % 0xFF;
    }
    return 0;
}

pub const ResponseHandler = struct {
    handler: *const fn (typ: u16, bytes: []const u8, offsetRef: *encoding.OffsetRef) void,
    timer: ?std.time.Timer = null,
};

pub const ClientOptions = struct {
    router: *router.Router,
    defaultTimeoutMs: ?u32 = 3000,
    source: ?u32 = null,
};

pub const Client = struct {
    router: *router.Router,
    source: u32,
    defaultTimeoutMs: u32,
    responseHandlers: std.AutoHashMap([64]u8, ResponseHandler),
    disposed: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, options: ClientOptions) !*Client {
        const source = options.source orelse try options.router.nextSource();
        const defaultTimeoutMs = options.defaultTimeoutMs orelse 3000;

        const client = try allocator.create(Client);
        client.* = .{
            .router = options.router,
            .source = source,
            .defaultTimeoutMs = defaultTimeoutMs,
            .responseHandlers = std.AutoHashMap([64]u8, ResponseHandler).init(allocator),
            .disposed = false,
            .allocator = allocator,
        };

        // try options.router.register(source, .{
        //     .onMessage = onMessage,
        //     .context = client,
        // });
        try options.router.register(source, .{
            .handler = onMessage,
            .context = client,
        });

        return client;
    }

    pub fn deinit(self: *Client) void {
        if (!self.disposed) {
            self.disposed = true;
            self.router.deregister(self.source) catch {};
        }
        self.responseHandlers.deinit();
        self.allocator.destroy(self);
    }

    pub fn broadcast(self: *Client, command: commands.Command) !void {
        const bytes = try encoding.encode(
            &self.allocator,
            true,
            self.source,
            &constants.NO_TARGET,
            false,
            false,
            0xFF,
            command.type,
            command.payload,
        );
        defer self.allocator.free(bytes);

        self.router.send(bytes, constants.PORT, constants.BROADCAST, null);
    }

    pub fn unicast(self: *Client, command: commands.Command, device: devices.Device) !void {
        const bytes = try encoding.encode(
            self.allocator,
            false,
            self.source,
            &device.target,
            false,
            false,
            device.sequence,
            command.type,
            command.payload,
        );
        defer self.allocator.free(bytes);

        self.router.send(bytes, device.port, device.address, device.serialNumber);
        device.sequence = incrementSequence(device.sequence);
    }

    pub fn sendOnlyAcknowledgement(self: *Client, command: commands.Command, device: devices.Device) !void {
        const bytes = try encoding.encode(
            self.allocator,
            false,
            self.source,
            &device.target,
            false,
            true,
            device.sequence,
            command.type,
            command.payload,
        );
        defer self.allocator.free(bytes);

        const key = try getResponseKey(device.serialNumber, device.sequence);
        try self.registerAckHandler(key);

        device.sequence = incrementSequence(device.sequence);
        self.router.send(bytes, device.port, device.address, device.serialNumber);
    }

    pub fn send(self: *Client, command: commands.Command, device: devices.Device) !void {
        const bytes = try encoding.encode(
            self.allocator,
            false,
            self.source,
            &device.target,
            true,
            false,
            device.sequence,
            command.type,
            command.payload,
        );
        defer self.allocator.free(bytes);

        const key = try getResponseKey(device.serialNumber, device.sequence);
        try self.registerResponseHandler(key, command.decode);

        device.sequence = incrementSequence(device.sequence);
        self.router.send(bytes, device.port, device.address, device.serialNumber);
    }

    // fn onMessage(context: ?*anyopaque, header: encoding.Header, payload: []const u8, serialNumber: []const u8) void {
    //     // const self = @ptrCast(*Client, @alignCast(@alignOf(Client), context.?));
    //     const self: *Client = @alignCast(@ptrCast(context.?));
    //     const key = getResponseKey(serialNumber, header.sequence) catch return;
    //     if (self.responseHandlers.get(key)) |handler| {
    //         var offsetRef = encoding.OffsetRef{ .current = 0 };
    //         handler.handler(header.type, payload, &offsetRef);
    //         _ = self.responseHandlers.remove(key);
    //     }
    // }

    fn onMessage(context: *anyopaque, header: encoding.Header, payload: []const u8, serialNumber: [12]u8) void {
        // fn onMessage(context: *anyopaque, header: encoding.Header, payload: []const u8, serialNumber: []const u8) void {
        // const self: *Client = @alignCast(@ptrCast(context.?));
        const self: *Client = @ptrCast(@alignCast(context));
        const key = getResponseKey(serialNumber, header.sequence) catch return;
        if (self.responseHandlers.get(key)) |handler| {
            var offsetRef = encoding.OffsetRef{ .current = 0 };
            handler.handler(header.type, payload, &offsetRef);
            _ = self.responseHandlers.remove(key);
        }
    }

    // fn onMessage(self: *Client, header: encoding.Header, payload: []const u8, serialNumber: []const u8) void {
    //     const key = getResponseKey(serialNumber, header.sequence) catch return;
    //     if (self.responseHandlers.get(key)) |handler| {
    //         var offsetRef = encoding.OffsetRef{ .current = 0 };
    //         handler.handler(header.type, payload, &offsetRef);
    //         _ = self.responseHandlers.remove(key);
    //     }
    // }

    fn registerAckHandler(self: *Client, key: [64]u8) !void {
        if (self.responseHandlers.contains(key)) {
            return error.HandlerConflict;
        }

        const handler = ResponseHandler{
            .handler = struct {
                fn handle(typ: constants.Type, _: []const u8, _: *encoding.OffsetRef) void {
                    if (typ == .Acknowledgement) {
                        // Handle acknowledgement
                    }
                }
            }.handle,
        };

        try self.responseHandlers.put(key, handler);
    }

    fn registerResponseHandler(
        self: *Client,
        key: [64]u8,
        decode: *const fn ([]const u8, *encoding.OffsetRef) anyerror!void,
    ) !void {
        if (self.responseHandlers.contains(key)) {
            return error.HandlerConflict;
        }

        const handler = ResponseHandler{
            .handler = struct {
                fn handle(typ: constants.Type, bytes: []const u8, offsetRef: *encoding.OffsetRef) void {
                    if (typ == .StateUnhandled) {
                        const requestType = encoding.decodeStateUnhandled(bytes, offsetRef) catch return;
                        // Handle unhandled request
                        std.debug.print("Unhandled request: {}\n", .{requestType});
                        std.debug.assert(false);
                    }
                    _ = decode(bytes, offsetRef) catch return;
                }
            }.handle,
        };

        try self.responseHandlers.put(key, handler);
    }
};
