const std = @import("std");
const constants = @import("constants.zig");
const utils = @import("utils.zig");

pub const Device = struct {
    address: []const u8,
    port: u16,
    target: [6]u8,
    serialNumber: [12]u8,
    sequence: u8,

    pub fn init(allocator: std.mem.Allocator, config: struct {
        address: []const u8,
        serialNumber: ?[12]u8 = null,
        port: ?u16 = null,
        target: ?[6]u8 = null,
        sequence: ?u8 = null,
    }) !Device {
        // TODO: I don't think this is needed
        const addr = try allocator.dupe(u8, config.address);
        const port = config.port orelse constants.PORT;

        var target: [6]u8 = undefined;
        if (config.target) |t| {
            target = t;
        } else if (config.serialNumber) |sn| {
            target = try utils.convertSerialNumberToTarget(sn);
        } else {
            target = constants.NO_TARGET;
        }

        return Device{
            .address = addr,
            .port = port,
            .target = target,
            .serialNumber = config.serialNumber orelse constants.NO_SERIAL_NUMBER,
            .sequence = config.sequence orelse 0,
        };
    }

    pub fn deinit(self: *Device, allocator: std.mem.Allocator) void {
        // TODO: I don't think this is needed
        allocator.free(self.address);
    }
};

pub const DeviceCallback = *const fn (device: *Device) void;

pub const DevicesOptions = struct {
    onAdded: ?DeviceCallback = null,
    onChanged: ?DeviceCallback = null,
    onRemoved: ?DeviceCallback = null,
    defaultTimeoutMs: u32 = 3000,
};

pub const Devices = struct {
    allocator: std.mem.Allocator,
    knownDevices: std.StringHashMap(Device),
    deviceResolvers: std.StringHashMap(std.ArrayList(DeviceCallback)),
    options: DevicesOptions,

    pub fn init(allocator: std.mem.Allocator, options: DevicesOptions) Devices {
        return .{
            .allocator = allocator,
            .knownDevices = std.StringHashMap(Device).init(allocator),
            .deviceResolvers = std.StringHashMap(std.ArrayList(DeviceCallback)).init(allocator),
            .options = options,
        };
    }

    pub fn deinit(self: *Devices) void {
        var it = self.knownDevices.iterator();
        while (it.next()) |entry| {
            var device = entry.value_ptr;
            device.deinit(self.allocator);
        }
        self.knownDevices.deinit();

        var resolvers_it = self.deviceResolvers.iterator();
        while (resolvers_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.deviceResolvers.deinit();
    }

    pub fn register(self: *Devices, serialNumber: [12]u8, port: u16, address: []const u8, target: [6]u8) !Device {
        const serialNumberSlice: []const u8 = serialNumber[0..];

        if (self.knownDevices.getPtr(serialNumberSlice)) |existing| {
            if (port != existing.port or !std.mem.eql(u8, address, existing.address)) {
                existing.port = port;
                existing.address = try self.allocator.dupe(u8, address);
                if (self.options.onChanged) |callback| {
                    callback(existing);
                }
            }
            return existing.*;
        }

        var device = try Device.init(self.allocator, .{
            .serialNumber = serialNumber,
            .port = port,
            .address = address,
            .target = target,
        });

        try self.knownDevices.put(serialNumberSlice, device);

        if (self.options.onAdded) |callback| {
            callback(&device);
        }

        if (self.deviceResolvers.get(&serialNumber)) |resolvers| {
            for (resolvers.items) |resolver| {
                resolver(&device);
            }
            _ = self.deviceResolvers.remove(&serialNumber);
        }

        return device;
    }

    pub fn remove(self: *Devices, serialNumber: [12]u8) bool {
        if (self.knownDevices.fetchRemove(serialNumber)) |kv| {
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

    pub const GetDeviceResult = struct {
        device: Device,
        frame: @Frame(getDeviceAsync),
    };

    pub fn getDevice(self: *Devices, serialNumber: [12]u8, timeout_ms: ?u32) !GetDeviceResult {
        if (self.knownDevices.get(serialNumber)) |device| {
            return GetDeviceResult{
                .device = device,
                .frame = undefined,
            };
        }

        var frame = async self.getDeviceAsync(serialNumber);
        const timeout = timeout_ms orelse self.options.defaultTimeoutMs;

        if (timeout > 0) {
            const timer = try std.time.Timer.start();
            while (timer.read() < timeout * std.time.ns_per_ms) {
                if (self.knownDevices.get(serialNumber)) |device| {
                    return GetDeviceResult{
                        .device = device,
                        .frame = frame,
                    };
                }
                std.time.sleep(1 * std.time.ns_per_ms);
            }
            return error.Timeout;
        }

        return GetDeviceResult{
            .device = await frame,
            .frame = frame,
        };
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
};
