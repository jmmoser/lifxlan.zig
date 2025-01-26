const std = @import("std");
const constants = @import("constants.zig");
const utils = @import("utils.zig");

pub const Device = @This();

address: [4]u8,
port: u16,
target: [6]u8,
serialNumber: [12]u8,
sequence: u8,

pub fn init(allocator: std.mem.Allocator, config: struct {
    address: [4]u8,
    serialNumber: ?[12]u8 = null,
    port: ?u16 = null,
    target: ?[6]u8 = null,
    sequence: ?u8 = null,
}) !*Device {
    const port = config.port orelse constants.PORT;

    var target: [6]u8 = undefined;
    if (config.target) |t| {
        target = t;
    } else if (config.serialNumber) |sn| {
        target = utils.convertSerialNumberToTarget(sn);
    } else {
        target = constants.NO_TARGET;
    }

    const device = try allocator.create(Device);
    errdefer allocator.destroy(device);

    device.* = .{
        .address = config.address,
        .port = port,
        .target = target,
        .serialNumber = config.serialNumber orelse constants.NO_SERIAL_NUMBER,
        .sequence = config.sequence orelse 0,
    };

    return device;
}

pub fn deinit(self: *Device, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}
