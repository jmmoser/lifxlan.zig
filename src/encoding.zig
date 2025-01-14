/// A Zig translation of the provided JavaScript code for encoding/decoding
/// LIFX protocol messages. This is a single self-contained file; you can
/// copy/paste it into a new .zig file and build it. Everything is here,
/// with the same structure and functionality as the original JS, but
/// implemented in an idiomatic Zig style.
///
/// This translation provides functions that allocate and return new byte
/// buffers (similar to `new Uint8Array(...)` in JS). Because Zig does not
/// have a global default allocator for "just works" usage, we provide
/// overloads that accept an allocator parameter. You can call these
/// functions with e.g. `std.heap.page_allocator` or any other allocator.
///
/// If you prefer stack-allocated buffers (for small messages), you can
/// adapt the code to write into a caller-supplied buffer. But for direct
/// 1:1 translation from JS's "new Uint8Array", an allocator is used here.
const std = @import("std");

////////////////////////////////////////////////////////////////////////////////
// Little-Endian Helpers
////////////////////////////////////////////////////////////////////////////////

fn writeUint8(bytes: []u8, offset: usize, value: u8) void {
    bytes[offset] = value;
}

fn readUint8(bytes: []const u8, offset: usize) u8 {
    // return std.mem.readInt(u8, bytes[offset .. offset + 1], .little);
    return bytes[offset];
}

fn writeUint16LE(bytes: []u8, offset: usize, value: u16) void {
    bytes[offset] = @as(u8, @truncate(value));
    bytes[offset + 1] = @as(u8, @truncate(value >> 8));
}

fn readUint16LE(bytes: []const u8, offset: usize) u16 {
    // const ptr: *[2]u8 = @constCast(@ptrCast(bytes[offset .. offset + 2]));
    // return std.mem.readInt(u16, ptr, .little);

    return @as(u16, bytes[offset]) | (@as(u16, bytes[offset + 1]) << 8);
}

fn writeUint32LE(bytes: []u8, offset: usize, value: u32) void {
    // const ptr: *[4]u8 = @ptrCast(bytes[offset .. offset + 4]);
    // std.mem.writeInt(u32, ptr, value, .little);

    // std.mem.writeInt(u32, bytes[offset .. offset + 4], value, .little);

    bytes[offset + 0] = @as(u8, @truncate(value >> 0));
    bytes[offset + 1] = @as(u8, @truncate(value >> 8));
    bytes[offset + 2] = @as(u8, @truncate(value >> 16));
    bytes[offset + 3] = @as(u8, @truncate(value >> 24));
}

fn readUint32LE(bytes: []const u8, offset: usize) u32 {
    return (@as(u32, bytes[offset + 0]) << 0) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn writeBigUint64LE(bytes: []u8, offset: usize, value: u64) void {
    // lower 8 bytes in little-endian
    bytes[offset + 0] = @as(u8, (value >> 0) & 0xff);
    bytes[offset + 1] = @as(u8, (value >> 8) & 0xff);
    bytes[offset + 2] = @as(u8, (value >> 16) & 0xff);
    bytes[offset + 3] = @as(u8, (value >> 24) & 0xff);
    bytes[offset + 4] = @as(u8, (value >> 32) & 0xff);
    bytes[offset + 5] = @as(u8, (value >> 40) & 0xff);
    bytes[offset + 6] = @as(u8, (value >> 48) & 0xff);
    bytes[offset + 7] = @as(u8, (value >> 56) & 0xff);
}

fn readBigUint64LE(bytes: []const u8, offset: usize) u64 {
    return (@as(u64, bytes[offset + 0]) << 0) |
        (@as(u64, bytes[offset + 1]) << 8) |
        (@as(u64, bytes[offset + 2]) << 16) |
        (@as(u64, bytes[offset + 3]) << 24) |
        (@as(u64, bytes[offset + 4]) << 32) |
        (@as(u64, bytes[offset + 5]) << 40) |
        (@as(u64, bytes[offset + 6]) << 48) |
        (@as(u64, bytes[offset + 7]) << 56);
}

fn writeFloat32LE(bytes: []u8, offset: usize, value: f32) void {
    const bits: u32 = @bitCast(value);
    writeUint32LE(bytes, offset, bits);
}

fn readFloat32LE(bytes: []const u8, offset: usize) f32 {
    const bits = readUint32LE(bytes, offset);
    return @bitCast(bits);
}

////////////////////////////////////////////////////////////////////////////////
// Shared Helpers (OffsetRef, etc.)
////////////////////////////////////////////////////////////////////////////////

pub const OffsetRef = struct {
    current: usize,
};

fn decodeBytes(bytes: []const u8, offsetRef: *OffsetRef, byteLength: usize) []const u8 {
    const start = offsetRef.current;
    const end = start + byteLength;
    const sub = bytes[start..end];
    offsetRef.current = end;
    return sub;
}

fn decodeString(bytes: []const u8, offsetRef: *OffsetRef, maxLength: usize) ![]const u8 {
    // Look for a 0 terminator or use entire block
    const slice = bytes[offsetRef.current .. offsetRef.current + maxLength];
    var foundIndex: usize = slice.len;
    for (slice, 0..) |b, i| {
        if (b == 0) {
            foundIndex = i;
            break;
        }
    }
    offsetRef.current += maxLength;
    return slice[0..foundIndex];
}

fn decodeUuid(bytes: []const u8, offsetRef: *OffsetRef) []const u8 {
    return decodeBytes(bytes, offsetRef, 16);
}

fn decodeTimestamp(bytes: []const u8, offsetRef: *OffsetRef) std.time.Time {
    // const raw = readBigUint64LE(bytes, offsetRef.current);
    const timestamp = std.mem.readInt(u64, bytes, std.builtin.Endian.little);
    offsetRef.current += 8;
    return timestamp;
    // return std.time.Time.fromZigTimestamp(raw);
}

////////////////////////////////////////////////////////////////////////////////
// Encode Functions
////////////////////////////////////////////////////////////////////////////////

fn encodeStringTo(bytes: []u8, offset: usize, value: []const u8, byteLength: usize) void {
    const count = @min(value.len, byteLength);
    @memcpy(bytes[offset .. offset + count], value[0..count]);
    // If there's space left, put a 0 terminator at next position
    if (count < byteLength) {
        bytes[offset + count] = 0;
    }
}

pub fn encodeString(allocator: *std.mem.Allocator, value: []const u8, byteLength: usize) ![]u8 {
    const buf = try allocator.alloc(u8, byteLength);
    @memset(buf, 0);
    encodeStringTo(buf, 0, value, byteLength);
    return buf;
}

pub fn encodeUuidTo(bytes: []u8, offset: usize, uuid: []const u8) !void {
    // remove dashes from the UUID string and parse 16 bytes of hex
    var hexBuf = try std.heap.page_allocator.alloc(u8, uuid.len);
    defer std.heap.page_allocator.free(hexBuf);

    // copy minus dashes
    var hexIdx: usize = 0;
    for (uuid) |c| {
        if (c == '-')
            continue;
        hexBuf[hexIdx] = c;
        hexIdx += 1;
    }

    // parse two hex chars at a time
    var j: usize = 0;
    var i: usize = 0;
    while (i < hexIdx) : (i += 2) {
        const h1 = try std.fmt.charToDigit(hexBuf[i], 16);
        const h2 = try std.fmt.charToDigit(hexBuf[i + 1], 16);
        const byteVal = (h1 << 4) + h2;
        bytes[offset + j] = @as(u8, @intCast(byteVal));
        j += 1;
    }
}

pub fn encodeTimestampTo(bytes: []u8, offset: usize, date: std.time.Time) void {
    writeBigUint64LE(bytes, offset, date.nanoseconds());
}

pub fn encode(
    allocator: *std.mem.Allocator,
    tagged: bool,
    source: u32,
    target: []const u8,
    resRequired: bool,
    ackRequired: bool,
    sequence: u8,
    msgType: u16,
    payload: ?[]const u8,
) ![]u8 {
    const protocol = 1024; // 0x400
    const addressable = 1;
    const origin: u16 = 0;

    const payloadLen = if (payload) |pl| pl.len else 0;

    const size = 36 + payloadLen;
    if (target.len != 6 and target.len != 14) {
        return error.Invalid;
    }

    var buf = try allocator.alloc(u8, size);
    @memset(buf, 0);

    // Frame Header
    writeUint16LE(buf, 0, @as(u16, @intCast(size)));

    // Protocol or-ed with flags
    const flags = (@as(u16, protocol) & 0x0FFF) |
        ((@as(u16, @intFromBool(addressable == 1)) & 0x01) << 12) |
        ((@as(u16, @intFromBool(tagged)) & 0x01) << 13) |
        ((@as(u16, origin) & 0x03) << 14);
    writeUint16LE(buf, 2, flags);

    writeUint32LE(buf, 4, source);

    // Frame Address
    if (target.len == 6) {
        @memcpy(buf[8 .. 8 + 6], target[0..6]);
        // Leave the rest as zeros (already done by @memset above)
    } else {
        // Copy all 14 bytes if provided
        @memcpy(buf[8 .. 8 + 14], target[0..14]);
    }

    // byte 22 => ackRequired, resRequired in bits 0 and 1
    var responseByte: u8 = 0;
    if (resRequired) responseByte |= 1 << 0;
    if (ackRequired) responseByte |= 1 << 1;
    writeUint8(buf, 22, responseByte);

    writeUint8(buf, 23, sequence);

    // Protocol Header
    writeUint16LE(buf, 32, msgType);

    // if payload is provided, copy it
    if (payload) |pl| {
        @memcpy(buf[36 .. 36 + pl.len], pl);
    }

    return buf;
}

////////////////////////////////////////////////////////////////////////////////
// decode State variants
////////////////////////////////////////////////////////////////////////////////

pub fn decodeStateService(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    service: u8,
    port: u32,
} {
    if (offsetRef.current + 5 > bytes.len) return error.OutOfBounds;
    const service = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;
    const port = readUint32LE(bytes, offsetRef.current);
    offsetRef.current += 4;
    return .{ .service = service, .port = port };
}

pub fn decodeStateHostFirmware(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    build: std.time.Time,
    reserved: []const u8,
    version_minor: u16,
    version_major: u16,
} {
    const build = decodeTimestamp(bytes, offsetRef);
    const reserved = decodeBytes(bytes, offsetRef, 8);
    if (offsetRef.current + 4 > bytes.len) return error.OutOfBounds;
    const version_minor = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const version_major = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    return .{
        .build = build,
        .reserved = reserved,
        .version_minor = version_minor,
        .version_major = version_major,
    };
}

pub fn decodeStateWifiInfo(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    signal: f32,
    reserved6: []const u8,
    reserved7: []const u8,
    reserved8: []const u8,
} {
    if (offsetRef.current + 4 > bytes.len) return error.OutOfBounds;
    const signal = readFloat32LE(bytes, offsetRef.current);
    offsetRef.current += 4;
    const reserved6 = decodeBytes(bytes, offsetRef, 4);
    const reserved7 = decodeBytes(bytes, offsetRef, 4);
    const reserved8 = decodeBytes(bytes, offsetRef, 2);
    return .{
        .signal = signal,
        .reserved6 = reserved6,
        .reserved7 = reserved7,
        .reserved8 = reserved8,
    };
}

pub fn decodeStateWifiFirmware(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    build: std.time.Time,
    reserved6: []const u8,
    version_minor: u16,
    version_major: u16,
} {
    const build = decodeTimestamp(bytes, offsetRef);
    const reserved6 = decodeBytes(bytes, offsetRef, 8);
    if (offsetRef.current + 4 > bytes.len) return error.OutOfBounds;
    const version_minor = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const version_major = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    return .{
        .build = build,
        .reserved6 = reserved6,
        .version_minor = version_minor,
        .version_major = version_major,
    };
}

pub fn decodeStatePower(bytes: []const u8, offsetRef: *OffsetRef) !u16 {
    if (offsetRef.current + 2 > bytes.len) return error.OutOfBounds;
    const power = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    return power;
}

pub fn decodeStateLabel(bytes: []const u8, offsetRef: *OffsetRef) ![]const u8 {
    return try decodeString(bytes, offsetRef, 32);
}

pub fn decodeStateVersion(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    vendor: u32,
    product: u32,
} {
    if (offsetRef.current + 8 > bytes.len) return error.OutOfBounds;
    const vendor = readUint32LE(bytes, offsetRef.current);
    offsetRef.current += 4;
    const product = readUint32LE(bytes, offsetRef.current);
    offsetRef.current += 4;
    return .{ .vendor = vendor, .product = product };
}

pub fn decodeStateInfo(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    time: std.time.Time,
    uptime: std.time.Time,
    downtime: std.time.Time,
} {
    const time = decodeTimestamp(bytes, offsetRef);
    const uptime = decodeTimestamp(bytes, offsetRef);
    const downtime = decodeTimestamp(bytes, offsetRef);
    return .{
        .time = time,
        .uptime = uptime,
        .downtime = downtime,
    };
}

pub fn decodeStateLocation(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    location: []const u8,
    label: []const u8,
    updated_at: std.time.Time,
} {
    const location = decodeBytes(bytes, offsetRef, 16);
    const label = try decodeString(bytes, offsetRef, 32);
    const updated_at = decodeTimestamp(bytes, offsetRef);
    return .{
        .location = location,
        .label = label,
        .updated_at = updated_at,
    };
}

pub fn decodeStateGroup(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    group: []const u8,
    label: []const u8,
    updated_at: u64,
} {
    const group = decodeUuid(bytes, offsetRef);
    const label = try decodeString(bytes, offsetRef, 32);
    if (offsetRef.current + 8 > bytes.len) return error.OutOfBounds;
    const updated_at = readBigUint64LE(bytes, offsetRef.current);
    offsetRef.current += 8;
    return .{
        .group = group,
        .label = label,
        .updated_at = updated_at,
    };
}

pub fn decodeEchoResponse(bytes: []const u8, offsetRef: *OffsetRef) []const u8 {
    // 64 bytes
    return decodeBytes(bytes, offsetRef, 64);
}

pub fn decodeStateUnhandled(bytes: []const u8, offsetRef: *OffsetRef) !u16 {
    if (offsetRef.current + 2 > bytes.len) return error.OutOfBounds;
    const typ = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    return typ;
}

pub fn decodeSetColor(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    reserved: []const u8,
    hue: u16,
    saturation: u16,
    brightness: u16,
    kelvin: u16,
    duration: u32,
} {
    const reserved = decodeBytes(bytes, offsetRef, 1);
    if (offsetRef.current + 13 - 1 > bytes.len) return error.OutOfBounds;
    const hue = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const saturation = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const brightness = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const kelvin = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const duration = readUint32LE(bytes, offsetRef.current);
    offsetRef.current += 4;

    return .{
        .reserved = reserved,
        .hue = hue,
        .saturation = saturation,
        .brightness = brightness,
        .kelvin = kelvin,
        .duration = duration,
    };
}

/// encodeSetColor(hue, saturation, brightness, kelvin, duration)
pub fn encodeSetColor(allocator: *std.mem.Allocator, hue: u16, saturation: u16, brightness: u16, kelvin: u16, duration: u32) ![]u8 {
    // 13 bytes
    const payload = try allocator.alloc(u8, 13);
    @memset(payload, 0);

    writeUint16LE(payload, 1, hue);
    writeUint16LE(payload, 3, saturation);
    writeUint16LE(payload, 5, brightness);
    writeUint16LE(payload, 7, kelvin);
    writeUint32LE(payload, 9, duration);

    return payload;
}

pub fn decodeLightState(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    hue: u16,
    saturation: u16,
    brightness: u16,
    kelvin: u16,
    power: u16,
    label: []const u8,
    reserved2: []const u8,
    reserved8: []const u8,
} {
    if (offsetRef.current + 52 > bytes.len) return error.OutOfBounds;
    const hue = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const saturation = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const brightness = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    const kelvin = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;

    const reserved2 = decodeBytes(bytes, offsetRef, 2);

    const power = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;

    const label = try decodeString(bytes, offsetRef, 32);

    const reserved8 = decodeBytes(bytes, offsetRef, 8);

    return .{
        .hue = hue,
        .saturation = saturation,
        .brightness = brightness,
        .kelvin = kelvin,
        .power = power,
        .label = label,
        .reserved2 = reserved2,
        .reserved8 = reserved8,
    };
}

pub fn decodeStateLightPower(bytes: []const u8, offsetRef: *OffsetRef) !u16 {
    return decodeStatePower(bytes, offsetRef);
}

pub fn decodeStateInfrared(bytes: []const u8, offsetRef: *OffsetRef) !u16 {
    return decodeStatePower(bytes, offsetRef);
}

pub fn decodeStateHevCycle(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    duration_s: u32,
    remaining_s: u32,
    last_power: bool,
} {
    if (offsetRef.current + 9 > bytes.len) return error.OutOfBounds;
    const duration_s = readUint32LE(bytes, offsetRef.current);
    offsetRef.current += 4;
    const remaining_s = readUint32LE(bytes, offsetRef.current);
    offsetRef.current += 4;
    const last_power = (readUint8(bytes, offsetRef.current) != 0);
    offsetRef.current += 1;
    return .{
        .duration_s = duration_s,
        .remaining_s = remaining_s,
        .last_power = last_power,
    };
}

pub fn decodeStateHevCycleConfiguration(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    indication: u8,
    duration_s: u32,
} {
    if (offsetRef.current + 5 > bytes.len) return error.OutOfBounds;
    const indication = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;
    const duration_s = readUint32LE(bytes, offsetRef.current);
    offsetRef.current += 4;
    return .{
        .indication = indication,
        .duration_s = duration_s,
    };
}

pub fn decodeStateLastHevCycleResult(bytes: []const u8, offsetRef: *OffsetRef) !u8 {
    if (offsetRef.current + 1 > bytes.len) return error.OutOfBounds;
    const result = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;
    return result;
}

pub fn decodeStateRPower(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    relay_index: u8,
    level: u16,
} {
    if (offsetRef.current + 3 > bytes.len) return error.OutOfBounds;
    const relay_index = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;
    const level = readUint16LE(bytes, offsetRef.current);
    offsetRef.current += 2;
    return .{
        .relay_index = relay_index,
        .level = level,
    };
}

pub fn decodeStateDeviceChain(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    start_index: u8,
    devices: []struct {
        accel_meas_x: i16,
        accel_meas_y: i16,
        accel_meas_z: i16,
        reserved6: []const u8,
        user_x: f32,
        user_y: f32,
        width: u8,
        height: u8,
        reserved7: []const u8,
        device_version_vendor: u32,
        device_version_product: u32,
        reserved8: []const u8,
        firmware_build: std.time.Time,
        reversed9: []const u8,
        firmware_version_minor: u16,
        firmware_version_major: u16,
        reserved10: []const u8,
    },
    tile_devices_count: u8,
} {
    if (offsetRef.current + 1 > bytes.len) return error.OutOfBounds;
    const start_index = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;

    var devicesArray = std.ArrayList(struct {
        accel_meas_x: i16,
        accel_meas_y: i16,
        accel_meas_z: i16,
        reserved6: []const u8,
        user_x: f32,
        user_y: f32,
        width: u8,
        height: u8,
        reserved7: []const u8,
        device_version_vendor: u32,
        device_version_product: u32,
        reserved8: []const u8,
        firmware_build: std.time.Time,
        reversed9: []const u8,
        firmware_version_minor: u16,
        firmware_version_major: u16,
        reserved10: []const u8,
    }).init(std.heap.page_allocator);

    defer devicesArray.deinit();

    // 16 devices
    for (std.math.zeroes(16)) |_| {
        // if (offsetRef.current + 2*3 + 2 + 4*2 + 2 + 1 + 1 + 1 + 4*2 + 8 + 8 + 4 + /* ... etc. */ 0 > bytes.len) {
        //     // We'll do a partial check below as we decode
        //     return error.OutOfBounds;
        // }
        const accel_meas_x = i16(readUint16LE(bytes, offsetRef.current));
        offsetRef.current += 2;
        const accel_meas_y = i16(readUint16LE(bytes, offsetRef.current));
        offsetRef.current += 2;
        const accel_meas_z = i16(readUint16LE(bytes, offsetRef.current));
        offsetRef.current += 2;
        const reserved6 = decodeBytes(bytes, offsetRef, 2);
        const user_x = readFloat32LE(bytes, offsetRef.current);
        offsetRef.current += 4;
        const user_y = readFloat32LE(bytes, offsetRef.current);
        offsetRef.current += 4;
        const width = readUint8(bytes, offsetRef.current);
        offsetRef.current += 1;
        const height = readUint8(bytes, offsetRef.current);
        offsetRef.current += 1;
        const reserved7 = decodeBytes(bytes, offsetRef, 1);
        const device_version_vendor = readUint32LE(bytes, offsetRef.current);
        offsetRef.current += 4;
        const device_version_product = readUint32LE(bytes, offsetRef.current);
        offsetRef.current += 4;
        const reserved8 = decodeBytes(bytes, offsetRef, 4);
        const firmware_build = decodeTimestamp(bytes, offsetRef);
        const reversed9 = decodeBytes(bytes, offsetRef, 8);
        const firmware_version_minor = readUint16LE(bytes, offsetRef.current);
        offsetRef.current += 2;
        const firmware_version_major = readUint16LE(bytes, offsetRef.current);
        offsetRef.current += 2;
        const reserved10 = decodeBytes(bytes, offsetRef, 4);

        try devicesArray.append(.{
            .accel_meas_x = accel_meas_x,
            .accel_meas_y = accel_meas_y,
            .accel_meas_z = accel_meas_z,
            .reserved6 = reserved6,
            .user_x = user_x,
            .user_y = user_y,
            .width = width,
            .height = height,
            .reserved7 = reserved7,
            .device_version_vendor = device_version_vendor,
            .device_version_product = device_version_product,
            .reserved8 = reserved8,
            .firmware_build = firmware_build,
            .reversed9 = reversed9,
            .firmware_version_minor = firmware_version_minor,
            .firmware_version_major = firmware_version_major,
            .reserved10 = reserved10,
        });
    }

    if (offsetRef.current + 1 > bytes.len) return error.OutOfBounds;
    const tile_devices_count = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;

    return .{
        .start_index = start_index,
        .devices = devicesArray.toOwnedSlice(),
        .tile_devices_count = tile_devices_count,
    };
}

pub fn decodeState64(bytes: []const u8, offsetRef: *OffsetRef) !struct {
    tile_index: u8,
    reserved6: []const u8,
    x: u8,
    y: u8,
    width: u8,
    colors: []struct {
        hue: u16,
        saturation: u16,
        brightness: u16,
        kelvin: u16,
    },
} {
    if (offsetRef.current + 4 > bytes.len) return error.OutOfBounds;
    const tile_index = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;
    const reserved6 = decodeBytes(bytes, offsetRef, 1);
    const x = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;
    const y = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;
    const width = readUint8(bytes, offsetRef.current);
    offsetRef.current += 1;

    // 64 colors, each 8 bytes => 512 bytes
    var colorsBuilder = std.ArrayList(struct {
        hue: u16,
        saturation: u16,
        brightness: u16,
        kelvin: u16,
    }).init(std.heap.page_allocator);
    defer colorsBuilder.deinit();

    for (std.math.zeroes(64)) |_| {
        if (offsetRef.current + 8 > bytes.len) return error.OutOfBounds;
        const hue = readUint16LE(bytes, offsetRef.current);
        offsetRef.current += 2;
        const saturation = readUint16LE(bytes, offsetRef.current);
        offsetRef.current += 2;
        const brightness = readUint16LE(bytes, offsetRef.current);
        offsetRef.current += 2;
        const kelvin = readUint16LE(bytes, offsetRef.current);
        offsetRef.current += 2;
        try colorsBuilder.append(.{
            .hue = hue,
            .saturation = saturation,
            .brightness = brightness,
            .kelvin = kelvin,
        });
    }

    return .{
        .tile_index = tile_index,
        .reserved6 = reserved6,
        .x = x,
        .y = y,
        .width = width,
        .colors = colorsBuilder.toOwnedSlice(),
    };
}

////////////////////////////////////////////////////////////////////////////////
// getHeader* and decodeHeader
////////////////////////////////////////////////////////////////////////////////

pub fn getHeaderSize(bytes: []const u8, offset: usize) u16 {
    return readUint16LE(bytes, offset);
}

pub fn getHeaderFlags(bytes: []const u8, offset: usize) u16 {
    return readUint16LE(bytes, offset + 2);
}

pub fn getHeaderTagged(bytes: []const u8, offset: usize) bool {
    const flags = getHeaderFlags(bytes, offset);
    return (((flags >> 13) & 0b1) == 1);
}

pub fn getHeaderSource(bytes: []const u8, offset: usize) u32 {
    return readUint32LE(bytes, offset + 4);
}

pub fn getHeaderTarget(bytes: []const u8, offset: usize) *const [6]u8 {
    return bytes[offset + 8 .. offset + 14][0..6];
}

pub fn getHeaderResponseFlags(bytes: []const u8, offset: usize) u8 {
    return readUint8(bytes, offset + 22);
}

pub fn getHeaderResponseRequired(responseFlags: u8) bool {
    return (responseFlags & 0b1) != 0;
}

pub fn getHeaderAcknowledgeRequired(responseFlags: u8) bool {
    return (responseFlags & 0b10) != 0;
}

pub fn getHeaderType(bytes: []const u8, offset: usize) u16 {
    return readUint16LE(bytes, offset + 32);
}

pub fn getHeaderSequence(bytes: []const u8, offset: usize) u8 {
    return readUint8(bytes, offset + 23);
}

// pub fn getPayload(bytes: []const u8, offset: usize) []const u8 {
//     if (36 + offset > bytes.len) return bytes[bytes.len..bytes.len];
//     return bytes[offset + 36 ..];
// }

pub fn getPayload(bytes: []const u8) []const u8 {
    // if (36 + offset > bytes.len) {
    //     std.debug.print("No payload: {any}, {any}\n", .{ bytes.len, offset });
    //     return bytes[bytes.len..bytes.len];
    // }
    // std.debug.print("Has payload: {any}, {any}\n", .{ bytes.len, offset });
    return bytes[36..];
}

pub const Header = struct {
    bytes: []const u8,
    size: u16,
    protocol: u16,
    addressable: bool,
    tagged: bool,
    origin: u16,
    source: u32,
    target: *const [6]u8,
    reserved1: []const u8,
    reserved2: []const u8,
    res_required: bool,
    ack_required: bool,
    reserved3: u8,
    reserved4: []const u8,
    sequence: u8,
    reserved5: []const u8,
    type: u16,
};

pub fn decodeHeader(bytes: []const u8, offset: usize) !Header {
    if (offset + 36 > bytes.len) return error.OutOfBounds;

    const size = getHeaderSize(bytes, offset);
    const flags = getHeaderFlags(bytes, offset);
    const protocol = flags & 0x0FFF;
    const addressable = (((flags >> 12) & 0b1) == 1);
    const tagged = (((flags >> 13) & 0b1) == 1);
    const origin = (flags >> 14) & 0b11;

    const source = getHeaderSource(bytes, offset);
    const target = getHeaderTarget(bytes, offset);

    const reserved1 = bytes[offset + 14 .. offset + 16];
    const reserved2 = bytes[offset + 16 .. offset + 22];

    const responseFlags = getHeaderResponseFlags(bytes, offset);
    const res_required = getHeaderResponseRequired(responseFlags);
    const ack_required = getHeaderAcknowledgeRequired(responseFlags);
    const reserved3 = (responseFlags & 0b11111100) >> 2;

    const sequence = getHeaderSequence(bytes, offset);

    const reserved4 = bytes[offset + 24 .. offset + 32];
    const typ = getHeaderType(bytes, offset);

    const reserved5 = bytes[offset + 34 .. offset + 36];

    // Return the struct
    return .{
        .bytes = bytes[offset .. offset + 36],
        .size = size,
        .protocol = protocol,
        .addressable = addressable,
        .tagged = tagged,
        .origin = @as(u16, origin),
        .source = source,
        .target = target,
        .reserved1 = reserved1,
        .reserved2 = reserved2,
        .res_required = res_required,
        .ack_required = ack_required,
        .reserved3 = reserved3,
        .reserved4 = reserved4,
        .sequence = sequence,
        .reserved5 = reserved5,
        .type = typ,
    };
}
