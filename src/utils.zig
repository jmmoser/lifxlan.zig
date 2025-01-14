const std = @import("std");

pub const RssiStatus = enum {
    none,
    very_bad,
    somewhat_bad,
    alright,
    good,
};

/// Converts HSB color values to RGB
/// h: [0-65535], s: [0-65535], b: [0-65535]
/// Returns RGB values [0-255]
pub fn hsbToRgb(h: u16, s: u16, b: u16) struct { r: u8, g: u8, b: u8 } {
    const h_norm = @as(f32, @floatFromInt(h)) * 6.0 / 65535.0;
    const s_norm = @as(f32, @floatFromInt(s)) / 65535.0;
    const b_norm = @as(f32, @floatFromInt(b)) * 255.0 / 65535.0;

    const i = @as(u32, @intFromFloat(@floor(h_norm)));
    const f = h_norm - @floor(h_norm);
    const p = b_norm * (1.0 - s_norm);
    const q = b_norm * (1.0 - s_norm * f);
    const t = b_norm * (1.0 - s_norm * (1.0 - f));

    var r: f32 = undefined;
    var g: f32 = undefined;
    var bl: f32 = undefined;

    switch (i % 6) {
        0 => {
            r = b_norm;
            g = t;
            bl = p;
        },
        1 => {
            r = q;
            g = b_norm;
            bl = p;
        },
        2 => {
            r = p;
            g = b_norm;
            bl = t;
        },
        3 => {
            r = p;
            g = q;
            bl = b_norm;
        },
        4 => {
            r = t;
            g = p;
            bl = b_norm;
        },
        else => {
            r = b_norm;
            g = p;
            bl = q;
        },
    }

    return .{
        .r = @intFromFloat(@round(r)),
        .g = @intFromFloat(@round(g)),
        .b = @intFromFloat(@round(bl)),
    };
}

/// Converts RGB color values to HSB
/// r, g, b: [0-255]
/// Returns HSB values [0-65535]
pub fn rgbToHsb(r: u8, g: u8, b: u8) struct { h: u16, s: u16, b: u16 } {
    const r_norm = @as(f32, @floatFromInt(r)) / 255.0;
    const g_norm = @as(f32, @floatFromInt(g)) / 255.0;
    const b_norm = @as(f32, @floatFromInt(b)) / 255.0;

    const v = @max(@max(r_norm, g_norm), b_norm);
    const n = v - @min(@min(r_norm, g_norm), b_norm);

    var h: f32 = 0.0;
    if (n != 0.0) {
        if (v == r_norm) {
            h = (g_norm - b_norm) / n;
        } else if (v == g_norm) {
            h = 2.0 + (b_norm - r_norm) / n;
        } else {
            h = 4.0 + (r_norm - g_norm) / n;
        }
    }

    if (h < 0.0) h += 6.0;

    return .{
        .h = @intFromFloat(@round(60.0 * h * (65535.0 / 360.0))),
        .s = @intFromFloat(@round(if (v != 0.0) (n / v) * 65535.0 else 0.0)),
        .b = @intFromFloat(@round(v * 65535.0)),
    };
}

/// Get RSSI status from signal strength
pub fn getRssiStatus(rssi: i32) RssiStatus {
    if (rssi == 200) return .none;

    if (rssi < -80 or rssi == 4 or rssi == 5 or rssi == 6) {
        return .very_bad;
    }

    if (rssi < -70 or (rssi >= 7 and rssi <= 11)) {
        return .somewhat_bad;
    }

    if (rssi < -60 or (rssi >= 12 and rssi <= 16)) {
        return .alright;
    }

    if (rssi < 0 or rssi > 16) {
        return .good;
    }

    return .none;
}

/// Convert signal strength to RSSI value
pub fn convertSignalToRssi(signal: f32) i32 {
    return @intFromFloat(@floor(10.0 * @log10(signal) + 0.5));
}

pub fn convertTargetToSerialNumber(target: *const [6]u8) [12]u8 {
    return std.fmt.bytesToHex(target, .lower);
}

/// Convert serial number string to target bytes
pub fn convertSerialNumberToTarget(serialNumber: []const u8) ![6]u8 {
    if (serialNumber.len != 12) {
        return error.InvalidSerialNumber;
    }

    var target: [6]u8 = undefined;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        const offset = 2 * i;
        const byte_str = serialNumber[offset .. offset + 2];
        target[i] = try std.fmt.parseInt(u8, byte_str, 16);
    }

    return target;
}

test "hsbToRgb" {
    const rgb = hsbToRgb(0, 0, 65535);
    try std.testing.expectEqual(@as(u8, 255), rgb.r);
    try std.testing.expectEqual(@as(u8, 255), rgb.g);
    try std.testing.expectEqual(@as(u8, 255), rgb.b);
}

test "rgbToHsb" {
    const hsb = rgbToHsb(255, 255, 255);
    try std.testing.expectEqual(@as(u16, 0), hsb.h);
    try std.testing.expectEqual(@as(u16, 0), hsb.s);
    try std.testing.expectEqual(@as(u16, 65535), hsb.b);
}

test "convertTargetToSerialNumber" {
    const target = [_]u8{ 0xd0, 0x73, 0xd5, 0x00, 0x11, 0x22 };
    const serial = convertTargetToSerialNumber(&target);
    try std.testing.expectEqualStrings("d073d5001122", &serial);
}

test "convertSerialNumberToTarget" {
    const serial = "d073d5001122";
    const target = try convertSerialNumberToTarget(serial);
    try std.testing.expectEqual(@as(u8, 0xd0), target[0]);
    try std.testing.expectEqual(@as(u8, 0x73), target[1]);
    try std.testing.expectEqual(@as(u8, 0xd5), target[2]);
    try std.testing.expectEqual(@as(u8, 0x00), target[3]);
    try std.testing.expectEqual(@as(u8, 0x11), target[4]);
    try std.testing.expectEqual(@as(u8, 0x22), target[5]);
}

test "getRssiStatus" {
    try std.testing.expectEqual(RssiStatus.none, getRssiStatus(200));
    try std.testing.expectEqual(RssiStatus.very_bad, getRssiStatus(-85));
    try std.testing.expectEqual(RssiStatus.somewhat_bad, getRssiStatus(-75));
    try std.testing.expectEqual(RssiStatus.alright, getRssiStatus(-65));
    try std.testing.expectEqual(RssiStatus.good, getRssiStatus(-55));
}

test "convertSignalToRssi" {
    const rssi = convertSignalToRssi(1.0);
    try std.testing.expectEqual(@as(i32, 0), rssi);
}
