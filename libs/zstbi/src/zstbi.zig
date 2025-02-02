pub const version = @import("std").SemanticVersion{ .major = 0, .minor = 9, .patch = 1 };
const std = @import("std");
const assert = std.debug.assert;

pub fn init(allocator: std.mem.Allocator) void {
    assert(mem_allocator == null);
    mem_allocator = allocator;
    mem_allocations = std.AutoHashMap(usize, usize).init(allocator);
}

pub fn deinit() void {
    assert(mem_allocator != null);
    assert(mem_allocations.?.count() == 0);
    mem_allocations.?.deinit();
    mem_allocations = null;
    mem_allocator = null;
}

pub const Image = struct {
    data: []u8,
    width: u32,
    height: u32,
    num_components: u32,
    bytes_per_component: u32,
    bytes_per_row: u32,
    is_hdr: bool,

    pub fn info(filename: [:0]const u8) struct {
        is_supported: bool,
        width: u32,
        height: u32,
        num_components: u32,
    } {
        var w: c_int = 0;
        var h: c_int = 0;
        var c: c_int = 0;
        const is_supported = stbi_info(filename, &w, &h, &c);
        return .{
            .is_supported = is_supported,
            .width = @intCast(u32, w),
            .height = @intCast(u32, h),
            .num_components = @intCast(u32, c),
        };
    }

    pub fn init(filename: [:0]const u8, forced_num_channels: u32) !Image {
        var width: u32 = 0;
        var height: u32 = 0;
        var num_components: u32 = 0;
        var bytes_per_component: u32 = 0;
        var bytes_per_row: u32 = 0;
        var is_hdr = false;

        const data = if (isHdr(filename)) data: {
            var x: c_int = undefined;
            var y: c_int = undefined;
            var ch: c_int = undefined;
            const ptr = stbi_loadf(
                filename,
                &x,
                &y,
                &ch,
                @intCast(c_int, forced_num_channels),
            );
            if (ptr == null) return error.ImageInitFailed;

            num_components = if (forced_num_channels == 0) @intCast(u32, ch) else forced_num_channels;
            width = @intCast(u32, x);
            height = @intCast(u32, y);
            bytes_per_component = 2;
            bytes_per_row = width * num_components * bytes_per_component;
            is_hdr = true;

            // Convert each component from f32 to f16.
            var ptr_f16 = @ptrCast([*]f16, ptr.?);
            const num = width * height * num_components;
            var i: u32 = 0;
            while (i < num) : (i += 1) {
                ptr_f16[i] = @floatCast(f16, ptr.?[i]);
            }
            break :data @ptrCast([*]u8, ptr_f16)[0 .. height * bytes_per_row];
        } else data: {
            var x: c_int = undefined;
            var y: c_int = undefined;
            var ch: c_int = undefined;
            const is_16bit = is16bit(filename);
            const ptr = if (is_16bit) @ptrCast(?[*]u8, stbi_load_16(
                filename,
                &x,
                &y,
                &ch,
                @intCast(c_int, forced_num_channels),
            )) else stbi_load(
                filename,
                &x,
                &y,
                &ch,
                @intCast(c_int, forced_num_channels),
            );
            if (ptr == null) return error.ImageInitFailed;

            num_components = if (forced_num_channels == 0) @intCast(u32, ch) else forced_num_channels;
            width = @intCast(u32, x);
            height = @intCast(u32, y);
            bytes_per_component = if (is_16bit) 2 else 1;
            bytes_per_row = width * num_components * bytes_per_component;
            is_hdr = false;

            break :data @ptrCast([*]u8, ptr)[0 .. height * bytes_per_row];
        };

        return Image{
            .data = data,
            .width = width,
            .height = height,
            .num_components = num_components,
            .bytes_per_component = bytes_per_component,
            .bytes_per_row = bytes_per_row,
            .is_hdr = is_hdr,
        };
    }

    pub fn initFromData(data: []const u8, forced_num_channels: u32) !Image {
        // TODO: Add support for HDR images (https://github.com/michal-z/zig-gamedev/issues/155).
        var width: u32 = 0;
        var height: u32 = 0;
        var num_components: u32 = 0;
        var bytes_per_component: u32 = 0;
        var bytes_per_row: u32 = 0;

        const image_data = data: {
            var x: c_int = undefined;
            var y: c_int = undefined;
            var ch: c_int = undefined;
            const ptr = stbi_load_from_memory(
                data.ptr,
                @intCast(c_int, data.len),
                &x,
                &y,
                &ch,
                @intCast(c_int, forced_num_channels),
            );
            if (ptr == null) return error.ImageInitFailed;

            num_components = if (forced_num_channels == 0) @intCast(u32, ch) else forced_num_channels;
            width = @intCast(u32, x);
            height = @intCast(u32, y);
            bytes_per_component = 1;
            bytes_per_row = width * num_components * bytes_per_component;

            break :data @ptrCast([*]u8, ptr)[0 .. height * bytes_per_row];
        };

        return Image{
            .data = image_data,
            .width = width,
            .height = height,
            .num_components = num_components,
            .bytes_per_component = bytes_per_component,
            .bytes_per_row = bytes_per_row,
            .is_hdr = false,
        };
    }

    pub fn deinit(image: *Image) void {
        stbi_image_free(image.data.ptr);
        image.* = undefined;
    }
};

/// `pub fn setHdrToLdrScale(scale: f32) void`
pub const setHdrToLdrScale = stbi_hdr_to_ldr_scale;

/// `pub fn setHdrToLdrGamma(gamma: f32) void`
pub const setHdrToLdrGamma = stbi_hdr_to_ldr_gamma;

/// `pub fn setLdrToHdrScale(scale: f32) void`
pub const setLdrToHdrScale = stbi_ldr_to_hdr_scale;

/// `pub fn setLdrToHdrGamma(gamma: f32) void`
pub const setLdrToHdrGamma = stbi_ldr_to_hdr_gamma;

pub fn isHdr(filename: [:0]const u8) bool {
    return stbi_is_hdr(filename) == 1;
}

pub fn is16bit(filename: [:0]const u8) bool {
    return stbi_is_16_bit(filename) == 1;
}

pub fn setFlipVerticallyOnLoad(should_flip: bool) void {
    stbi_set_flip_vertically_on_load(if (should_flip) 1 else 0);
}

var mem_allocator: ?std.mem.Allocator = null;
var mem_allocations: ?std.AutoHashMap(usize, usize) = null;
var mem_mutex: std.Thread.Mutex = .{};
const mem_alignment = 16;

export fn zstbiMalloc(size: usize) callconv(.C) ?*anyopaque {
    mem_mutex.lock();
    defer mem_mutex.unlock();

    const mem = mem_allocator.?.alignedAlloc(
        u8,
        mem_alignment,
        size,
    ) catch @panic("zstbi: out of memory");

    mem_allocations.?.put(@ptrToInt(mem.ptr), size) catch @panic("zstbi: out of memory");

    return mem.ptr;
}

export fn zstbiRealloc(ptr: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque {
    mem_mutex.lock();
    defer mem_mutex.unlock();

    const old_size = if (ptr != null) mem_allocations.?.get(@ptrToInt(ptr.?)).? else 0;
    const old_mem = if (old_size > 0)
        @ptrCast([*]align(mem_alignment) u8, @alignCast(mem_alignment, ptr))[0..old_size]
    else
        @as([*]align(mem_alignment) u8, undefined)[0..0];

    const new_mem = mem_allocator.?.realloc(old_mem, size) catch @panic("zstbi: out of memory");

    if (ptr != null) {
        const removed = mem_allocations.?.remove(@ptrToInt(ptr.?));
        std.debug.assert(removed);
    }

    mem_allocations.?.put(@ptrToInt(new_mem.ptr), size) catch @panic("zstbi: out of memory");

    return new_mem.ptr;
}

export fn zstbiFree(maybe_ptr: ?*anyopaque) callconv(.C) void {
    if (maybe_ptr) |ptr| {
        mem_mutex.lock();
        defer mem_mutex.unlock();

        const size = mem_allocations.?.fetchRemove(@ptrToInt(ptr)).?.value;
        const mem = @ptrCast([*]align(mem_alignment) u8, @alignCast(mem_alignment, ptr))[0..size];
        mem_allocator.?.free(mem);
    }
}

extern fn stbi_info(filename: [*:0]const u8, x: *c_int, y: *c_int, comp: *c_int) c_int;

extern fn stbi_load(
    filename: [*:0]const u8,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) ?[*]u8;

extern fn stbi_load_16(
    filename: [*:0]const u8,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) ?[*]u16;

extern fn stbi_loadf(
    filename: [*:0]const u8,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) ?[*]f32;

pub extern fn stbi_load_from_memory(
    buffer: [*]const u8,
    len: c_int,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) ?[*]u8;

extern fn stbi_image_free(image_data: ?[*]u8) void;

extern fn stbi_hdr_to_ldr_scale(scale: f32) void;
extern fn stbi_hdr_to_ldr_gamma(gamma: f32) void;
extern fn stbi_ldr_to_hdr_scale(scale: f32) void;
extern fn stbi_ldr_to_hdr_gamma(gamma: f32) void;

extern fn stbi_is_16_bit(filename: [*:0]const u8) c_int;
extern fn stbi_is_hdr(filename: [*:0]const u8) c_int;

extern fn stbi_set_flip_vertically_on_load(flag_true_if_should_flip: c_int) void;

test "zstbi.basic" {
    init(std.testing.allocator);
    defer deinit();
}
