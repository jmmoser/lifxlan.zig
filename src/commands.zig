const std = @import("std");
const constants = @import("constants.zig");
const encoding = @import("encoding.zig");

pub const Decode = *const fn (bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void;

pub const Command = struct {
    type: u16,
    payload: ?[]const u8 = null,
    decode: Decode,
};

fn noopDecode(_: []const u8, _: *encoding.OffsetRef) anyerror!void {}

pub fn GetServiceCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetService),
        // .decode = encoding.decodeStateService,
        .decode = struct {
            fn wrap(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
                _ = try encoding.decodeStateService(bytes, offsetRef);
            }
        }.wrap,
    };
}

pub fn GetHostFirmwareCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetHostFirmware),
        .decode = encoding.decodeStateHostFirmware,
    };
}

pub fn GetWifiInfoCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetWifiInfo),
        .decode = encoding.decodeStateWifiInfo,
    };
}

pub fn GetWifiFirmwareCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetWifiFirmware),
        .decode = encoding.decodeStateWifiFirmware,
    };
}

pub fn GetColorCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetColor),
        // .decode = encoding.decodeLightState,
        .decode = noopDecode,
    };
}

pub fn GetPowerCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetPower),
        .decode = encoding.decodeStatePower,
    };
}

pub fn SetPowerCommand(allocator: std.mem.Allocator, power: anytype) !Command {
    var payload = try allocator.alloc(u8, 2);
    const value: u16 = switch (@TypeOf(power)) {
        bool => if (power) 65535 else 0,
        u16 => power,
        else => @compileError("power must be bool or u16"),
    };
    std.mem.writeIntLittle(u16, payload[0..2], value);

    return .{
        .type = @intFromEnum(constants.CommandType.SetPower),
        .payload = payload,
        .decode = encoding.decodeStatePower,
    };
}

pub fn GetLabelCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetLabel),
        // .decode = encoding.decodeStateLabel,
        .decode = struct {
            fn wrap(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
                _ = try encoding.decodeStateLabel(bytes, offsetRef);
            }
        }.wrap,
    };
}

pub fn SetLabelCommand(allocator: std.mem.Allocator, label: []const u8) !Command {
    return .{
        .type = @intFromEnum(constants.CommandType.SetLabel),
        .payload = try encoding.encodeString(allocator, label, 32),
        .decode = encoding.decodeStateLabel,
    };
}

pub fn GetVersionCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetVersion),
        .decode = encoding.decodeStateVersion,
    };
}

pub fn GetInfoCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetInfo),
        .decode = encoding.decodeStateInfo,
    };
}

pub fn SetRebootCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.SetReboot),
        .decode = struct {
            fn noop(_: []const u8, _: *encoding.OffsetRef) !void {}
        }.noop,
    };
}

pub fn GetLocationCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetLocation),
        .decode = encoding.decodeStateLocation,
    };
}

pub fn SetLocationCommand(
    allocator: std.mem.Allocator,
    location: anytype,
    label: []const u8,
    updatedAt: std.time.Timestamp,
) !Command {
    var payload = try allocator.alloc(u8, 56);
    errdefer allocator.free(payload);

    switch (@TypeOf(location)) {
        []const u8 => {
            if (location.len == 16) {
                @memcpy(payload[0..16], location);
            } else {
                try encoding.encodeUuidTo(payload, 0, location);
            }
        },
        else => @compileError("location must be []const u8"),
    }

    try encoding.encodeStringTo(payload, 16, label, 32);
    try encoding.encodeTimestampTo(payload[48..], updatedAt);

    return .{
        .type = @intFromEnum(constants.CommandType.SetLocation),
        .payload = payload,
        .decode = encoding.decodeStateLocation,
    };
}

// Similar pattern for other commands...

pub fn SetColorCommand(
    allocator: std.mem.Allocator,
    hue: u16,
    saturation: u16,
    brightness: u16,
    kelvin: u16,
    duration: u32,
) !Command {
    var payload = try allocator.alloc(u8, 13);
    errdefer allocator.free(payload);

    std.mem.writeIntLittle(u8, payload[0..1], 0); // reserved
    std.mem.writeIntLittle(u16, payload[1..3], hue);
    std.mem.writeIntLittle(u16, payload[3..5], saturation);
    std.mem.writeIntLittle(u16, payload[5..7], brightness);
    std.mem.writeIntLittle(u16, payload[7..9], kelvin);
    std.mem.writeIntLittle(u32, payload[9..13], duration);

    return .{
        .type = @intFromEnum(constants.CommandType.SetColor),
        .payload = payload,
        .decode = encoding.decodeLightState,
    };
}

pub fn SetWaveformCommand(
    allocator: std.mem.Allocator,
    transient: bool,
    hue: u16,
    saturation: u16,
    brightness: u16,
    kelvin: u16,
    period: u32,
    cycles: f32,
    skewRatio: i16,
    waveform: constants.Waveform,
) !Command {
    var payload = try allocator.alloc(u8, 21);
    errdefer allocator.free(payload);

    payload[0] = 0; // reserved
    payload[1] = if (transient) 1 else 0;
    std.mem.writeIntLittle(u16, payload[2..4], hue);
    std.mem.writeIntLittle(u16, payload[4..6], saturation);
    std.mem.writeIntLittle(u16, payload[6..8], brightness);
    std.mem.writeIntLittle(u16, payload[8..10], kelvin);
    std.mem.writeIntLittle(u32, payload[10..14], period);
    std.mem.writeIntLittle(f32, payload[14..18], cycles);
    std.mem.writeIntLittle(i16, payload[18..20], skewRatio);
    payload[20] = @intFromEnum(waveform);

    return .{
        .type = @intFromEnum(constants.CommandType.SetWaveform),
        .payload = payload,
        .decode = encoding.decodeLightState,
    };
}
