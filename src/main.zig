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
    _ = c.SDL_SetAppMetadata("GameThingy", "0.0.0", "hansielneff.gamethingy");

    try sdlOk(c.SDL_Init(c.SDL_INIT_VIDEO));
    defer c.SDL_Quit();

    try sdlOk(c.SDL_Vulkan_LoadLibrary(null));
    defer c.SDL_Vulkan_UnloadLibrary();

    const loader: vk.PfnGetInstanceProcAddr = @ptrCast(c.SDL_Vulkan_GetVkGetInstanceProcAddr() orelse return sdlFail());
    const vkb = vk.BaseWrapper.load(loader);
    _ = vkb;

    //const instance = vkb.createInstance(p_create_info: *const InstanceCreateInfo, p_allocator: ?*const AllocationCallbacks);

    //const vki = vk.InstanceWrapper.load(instance, loader);

    // const window: *c.SDL_Window = c.SDL_CreateWindow("GameThingy", 1920, 1080, c.SDL_WINDOW_VULKAN) orelse return error.SdlError;
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
