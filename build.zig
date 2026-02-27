const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vk_wsi = b.option([]const u8, "vk_wsi", "Linux WSI: wayland|xcb|xlib") orelse "wayland";

    const exe = b.addExecutable(.{
        .name = "gamethingy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const dep_sdl = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const lib_sdl = dep_sdl.artifact("SDL3");
    exe.root_module.linkLibrary(lib_sdl);

    const dep_vulkan_headers = b.dependency("vulkan_headers", .{});
    const vk_xml = dep_vulkan_headers.path("registry/vk.xml");
    const dep_vulkan = b.dependency("vulkan", .{ .registry = vk_xml });
    const mod_vulkan = dep_vulkan.module("vulkan-zig");
    exe.root_module.addImport("vulkan", mod_vulkan);

    const dep_vulkan_profiles = b.dependency("vulkan_profiles", .{});
    const vp_gen_script = dep_vulkan_profiles.path("scripts/gen_profiles_solution.py");
    const vp_gen = b.addSystemCommand(&.{"python3"});
    vp_gen.addFileArg(vp_gen_script);
    vp_gen.addArg("--registry");
    vp_gen.addFileArg(vk_xml);
    vp_gen.addArg("--input");
    vp_gen.addDirectoryArg(b.path("profiles"));
    vp_gen.addArg("--output-library-src");
    const vp_src_dir = vp_gen.addOutputDirectoryArg("vkprofiles-src");
    vp_gen.addArg("--output-library-inc");
    const vp_inc_dir = vp_gen.addOutputDirectoryArg("vkprofiles-inc");
    const fixed_inc = b.addWriteFiles();
    _ = fixed_inc.addCopyFile(vp_inc_dir.path(b, "vulkan_profiles.h"), "vulkan/vulkan_profiles.h");
    const fixed_inc_dir = fixed_inc.getDirectory();
    exe.root_module.addIncludePath(fixed_inc_dir);
    exe.root_module.addIncludePath(dep_vulkan_headers.path("include"));
    const wsi_macro = getWsiMacroForTarget(target.result.os.tag, vk_wsi);
    exe.root_module.addCMacro(wsi_macro, "1");
    exe.root_module.addCSourceFile(.{
        .file = vp_src_dir.path(b, "vulkan_profiles.cpp"),
        .flags = &.{
            "-std=c++17",
            "-DVP_USE_OBJECT=1",
            b.fmt("-D{s}=1", .{wsi_macro}),
        },
    });
    exe.root_module.link_libcpp = true;

    const target_spirv = b.resolveTargetQuery(.{
        .cpu_arch = .spirv32,
        .os_tag = .vulkan,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        .ofmt = .spirv,
    });
    const shaders = @import("shaders.zon");
    inline for (shaders) |stem| {
        const import_name = b.fmt("shader_{s}", .{stem});
        const src_path = b.fmt("src/shaders/{s}.zig", .{stem});
        const shader = b.addObject(.{
            .name = import_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(src_path),
                .target = target_spirv,
                .optimize = .ReleaseFast,
            }),
            .use_llvm = false,
            .use_lld = false,
        });
        exe.root_module.addAnonymousImport(import_name, .{
            .root_source_file = shader.getEmittedBin(),
        });
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn getWsiMacroForTarget(target_tag: std.Target.Os.Tag, vk_wsi: []const u8) []const u8 {
    return switch (target_tag) {
        .windows => "VK_USE_PLATFORM_WIN32_KHR",
        .macos => "VK_USE_PLATFORM_METAL_EXT",
        .linux => {
            // zig fmt: off
            return if (std.mem.eql(u8, vk_wsi, "wayland")) "VK_USE_PLATFORM_WAYLAND_KHR"
            else if (std.mem.eql(u8, vk_wsi, "xcb")) "VK_USE_PLATFORM_XCB_KHR"
            else if (std.mem.eql(u8, vk_wsi, "xlib")) "VK_USE_PLATFORM_XLIB_KHR"
            else @panic("invalid -Dvk_wsi (use wayland|xcb|xlib)");
            // zig fmt: on
        },
        else => @panic("unsupported target platform"),
    };
}
