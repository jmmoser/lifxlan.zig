const std = @import("std");
const types = @import("types.zig");
const encoding = @import("encoding.zig");
const utils = @import("utils.zig");

pub const MAX_SOURCE: u32 = 0xFFFFFFFF;
const MAX_SOURCE_VALUES: u32 = MAX_SOURCE - 2; // 0 and 1 are reserved

const MessageHandler = *const fn (*anyopaque, types.Header, []const u8, [12]u8) void;

pub const HandlerEntry = struct {
    context: *anyopaque,
    handler: MessageHandler,
};

fn defaultOnMessage(header: types.Header, payload: []const u8, serialNumber: [12]u8) void {
    _ = header;
    _ = payload;
    _ = serialNumber;
}

const OnSend = *const fn (message: []const u8, port: u16, address: []const u8, serialNumber: ?[12]u8) anyerror!void;
const OnMessage = *const fn (header: types.Header, payload: []const u8, serialNumber: [12]u8) void;

pub const RouterOptions = struct {
    onSend: OnSend,
    onMessage: ?OnMessage = null,
    handlers: ?std.AutoHashMap(u32, HandlerEntry),
};

pub const Router = struct {
    handlers: std.AutoHashMap(u32, HandlerEntry),
    onSend: OnSend,
    onMessage: ?OnMessage = null,
    sourceCounter: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, options: RouterOptions) !Router {
        return Router{
            .handlers = options.handlers orelse std.AutoHashMap(u32, HandlerEntry).init(allocator),
            .onSend = options.onSend,
            .onMessage = options.onMessage,
            .sourceCounter = 2,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Router) void {
        self.handlers.deinit();
    }

    pub fn nextSource(self: *Router) !u32 {
        var source: i32 = -1;
        var i: u32 = 0;
        while (i < MAX_SOURCE_VALUES) : (i += 1) {
            if (!self.handlers.contains(self.sourceCounter)) {
                source = @intCast(self.sourceCounter);
                break;
            }
            self.sourceCounter = self.sourceCounter + 1;
            if (self.sourceCounter <= 1) {
                self.sourceCounter = 2;
            }
        }
        if (source == -1) {
            return error.NoAvailableSource;
        }
        return @intCast(source);
    }

    pub fn register(self: *Router, source: u32, handler: HandlerEntry) !void {
        if (source <= 1 or source > MAX_SOURCE) {
            return error.InvalidSource;
        }
        if (self.handlers.contains(source)) {
            return error.SourceAlreadyRegistered;
        }
        try self.handlers.put(source, handler);
    }

    pub fn deregister(self: *Router, source: u32) !void {
        _ = self.handlers.remove(source);
    }

    pub fn send(self: *Router, message: []const u8, port: u16, address: []const u8, serialNumber: ?[12]u8) anyerror!void {
        // std.debug.print("Router sending message to {?s} at {s}\n", .{ serialNumber, address });
        try self.onSend(message, port, address, serialNumber);
        // std.debug.print("Router sent message to {?s} at {s}\n", .{ serialNumber, address });
    }

    pub const ReceiveResult = struct {
        header: types.Header,
        payload: []const u8,
        serialNumber: [12]u8,
    };

    pub fn receive(self: *Router, message: []const u8) !ReceiveResult {
        const header = try encoding.decodeHeader(message, 0);
        const payload = encoding.getPayload(message);
        const serialNumber = utils.convertTargetToSerialNumber(header.target);

        if (self.onMessage) |onMessage| {
            onMessage(header, payload, serialNumber);
        }

        // std.debug.print("Router received message from {s} at {d}: {any}\n", .{ serialNumber, header.source, payload });

        if (self.handlers.get(header.source)) |handler| {
            handler.handler(handler.context, header, payload, serialNumber);
        } else {
            std.debug.print("Router received message from {s} at {d} but no handler found\n", .{ serialNumber, header.source });
        }

        return ReceiveResult{
            .header = header,
            .payload = payload,
            .serialNumber = serialNumber,
        };
    }
};
