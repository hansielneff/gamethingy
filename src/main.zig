const std = @import("std");

const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", {});
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_main.h");
});
const vk = @import("vulkan");

const log_app = std.log.scoped(.app);
const log_sdl = std.log.scoped(.sdl);

const app_name = "GameThingy";

pub const SdlError = error{SdlFailed};
inline fn sdlFail() SdlError {
    const msg_ptr = c.SDL_GetError();
    const msg = if (msg_ptr != null) std.mem.span(msg_ptr) else "SDL error (null)";
    log_sdl.err("{s}", .{msg});
    return error.SdlFailed;
}

inline fn sdlOk(ok: bool) SdlError!void {
    if (!ok) return sdlFail();
}

pub fn entrypoint() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = c.SDL_SetAppMetadata(app_name, "0.0.0", "hansielneff.gamethingy");
    try sdlOk(c.SDL_Init(c.SDL_INIT_VIDEO));
    defer c.SDL_Quit();
    try sdlOk(c.SDL_Vulkan_LoadLibrary(null));
    defer c.SDL_Vulkan_UnloadLibrary();

    const loader: vk.PfnGetInstanceProcAddr = @ptrCast(c.SDL_Vulkan_GetVkGetInstanceProcAddr() orelse return sdlFail());
    const vkb = vk.BaseWrapper.load(loader);

    var extension_names: std.ArrayList([*:0]const u8) = .empty;
    defer extension_names.deinit(allocator);
    try extension_names.append(allocator, vk.extensions.ext_debug_utils.name);
    try extension_names.append(allocator, vk.extensions.khr_portability_enumeration.name);
    try extension_names.append(allocator, vk.extensions.khr_get_physical_device_properties_2.name);
    var sdl_exts_count: u32 = 0;
    const sdl_exts = c.SDL_Vulkan_GetInstanceExtensions(&sdl_exts_count);
    try extension_names.appendSlice(allocator, @ptrCast(sdl_exts[0..sdl_exts_count]));
    const instance_handle = try vkb.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 0).toU32(),
            .engine_version = vk.makeApiVersion(0, 0, 0, 0).toU32(),
            .api_version = vk.API_VERSION_1_4.toU32(),
        },
        .enabled_extension_count = @intCast(extension_names.items.len),
        .pp_enabled_extension_names = extension_names.items.ptr,
    }, null);

    const vki = vk.InstanceWrapper.load(instance_handle, loader);
    const instance = vk.InstanceProxy.init(instance_handle, &vki);
    defer instance.destroyInstance(null);

    var physical_device_index: u32 = 0;
    const physical_devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(physical_devices);
    for (physical_devices, 0..) |physical_device, i| {
        var props: vk.PhysicalDeviceProperties2 = .{ .properties = undefined };
        instance.getPhysicalDeviceProperties2(physical_device, &props);
        if (props.properties.device_type == .discrete_gpu) {
            physical_device_index = @intCast(i);
            log_app.info("Selected device: {s}", .{props.properties.device_name});
            break;
        }
    } else {
        @panic("No discrete GPU found!");
    }

    var queue_family_index: u32 = 0;
    const queue_family_properties = try instance.getPhysicalDeviceQueueFamilyProperties2Alloc(physical_devices[physical_device_index], allocator);
    defer allocator.free(queue_family_properties);
    for (queue_family_properties, 0..) |props, i| {
        if (props.queue_family_properties.queue_flags.graphics_bit) {
            queue_family_index = @intCast(i);
            break;
        }
    } else {
        unreachable; // Vulkan impl must provide a queue family with graphics support
    }
    if (!c.SDL_Vulkan_GetPresentationSupport(@ptrFromInt(@intFromEnum(instance.handle)), @ptrFromInt(@intFromEnum(physical_devices[physical_device_index])), queue_family_index)) {
        @panic("Selected graphics queue family doesn't support presentation");
    }

    // const window: *c.SDL_Window = c.SDL_CreateWindow(app_name, 1920, 1080, c.SDL_WINDOW_VULKAN) orelse return error.SdlError;
    // const surface: vk.SurfaceKHR = undefined;
    // c.SDL_Vulkan_CreateSurface(window, instance, null, &surface);
}

pub fn appMain(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;
    entrypoint() catch return -1;
    return 0;
}

pub fn main() u8 {
    const rc = c.SDL_RunApp(0, null, appMain, null);
    return if (rc < 0) 1 else @intCast(@min(rc, 255));
}
