const std = @import("std");
const Device = @import("device.zig");
const Devices = @This();

pub const DeviceCallback = *const fn (device: *Device) void;

pub const DevicesOptions = struct {
    onAdded: ?DeviceCallback = null,
    onChanged: ?DeviceCallback = null,
    onRemoved: ?DeviceCallback = null,
    defaultTimeoutMs: u32 = 3000,
};

allocator: std.mem.Allocator,
knownDevices: std.StringHashMap(*Device),
deviceResolvers: std.StringHashMap(std.ArrayList(DeviceCallback)),
options: DevicesOptions,

pub fn init(allocator: std.mem.Allocator, options: DevicesOptions) Devices {
    return .{
        .allocator = allocator,
        .knownDevices = std.StringHashMap(*Device).init(allocator),
        .deviceResolvers = std.StringHashMap(std.ArrayList(DeviceCallback)).init(allocator),
        .options = options,
    };
}

pub fn deinit(self: *Devices) void {
    var it = self.knownDevices.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit(self.allocator);
    }
    self.knownDevices.deinit();

    var resolvers_it = self.deviceResolvers.iterator();
    while (resolvers_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    self.deviceResolvers.deinit();
    self.* = undefined;
}

pub fn register(self: *Devices, serialNumber: [12]u8, port: u16, address: [4]u8, target: [6]u8) !*Device {
    const serialNumberSlice: []const u8 = serialNumber[0..];

    if (self.knownDevices.get(serialNumberSlice)) |existing| {
        if (port != existing.port or !std.mem.eql(u8, &address, &existing.address)) {
            existing.port = port;
            existing.address = address;
            if (self.options.onChanged) |callback| {
                callback(existing);
            }
        }
        return existing;
    }

    const device = try Device.init(self.allocator, .{
        .serialNumber = serialNumber,
        .port = port,
        .address = address,
        .target = target,
    });

    try self.knownDevices.put(device.serialNumber[0..], device);

    if (self.options.onAdded) |callback| {
        callback(device);
    }

    if (self.deviceResolvers.get(&serialNumber)) |resolvers| {
        for (resolvers.items) |resolver| {
            resolver(device);
        }
        _ = self.deviceResolvers.remove(&serialNumber);
    }

    return device;
}

pub fn remove(self: *Devices, serialNumber: [12]u8) bool {
    const serialNumberSlice: []const u8 = serialNumber[0..];

    if (self.knownDevices.fetchRemove(serialNumberSlice)) |kv| {
        if (self.options.onRemoved) |callback| {
            callback(kv.value);
        }
        var device = kv.value;
        device.deinit(self.allocator);
        return true;
    }
    return false;
}

const GetDeviceError = error{
    DeviceNotFound,
    Timeout,
    Aborted,
};

pub fn get(self: *Devices, serialNumber: [12]u8) ?*Device { //, timeout_ms: ?u32*/) !?*Device {
    const serialNumberSlice: []const u8 = serialNumber[0..];

    if (self.knownDevices.get(serialNumberSlice)) |device| {
        return device;
    }

    return null;

    // const timeout = timeout_ms orelse self.options.defaultTimeoutMs;

    // if (timeout > 0) {
    //     const timer = try std.time.Timer.start();
    //     while (timer.read() < timeout * std.time.ns_per_ms) {
    //         if (self.knownDevices.get(serialNumberSlice)) |device| {
    //             return device;
    //         }
    //         std.time.sleep(1 * std.time.ns_per_ms);
    //     }
    //     return error.Timeout;
    // }

    // return null;
}

fn getDeviceAsync(self: *Devices, serialNumber: [12]u8) !Device {
    var resolvers = if (self.deviceResolvers.get(serialNumber)) |existing|
        existing
    else blk: {
        const new_list = std.ArrayList(DeviceCallback).init(self.allocator);
        try self.deviceResolvers.put(serialNumber, new_list);
        break :blk new_list;
    };

    const promise = try std.event.Promise(Device).create();
    try resolvers.append(promise.resolve);

    return promise.wait();
}
