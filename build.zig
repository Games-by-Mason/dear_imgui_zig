const std = @import("std");

const flags: []const []const u8 = &.{
    "-fno-exceptions",
    "-fno-rtti",
    "-fno-threadsafe-statics",
};

pub fn build(b: *std.Build) void {
    // Standard options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const optimize_external = switch (optimize) {
        .Debug => .ReleaseSafe,
        else => optimize,
    };

    // Get the upstream code
    const upstream = b.dependency("dear-imgui", .{});

    // Compile Dear ImGui as a static library
    const dear_imgui_lib = b.addStaticLibrary(.{
        .name = "dear_imgui",
        .target = target,
        .optimize = optimize_external,
    });
    dear_imgui_lib.addIncludePath(upstream.path(""));
    dear_imgui_lib.installHeadersDirectory(upstream.path(""), "", .{});
    dear_imgui_lib.linkLibC();
    dear_imgui_lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "imgui.cpp",
            "imgui_demo.cpp",
            "imgui_draw.cpp",
            "imgui_tables.cpp",
            "imgui_widgets.cpp",
        },
        .flags = flags,
    });
    dear_imgui_lib.addCSourceFiles(.{
        .root = b.path("src/cached"),
        .files = &.{"cimgui.cpp"},
        .flags = flags,
    });
    b.installArtifact(dear_imgui_lib);

    // Compile the Vulkan backend as a static library
    const dear_imgui_vulkan_lib = b.addStaticLibrary(.{
        .name = "dear_imgui_vulkan",
        .target = target,
        .optimize = optimize_external,
    });
    dear_imgui_vulkan_lib.linkLibrary(dear_imgui_lib);
    dear_imgui_vulkan_lib.addCSourceFile(.{ .file = upstream.path("backends/imgui_impl_vulkan.cpp"), .flags = flags });
    dear_imgui_vulkan_lib.addCSourceFile(.{ .file = b.path("src/cached/cimgui_impl_vulkan.cpp"), .flags = flags });
    dear_imgui_vulkan_lib.addIncludePath(upstream.path(""));
    dear_imgui_vulkan_lib.addIncludePath(upstream.path("backends"));
    const vulkan_headers = b.dependency("Vulkan-Headers", .{});
    dear_imgui_vulkan_lib.addIncludePath(vulkan_headers.path("include"));
    dear_imgui_vulkan_lib.defineCMacro("IMGUI_IMPL_VULKAN_NO_PROTOTYPES", "1"); // Assumed in generator
    dear_imgui_vulkan_lib.installHeadersDirectory(upstream.path("backends"), "", .{});
    dear_imgui_vulkan_lib.installHeadersDirectory(vulkan_headers.path("include"), "", .{});
    b.installArtifact(dear_imgui_vulkan_lib);

    // Compile the generator
    const generate_exe = b.addExecutable(.{
        .name = "generate",
        .root_source_file = b.path("src/generate.zig"),
        .target = target,
        .optimize = optimize,
    });

    const generate_cmd = b.addRunArtifact(generate_exe);
    generate_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        generate_cmd.addArgs(args);
    }

    const generate_step = b.step("generate", "Generate Zig bindings for Dear ImGui. This is done automatically as part of the build process, but is exposed as an option for debugging purposes.");
    generate_step.dependOn(&generate_cmd.step);

    // Generate Zig bindings for Dear ImGui
    const generate_dear_imgui = b.addRunArtifact(generate_exe);
    generate_dear_imgui.addFileArg(b.path("src/cached/cimgui.json"));
    const dear_imgui_zig = generate_dear_imgui.addOutputFileArg("dear_imgui.zig");
    generate_dear_imgui.addFileArg(b.path("src/templates/cimgui_prefix.zig.template"));
    generate_dear_imgui.addFileArg(b.path("src/templates/cimgui_postfix.zig.template"));
    const dear_imgui_zig_module = b.addModule("dear_imgui", .{
        .root_source_file = dear_imgui_zig,
        .target = target,
        .optimize = optimize,
    });
    dear_imgui_zig_module.linkLibrary(dear_imgui_lib);

    // Generate Zig bindings for the Vulkan backend
    const generate_vulkan = b.addRunArtifact(generate_exe);
    generate_vulkan.addFileArg(b.path("src/cached/cimgui_impl_vulkan.json"));
    const dear_imgui_vulkan_zig = generate_vulkan.addOutputFileArg("dear_imgui_impl_vulkan.zig");
    generate_vulkan.addFileArg(b.path("src/templates/impl_vulkan_prefix.zig.template"));
    generate_vulkan.addFileArg(b.path("src/templates/impl_vulkan_postfix.zig.template"));
    const dear_imgui_vulkan_zig_module = b.addModule("dear_imgui_vulkan", .{
        .root_source_file = dear_imgui_vulkan_zig,
        .target = target,
        .optimize = optimize,
    });
    dear_imgui_vulkan_zig_module.linkLibrary(dear_imgui_vulkan_lib);
}
