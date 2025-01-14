const std = @import("std");
const testing = std.testing;
const lifx = @import("encoding.zig"); // Import the main LIFX protocol code

test "encode uuid" {
    var bytes: [16]u8 = undefined;
    try lifx.encodeUuidTo(&bytes, 0, "4e0352bf-1994-4ff2-b425-1c4455479f33");

    try testing.expectEqualSlices(u8, &[_]u8{
        0x4e, 0x03, 0x52, 0xbf, 0x19, 0x94, 0x4f, 0xf2,
        0xb4, 0x25, 0x1c, 0x44, 0x55, 0x47, 0x9f, 0x33,
    }, &bytes);
}

test "encode string" {
    var allocator = std.heap.page_allocator;
    const bytes = try lifx.encodeString(&allocator, "abc", 32);
    defer allocator.free(bytes);

    try testing.expectEqualSlices(u8, &[_]u8{
        0x61, 0x62, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    }, bytes);
}

test "decode header" {
    const bytes = &[_]u8{
        0x24, 0x00, 0x00, 0x34, 0x99, 0x9c, 0x8c, 0xc9,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x05,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00,
    };

    const header = try lifx.decodeHeader(bytes, 0);

    // Test individual fields since we can't do deep equality on structs easily
    try testing.expectEqual(@as(u16, bytes.len), header.size);
    try testing.expectEqual(@as(u16, 2), header.type);
    try testing.expectEqual(@as(u16, 1024), header.protocol);
    try testing.expectEqual(true, header.addressable);
    try testing.expectEqual(true, header.tagged);
    try testing.expectEqual(@as(u16, 0), header.origin);
    try testing.expectEqual(@as(u32, 3381435545), header.source);
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 5, 6 }, header.target);
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 0 }, header.reserved1);
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0, 0, 0 }, header.reserved2);
    try testing.expectEqual(true, header.res_required);
    try testing.expectEqual(false, header.ack_required);
    try testing.expectEqual(@as(u8, 0), header.reserved3);
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, header.reserved4);
    try testing.expectEqual(@as(u8, 5), header.sequence);
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 0 }, header.reserved5);

    // Test re-encoding produces the same bytes
    var allocator = std.heap.page_allocator;
    const target = header.target;
    const encodedBytes = try lifx.encode(
        &allocator,
        header.tagged,
        header.source,
        target,
        header.res_required,
        header.ack_required,
        header.sequence,
        header.type,
        null, // no payload in this test
    );
    defer allocator.free(encodedBytes);

    try testing.expectEqualSlices(u8, bytes, encodedBytes);
}

test "encode with payload" {
    var allocator = std.heap.page_allocator;
    const target = &[_]u8{ 1, 2, 3, 4, 5, 6 };
    const payload = &[_]u8{ 1, 2, 3, 4, 5, 6 };
    const bytes = try lifx.encode(
        &allocator,
        false,
        1,
        target,
        true,
        false,
        0,
        2,
        payload,
    );
    defer allocator.free(bytes);

    try testing.expectEqualSlices(u8, &[_]u8{
        0x2a, 0x00, 0x00, 0x14, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
        0x05, 0x06,
    }, bytes);
}
