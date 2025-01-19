pub const NO_TARGET: [6]u8 = [_]u8{0x00} ** 6;
pub const NO_SERIAL_NUMBER: [12]u8 = [_]u8{'0'} ** 12;
pub const BROADCAST: [4]u8 = [_]u8{ 255, 255, 255, 255 };
pub const PORT: u16 = 56700;

pub const ServiceType = enum(u8) {
    UDP = 1,
    RESERVED2 = 2,
    RESERVED3 = 3,
    RESERVED4 = 4,
    RESERVED5 = 5,
};

pub const Direction = enum(u8) {
    RIGHT = 0,
    LEFT = 1,
};

/// Result of the last HEV cycle operation
pub const LightLastHevCycleResult = enum(u8) {
    SUCCESS = 0,
    BUSY = 1,
    INTERRUPTED_BY_RESET = 2,
    INTERRUPTED_BY_HOMEKIT = 3,
    INTERRUPTED_BY_LAN = 4,
    INTERRUPTED_BY_CLOUD = 5,
    NONE = 255,
};

/// Application request state for multi-zone operations
pub const MultiZoneApplicationRequest = enum(u8) {
    NO_APPLY = 0,
    APPLY = 1,
    APPLY_ONLY = 2,
};

/// Types of effects available for multi-zone devices
pub const MultiZoneEffectType = enum(u8) {
    OFF = 0,
    MOVE = 1,
    RESERVED1 = 2,
    RESERVED2 = 3,
};

/// Extended application request state for multi-zone operations
pub const MultiZoneExtendedApplicationRequest = enum(u8) {
    NO_APPLY = 0,
    APPLY = 1,
    APPLY_ONLY = 2,
};

/// Types of effects available for tile devices
pub const TileEffectType = enum(u8) {
    OFF = 0,
    RESERVED1 = 1,
    MORPH = 2,
    FLAME = 3,
    RESERVED2 = 4,
};

/// Available waveform patterns
pub const Waveform = enum(u8) {
    SAW = 0,
    SINE = 1,
    HALF_SINE = 2,
    TRIANGLE = 3,
    PULSE = 4,
};

/// Message types for device communication
pub const CommandType = enum(u16) {
    // Core functionality
    GetService = 2,
    StateService = 3,
    GetHostFirmware = 14,
    StateHostFirmware = 15,
    GetWifiInfo = 16,
    StateWifiInfo = 17,
    GetWifiFirmware = 18,
    StateWifiFirmware = 19,
    GetPower = 20,
    SetPower = 21,
    StatePower = 22,
    GetLabel = 23,
    SetLabel = 24,
    StateLabel = 25,
    GetVersion = 32,
    StateVersion = 33,
    GetInfo = 34,
    StateInfo = 35,
    SetReboot = 38,
    Acknowledgement = 45,
    GetLocation = 48,
    SetLocation = 49,
    StateLocation = 50,
    GetGroup = 51,
    SetGroup = 52,
    StateGroup = 53,
    EchoRequest = 58,
    EchoResponse = 59,
    StateUnhandled = 223,

    // Light functionality
    GetColor = 101,
    SetColor = 102,
    SetWaveform = 103,
    LightState = 107,
    GetLightPower = 116,
    SetLightPower = 117,
    StateLightPower = 118,
    SetWaveformOptional = 119,
    GetInfrared = 120,
    StateInfrared = 121,
    SetInfrared = 122,
    GetHevCycle = 142,
    SetHevCycle = 143,
    StateHevCycle = 144,
    GetHevCycleConfiguration = 145,
    SetHevCycleConfiguration = 146,
    StateHevCycleConfiguration = 147,
    GetLastHevCycleResult = 148,
    StateLastHevCycleResult = 149,

    // Sensor functionality
    SensorGetAmbientLight = 401,
    SensorStateAmbientLight = 402,

    // MultiZone functionality
    SetColorZones = 501,
    GetColorZones = 502,
    StateZone = 503,
    StateMultiZone = 506,
    GetMultiZoneEffect = 507,
    SetMultiZoneEffect = 508,
    StateMultiZoneEffect = 509,
    SetExtendedColorZones = 510,
    GetExtendedColorZones = 511,
    StateExtendedColorZones = 512,

    // Tile functionality
    GetDeviceChain = 701,
    StateDeviceChain = 702,
    Get64 = 707,
    State64 = 711,
    Set64 = 715,
    GetTileEffect = 718,
    SetTileEffect = 719,
    StateTileEffect = 720,

    // Relay functionality
    GetRPower = 816,
    SetRPower = 817,
    StateRPower = 818,
};
