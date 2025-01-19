const std = @import("std");
const types = @import("types.zig");
const constants = @import("constants.zig");
const encoding = @import("encoding.zig");
const router = @import("router.zig");
const devices = @import("devices.zig");
const commands = @import("commands.zig");

// fn getResponseKey(serialNumber: [12]u8, sequence: u8) ![64]u8 {
//     var key: [64]u8 = undefined;
//     const result = try std.fmt.bufPrint(&key, "{s}:{d}", .{ serialNumber, sequence });
//     @memcpy(key[0..result.len], result);
//     return key;
//     // var key: [64]u8 = undefined;
//     // return std.fmt.bufPrint(&key, "{s}:{d}", .{ serialNumber, sequence }) catch |err| {
//     //     return err;
//     // };
// }

const ResponseKey = [15]u8;

fn getResponseKey(serialNumber: [12]u8, sequence: u8) !ResponseKey {
    var key: ResponseKey = undefined;
    _ = try std.fmt.bufPrint(&key, "{s}{d}", .{ serialNumber, sequence });
    return key;
}

test "get response key" {
    const key = try getResponseKey(constants.NO_SERIAL_NUMBER, 255);
    try std.testing.expect(std.mem.eql(u8, &key, "000000000000255"));
}

fn incrementSequence(sequence: ?u8) u8 {
    if (sequence) |seq| {
        return (seq + 1) % 0xFF;
    }
    return 0;
}

pub const ResponseHandler = struct {
    handler: *const fn (context: *anyopaque, typ: u16, bytes: []const u8, offsetRef: *encoding.OffsetRef) void,
    context: *anyopaque,
    // timer: ?std.time.Timer = null,
};

pub const ClientOptions = struct {
    router: *router.Router,
    defaultTimeoutMs: ?u32 = 3000,
    source: ?u32 = null,
    // onMessage: ?*const fn (header: types.Header, payload: []const u8, serialNumber: [12]u8) void = null,
    onMessage: ?types.MessageHandler = null,
};

pub const Client = struct {
    router: *router.Router,
    source: u32,
    defaultTimeoutMs: u32,
    responseHandlers: std.AutoHashMap(ResponseKey, ResponseHandler),
    disposed: bool,
    allocator: std.mem.Allocator,
    // onMessage: ?*const fn (header: types.Header, payload: []const u8, serialNumber: [12]u8) void,
    onMessage: ?types.MessageHandler,

    pub fn init(allocator: std.mem.Allocator, options: ClientOptions) !*Client {
        const source = options.source orelse try options.router.nextSource();
        const defaultTimeoutMs = options.defaultTimeoutMs orelse 3000;

        const client = try allocator.create(Client);
        client.* = .{
            .router = options.router,
            .source = source,
            .defaultTimeoutMs = defaultTimeoutMs,
            .responseHandlers = std.AutoHashMap(ResponseKey, ResponseHandler).init(allocator),
            .disposed = false,
            .allocator = allocator,
            .onMessage = options.onMessage,
        };

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
            self.allocator,
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

        try self.router.send(bytes, constants.PORT, constants.BROADCAST, null);
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

    pub fn send(self: *Client, command: commands.Command, device: *devices.Device) !void {
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

        // const key = try getResponseKey(device.serialNumber, device.sequence);
        // try self.registerResponseHandler(key, command.decode);

        device.sequence = incrementSequence(device.sequence);
        try self.router.send(bytes, device.port, device.address, device.serialNumber);
    }

    fn onMessage(context: *anyopaque, header: types.Header, payload: []const u8, serialNumber: [12]u8) void {
        const self: *Client = @ptrCast(@alignCast(context));
        if (self.onMessage) |onMessageFn| {
            onMessageFn.onMessage(header, payload, serialNumber);
        }
        const key = getResponseKey(serialNumber, header.sequence) catch return;
        if (self.responseHandlers.get(key)) |handler| {
            var offsetRef = encoding.OffsetRef{ .current = 0 };
            // const decoded = handler.
            handler.handler(handler.context, header.type, payload, &offsetRef);
            _ = self.responseHandlers.remove(key);
        }
    }

    fn registerAckHandler(self: *Client, key: [64]u8) !void {
        if (self.responseHandlers.contains(key)) {
            return error.HandlerConflict;
        }

        const handler = ResponseHandler{
            .handler = struct {
                fn handle(typ: u16, _: []const u8, _: *encoding.OffsetRef) void {
                    if (typ == @intFromEnum(constants.CommandType.Acknowledgement)) {
                        // TODO: Handle acknowledgement
                    }
                }
            }.handle,
        };

        try self.responseHandlers.put(key, handler);
    }

    fn registerResponseHandler(
        self: *Client,
        key: ResponseKey,
        decode: *const fn ([]const u8, *encoding.OffsetRef) anyerror!void,
    ) !void {
        if (self.responseHandlers.contains(key)) {
            return error.HandlerConflict;
        }

        const handler = ResponseHandler{
            .context = @constCast(@ptrCast(decode)),
            .handler = struct {
                fn handle(resCtx: *anyopaque, responseType: u16, bytes: []const u8, offsetRef: *encoding.OffsetRef) void {
                    const decodeFn: commands.Decode = @ptrCast(@alignCast(resCtx));
                    if (responseType == @intFromEnum(constants.CommandType.StateUnhandled)) {
                        const requestType = encoding.decodeStateUnhandled(bytes, offsetRef) catch return;
                        // Handle unhandled request
                        std.debug.print("Unhandled request: {}\n", .{requestType});
                        std.debug.assert(false);
                    }
                    _ = decodeFn(bytes, offsetRef) catch return; // Access decode via context
                }
            }.handle,
        };

        try self.responseHandlers.put(key, handler);
    }
};
