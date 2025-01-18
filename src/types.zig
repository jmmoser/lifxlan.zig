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

pub const MessageHandler = struct {
    onMessageFn: *const fn (ptr: *anyopaque, header: Header, payload: []const u8, serialNumber: [12]u8) void,
    ptr: *anyopaque,

    pub fn init(ptr: anytype) MessageHandler {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);

        const gen = struct {
            pub fn handler(pointer: *anyopaque, header: Header, payload: []const u8, serialNumber: [12]u8) void {
                const self: T = @ptrCast(@alignCast(pointer));
                return ptr_info.Pointer.child.handler(self, header, payload, serialNumber);
            }
        };

        return .{
            .ptr = ptr,
            .onMessageFn = gen.handler,
        };
    }

    pub fn onMessage(self: MessageHandler, header: Header, payload: []const u8, serialNumber: [12]u8) void {
        self.onMessageFn(self.ptr, header, payload, serialNumber);
    }
};
