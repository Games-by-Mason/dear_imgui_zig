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
    const native_target = b.resolveTargetQuery(.{});
    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match the specified filters.",
    ) orelse &.{};

    const optimize_external = switch (optimize) {
        .Debug => .ReleaseSafe,
        else => optimize,
    };

    // Get the upstream code
    const upstream = b.dependency("dear-imgui", .{});

    // Compile Dear ImGui as a static library
    const dear_imgui_lib = b.addLibrary(.{
        .name = "dear_imgui",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize_external,
        }),
    });
    dear_imgui_lib.addIncludePath(upstream.path(""));
    dear_imgui_lib.installHeadersDirectory(upstream.path("."), "", .{});
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
        .files = &.{"dcimgui.cpp"},
        .flags = flags,
    });
    b.installArtifact(dear_imgui_lib);

    // Compile the Vulkan backend as a static library
    const dear_imgui_vulkan_lib = b.addLibrary(.{
        .name = "dear_imgui_vulkan",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize_external,
        }),
    });
    dear_imgui_vulkan_lib.linkLibrary(dear_imgui_lib);
    dear_imgui_vulkan_lib.addCSourceFile(.{ .file = upstream.path("backends/imgui_impl_vulkan.cpp"), .flags = flags });
    dear_imgui_vulkan_lib.addCSourceFile(.{ .file = b.path("src/cached/dcimgui_impl_vulkan.cpp"), .flags = flags });
    dear_imgui_vulkan_lib.addIncludePath(upstream.path(""));
    dear_imgui_vulkan_lib.addIncludePath(upstream.path("backends"));
    const vulkan_headers = b.dependency("Vulkan-Headers", .{});
    dear_imgui_vulkan_lib.addIncludePath(vulkan_headers.path("include"));
    dear_imgui_vulkan_lib.root_module.addCMacro("IMGUI_IMPL_VULKAN_NO_PROTOTYPES", "1"); // Assumed in generator
    dear_imgui_vulkan_lib.installHeadersDirectory(upstream.path("backends"), "", .{});
    dear_imgui_vulkan_lib.installHeadersDirectory(vulkan_headers.path("include"), "", .{});
    b.installArtifact(dear_imgui_vulkan_lib);

    // Compile the SDL3 backend as a static library
    const dear_imgui_sdl3_lib = b.addLibrary(.{
        .name = "dear_imgui_vulkan",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize_external,
        }),
    });
    dear_imgui_sdl3_lib.linkLibrary(dear_imgui_lib);
    dear_imgui_sdl3_lib.addCSourceFile(.{ .file = upstream.path("backends/imgui_impl_sdl3.cpp"), .flags = flags });
    dear_imgui_sdl3_lib.addCSourceFile(.{ .file = b.path("src/cached/dcimgui_impl_sdl3.cpp"), .flags = flags });
    dear_imgui_sdl3_lib.addIncludePath(upstream.path(""));
    dear_imgui_sdl3_lib.addIncludePath(upstream.path("backends"));
    const sdl = b.dependency("sdl", .{});
    dear_imgui_sdl3_lib.addIncludePath(sdl.path("include"));
    // dear_imgui_sdl3_lib.root_module.addCMacro("IMGUI_IMPL_VULKAN_NO_PROTOTYPES", "1"); // Assumed in generator // XXX: ...
    dear_imgui_sdl3_lib.installHeadersDirectory(upstream.path("backends"), "", .{});
    // dear_imgui_sdl3_lib.installHeadersDirectory(vulkan_headers.path("include"), "", .{}); // XXX: ...
    b.installArtifact(dear_imgui_sdl3_lib);

    // Compile the generator
    const generate_exe = b.addExecutable(.{
        .name = "generate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generate.zig"),
            .target = native_target,
            .optimize = optimize,
        }),
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
    generate_dear_imgui.addFileArg(b.path("src/cached/dcimgui.json"));
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
    generate_vulkan.addFileArg(b.path("src/cached/dcimgui_impl_vulkan.json"));
    const dear_imgui_vulkan_zig = generate_vulkan.addOutputFileArg("dear_imgui_impl_vulkan.zig");
    generate_vulkan.addFileArg(b.path("src/templates/impl_vulkan_prefix.zig.template"));
    generate_vulkan.addFileArg(b.path("src/templates/impl_vulkan_postfix.zig.template"));
    const dear_imgui_vulkan_zig_module = b.addModule("dear_imgui_vulkan", .{
        .root_source_file = dear_imgui_vulkan_zig,
        .target = target,
        .optimize = optimize,
    });
    dear_imgui_vulkan_zig_module.linkLibrary(dear_imgui_vulkan_lib);
    dear_imgui_vulkan_zig_module.addImport("dear_imgui", dear_imgui_zig_module);

    // Generate Zig bindings for the SDL3 backend
    const generate_sdl3 = b.addRunArtifact(generate_exe);
    generate_sdl3.addFileArg(b.path("src/cached/dcimgui_impl_sdl3.json"));
    const dear_imgui_sdl3_zig = generate_sdl3.addOutputFileArg("dear_imgui_impl_sdl3.zig");
    generate_sdl3.addFileArg(b.path("src/templates/impl_sdl3_prefix.zig.template"));
    generate_sdl3.addFileArg(b.path("src/templates/impl_sdl3_postfix.zig.template"));
    const dear_imgui_sdl3_zig_module = b.addModule("dear_imgui_sdl3", .{
        .root_source_file = dear_imgui_sdl3_zig,
        .target = target,
        .optimize = optimize,
    });
    dear_imgui_sdl3_zig_module.linkLibrary(dear_imgui_sdl3_lib);

    const tests = b.addTest(.{
        .root_module = dear_imgui_zig_module,
        .filters = test_filters,
    });
    const run_lib_unit_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const docs = tests.getEmittedDocs();
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs,
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Build the docs");
    docs_step.dependOn(&install_docs.step);
}
