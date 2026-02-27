const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
