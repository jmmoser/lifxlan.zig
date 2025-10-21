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

fn wrapDecodeStateService(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStateService(bytes, offsetRef);
}

fn wrapDecodeStateHostFirmware(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStateHostFirmware(bytes, offsetRef);
}

fn wrapDecodeStateWifiInfo(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStateWifiInfo(bytes, offsetRef);
}

fn wrapDecodeStateWifiFirmware(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStateWifiFirmware(bytes, offsetRef);
}

fn wrapDecodeStatePower(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStatePower(bytes, offsetRef);
}

fn wrapDecodeStateLabel(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStateLabel(bytes, offsetRef);
}

fn wrapDecodeStateVersion(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStateVersion(bytes, offsetRef);
}

fn wrapDecodeStateInfo(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStateInfo(bytes, offsetRef);
}

fn wrapDecodeStateLocation(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeStateLocation(bytes, offsetRef);
}

fn wrapDecodeLightState(bytes: []const u8, offsetRef: *encoding.OffsetRef) anyerror!void {
    _ = try encoding.decodeLightState(bytes, offsetRef);
}

pub fn GetServiceCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetService),
        .decode = wrapDecodeStateService,
    };
}

pub fn GetHostFirmwareCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetHostFirmware),
        .decode = wrapDecodeStateHostFirmware,
    };
}

pub fn GetWifiInfoCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetWifiInfo),
        .decode = wrapDecodeStateWifiInfo,
    };
}

pub fn GetWifiFirmwareCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetWifiFirmware),
        .decode = wrapDecodeStateWifiFirmware,
    };
}

pub fn GetColorCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetColor),
        .decode = wrapDecodeLightState,
    };
}

pub fn GetPowerCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetPower),
        .decode = wrapDecodeStatePower,
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
        .decode = wrapDecodeStatePower,
    };
}

pub fn GetLabelCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetLabel),
        .decode = wrapDecodeStateLabel,
    };
}

pub fn SetLabelCommand(allocator: std.mem.Allocator, label: []const u8) !Command {
    return .{
        .type = @intFromEnum(constants.CommandType.SetLabel),
        .payload = try encoding.encodeString(allocator, label, 32),
        .decode = wrapDecodeStateLabel,
    };
}

pub fn GetVersionCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetVersion),
        .decode = wrapDecodeStateVersion,
    };
}

pub fn GetInfoCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetInfo),
        .decode = wrapDecodeStateInfo,
    };
}

pub fn SetRebootCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.SetReboot),
        .decode = noopDecode,
    };
}

pub fn GetLocationCommand() Command {
    return .{
        .type = @intFromEnum(constants.CommandType.GetLocation),
        .decode = wrapDecodeStateLocation,
    };
}

pub fn SetLocationCommand(
    allocator: std.mem.Allocator,
    location: anytype,
    label: []const u8,
    updatedAt: u64,
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

    encoding.encodeStringTo(payload, 16, label, 32);
    encoding.encodeTimestampTo(payload, 48, updatedAt);

    return .{
        .type = @intFromEnum(constants.CommandType.SetLocation),
        .payload = payload,
        .decode = wrapDecodeStateLocation,
    };
}

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
        .decode = wrapDecodeLightState,
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
        .decode = wrapDecodeLightState,
    };
}
