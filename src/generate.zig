const std = @import("std");
const Allocator = std.mem.Allocator;

const DeclarationKind = enum {
    normal,
    @"opaque",
    import, // Assumed to be normal, but external
};

const Declarations = std.StringArrayHashMap(DeclarationKind);
const max_size = 5000000;

// The header type we'll parse from JSON. Fields are only included as needed.
// practice, etc.
const Header = struct {
    defines: []Define,
    typedefs: []Typedef,
    enums: []Enum,
    structs: []const Struct,
    functions: []Function,

    const Define = struct {
        name: []const u8,
        content: ?[]const u8 = null,
        is_internal: bool,
        conditionals: []const Conditional = &.{},
    };

    const Typedef = struct {
        name: []const u8,
        type: Type,
        conditionals: []const Conditional = &.{},
    };

    const Enum = struct {
        name: []const u8,
        storage_type: StorageType = .{ .declaration = .int },
        is_flags_enum: bool,
        elements: []const Element,
        is_internal: bool,
        conditionals: []const Conditional = &.{},

        const Element = struct {
            name: []const u8,
            value: i64,
            is_count: bool,
            is_internal: bool,
            conditionals: []const Conditional = &.{},
        };

        const StorageType = struct {
            declaration: enum { int, ImU8 },
        };
    };

    const Struct = struct {
        name: []const u8,
        is_anonymous: bool,
        kind: enum { @"struct", @"union" },
        forward_declaration: bool,
        fields: []const Field,
        conditionals: []const Conditional = &.{},

        const Field = struct {
            name: []const u8,
            is_anonymous: bool,
            type: Type,
            width: ?usize = null,
            default_value: ?std.json.Value = null,
            conditionals: []const Conditional = &.{},
        };
    };

    const Function = struct {
        original_class: ?[]const u8 = null,
        name: []const u8,
        arguments: []const Argument = &.{},
        return_type: Type,
        conditionals: []const Conditional = &.{},

        const Argument = struct {
            type: ?Type = null,
            is_varargs: bool,
            is_instance_pointer: bool,
            default_value: ?[]const u8 = null,
        };
    };

    // `dear_bindings` doesn't parse these for us, it just forwards the c preprocessor strings.
    // This is a whitelist of the current values so that we can react appropriately as new values
    // are added.
    const Conditional = struct {
        condition: enum { ifdef, ifndef, @"if", ifnot },
        expression: enum {
            IMGUI_DISABLE_OBSOLETE_FUNCTIONS,
            IMGUI_DISABLE_OBSOLETE_KEYIO,
            IMGUI_OVERRIDE_DRAWVERT_STRUCT_LAYOUT,
            IMGUI_USE_WCHAR32,
            ImTextureID,
            ImDrawIdx,
            ImDrawCallback,
            CIMGUI_API,
            CIMGUI_IMPL_API,
            @"defined(_MSC_VER)&&!defined(__clang__)&&!defined(__INTEL_COMPILER)&&!defined(IMGUI_DEBUG_PARANOID)",
            @"defined(IMGUI_DISABLE_OBSOLETE_FUNCTIONS)&&!defined(IMGUI_DISABLE_OBSOLETE_KEYIO)",
            IMGUI_DEFINE_MATH_OPERATORS,
            IM_COL32_R_SHIFT,
            IMGUI_USE_BGRA_PACKED_COLOR,
            IM_DRAWLIST_TEX_LINES_WIDTH_MAX,
            @"defined(IMGUI_DISABLE_METRICS_WINDOW)&&!defined(IMGUI_DISABLE_OBSOLETE_FUNCTIONS)&&!defined(IMGUI_DISABLE_DEBUG_TOOLS)",
            @"defined(IMGUI_HAS_IMSTR)",
            IMGUI_HAS_IMSTR,
            @"defined(IMGUI_IMPL_VULKAN_NO_PROTOTYPES)&&!defined(VK_NO_PROTOTYPES)",
            @"defined(VK_USE_PLATFORM_WIN32_KHR)&&!defined(NOMINMAX)",
            @"defined(VK_VERSION_1_3)|| defined(VK_KHR_dynamic_rendering)",
            IMGUI_IMPL_VULKAN_HAS_DYNAMIC_RENDERING,
            IMGUI_DISABLE_DEBUG_TOOLS,
        },
    };

    const Type = struct {
        type_details: ?Details = null,
        description: Description,

        const Details = struct {
            flavour: enum { function_pointer },
            arguments: []const struct {
                type: Type,
                is_array: bool,
                is_varargs: bool,
            },
            return_type: *Type,
        };

        const Description = struct {
            kind: enum { Type, Function, Array, Pointer, Builtin, User },
            storage_classes: []const enum { @"const" } = &.{},
            inner_type: ?*Description = null,
            bounds: ?[]const u8 = null, // Literal or variable
            builtin_type: ?Builtin = null,
            name: ?[]const u8 = null,

            const Builtin = enum {
                void,
                char,
                unsigned_char,
                short,
                unsigned_short,
                int,
                unsigned_int,
                long,
                unsigned_long,
                long_long,
                unsigned_long_long,
                float,
                double,
                long_double,
                bool,
            };
        };
    };
};

pub fn main() !void {
    // Allocator and command line args
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = false,
    }){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    std.debug.assert(args.skip());
    const in_path = args.next().?;
    const out_path = args.next().?;
    const prefix_path = args.next();
    const postfix_path = args.next();
    std.debug.assert(args.next() == null);

    const out = try std.fs.cwd().createFile(out_path, .{});
    defer out.close();
    var buf = std.io.bufferedWriter(out.writer());
    const writer = buf.writer();

    // Write the prefix
    if (prefix_path) |p| {
        const prefix_source = try std.fs.cwd().readFileAlloc(allocator, p, max_size);
        defer allocator.free(prefix_source);
        try writer.writeAll(prefix_source);
        try writer.writeAll("\n// End of prefix\n\n");
    }

    // Write the source
    {
        const source = try std.fs.cwd().readFileAlloc(allocator, in_path, max_size);
        defer allocator.free(source);

        const header = try std.json.parseFromSlice(Header, allocator, source, .{
            .ignore_unknown_fields = true,
        });
        defer header.deinit();

        // We need the list of declarations up front.
        var declarations = try getDeclarations(allocator, &header.value);
        defer declarations.deinit();

        // Write all defines as private constants.
        try writeDefines(writer, &header.value);

        // Write all typedefs as private constants.
        try writeTypedefs(writer, &header.value, &declarations);

        // Write all cimgui functions as private extern functions.
        try writeExternFunctions(writer, &header.value, &declarations);

        // Alias cimgui free functions under Zig friendly names.
        try writeFreeFunctions(writer, &header.value);

        // Get a list of cimgui methods. These were already written as externs, and can be aliased
        // when we write their respective types.
        var methods = try Methods.get(allocator, &header.value);
        defer methods.deinit();

        // Write cimgui enums as Zig enums.
        try writeEnums(allocator, writer, &header.value);

        // Write cimgui structs as Zig structs and unions.
        try writeStructs(writer, &header.value, &declarations, &methods);

        // Write helpers used by the other generated code.
        try writeHelpers(writer);
    }

    // Write the postfix
    if (postfix_path) |p| {
        const postfix_source = try std.fs.cwd().readFileAlloc(allocator, p, max_size);
        defer allocator.free(postfix_source);
        try writer.writeAll("\n// Start of postfix\n\n");
        try writer.writeAll(postfix_source);
    }

    // Flush and exit
    try buf.flush();
}

fn getDeclarations(allocator: Allocator, header: *const Header) !Declarations {
    var declarations = Declarations.init(allocator);
    errdefer declarations.deinit();
    for (header.structs) |ty| {
        if (skip(ty.conditionals)) continue;

        var kind: DeclarationKind = .normal;
        if (ty.forward_declaration) {
            if (std.mem.eql(u8, "ImDrawData", ty.name)) {
                // Normally if a type has the forward declaration flag set, we want to mark it as
                // opaque. In the case of draw data, however, the ImGui backends opt to forward
                // declare it instead of include it. If we were to mark it as opaque here, it would
                // be opaque in the backends but an actual type in imgui.
                //
                // Instead, Zig ports of the backends should import DrawData.
                kind = .import;
            } else {
                kind = .@"opaque";
            }
        } else if (ty.kind == .@"struct") {
            for (ty.fields) |field| if (field.width != null) {
                // Treat packed structs as opaque.
                //
                // We *could* write out the Zig code to pack them by passing the widths in when
                // writing the type (and overwriting number types with the actual width, asserting
                // otherwise.)
                //
                // However, we'd need to decide the correct backing type for the packed struct to
                // make it compatible with C. I'm also not 100% what the guarantees are for packed
                // struct layout in C.
                kind = .@"opaque";
                break;
            };
        }

        const trimmed = std.mem.trimRight(u8, ty.name, "_");
        try declarations.put(trimmed, kind);
    }

    for (header.enums) |e| {
        if (e.is_internal) continue;
        if (skip(e.conditionals)) continue;

        const trimmed = std.mem.trimRight(u8, e.name, "_");
        try declarations.put(trimmed, .normal);
    }

    return declarations;
}

fn writeDefines(writer: anytype, header: *const Header) !void {
    for (header.defines) |define| {
        if (define.is_internal) continue;
        if (skip(define.conditionals)) continue;
        if (define.content) |content| {
            try writer.print("const {s} = {s};\n", .{ define.name, content });
        }
    }
}

fn writeTypedefs(writer: anytype, header: *const Header, declarations: *const Declarations) !void {
    for (header.typedefs) |typedef| {
        // Skip typedefs skipped by the preprocessor
        if (skip(typedef.conditionals)) continue;

        // Skip duplicate declarations (e.g. naming enums as ints in C)
        if (declarations.contains(typedef.name)) continue;

        // Write the typedef
        try writer.writeAll("const ");
        try writeTypeName(writer, typedef.name);
        try writer.writeAll(" = ");
        try writeType(writer, typedef.type, declarations, .{});
        try writer.writeAll(";\n");
    }
}

fn writeExternFunctions(
    writer: anytype,
    header: *const Header,
    declarations: *const Declarations,
) !void {
    for (header.functions) |function| {
        if (skip(function.conditionals)) continue;
        if (argsContainsVaList(function.arguments)) continue;

        try writer.print("extern fn {s}(", .{function.name});
        for (function.arguments) |argument| {
            if (argument.type) |ty| {
                std.debug.assert(!argument.is_varargs);
                try writeType(writer, ty, declarations, .{
                    .is_instance_pointer = argument.is_instance_pointer,
                    .is_argument = true,
                    .default_null = if (argument.default_value) |d| std.mem.eql(u8, d, "NULL") else false,
                });
            } else {
                std.debug.assert(argument.is_varargs);
                try writer.writeAll("...");
            }
            try writer.writeAll(", ");
        }
        try writer.writeAll(") callconv(.C) ");
        try writeType(writer, function.return_type, declarations, .{ .is_result = true });
        try writer.writeAll(";\n");
    }
}

fn argsContainsVaList(arguments: []const Header.Function.Argument) bool {
    for (arguments) |argument| {
        if (argument.type) |ty| {
            if (ty.description.name) |name| {
                if (std.mem.eql(u8, name, "va_list")) return true;
            }
        }
    }
    return false;
}

fn writeFreeFunctions(writer: anytype, header: *const Header) !void {
    for (header.functions) |function| {
        if (skip(function.conditionals)) continue;
        if (function.original_class != null) continue;
        if (argsContainsVaList(function.arguments)) continue;

        try writer.writeAll("pub const ");
        try writeFunctionName(writer, function.name);
        try writer.print(" = {s};\n", .{function.name});
    }
}

const Methods = struct {
    types: std.StringArrayHashMap(std.ArrayList([]const u8)),

    fn get(allocator: Allocator, header: *const Header) !Methods {
        // Initialize an empty method list for each type
        var types = std.StringArrayHashMap(std.ArrayList([]const u8)).init(allocator);
        errdefer types.deinit();
        errdefer for (types.values()) |methods| {
            methods.deinit();
        };
        for (header.structs) |ty| {
            const methods = std.ArrayList([]const u8).init(allocator);
            errdefer methods.deinit();
            try types.put(ty.name, methods);
        }

        // Fill in the method lists
        for (header.functions) |function| {
            if (skip(function.conditionals)) continue;
            if (argsContainsVaList(function.arguments)) continue;

            if (function.original_class) |class| {
                const methods = types.getPtr(class).?;
                try methods.append(function.name);
            }
        }

        return .{ .types = types };
    }

    fn deinit(self: *Methods) void {
        for (self.types.values()) |methods| {
            methods.deinit();
        }
        self.types.deinit();
        self.* = undefined;
    }
};

fn writeEnums(allocator: Allocator, writer: anytype, header: *const Header) !void {
    for (header.enums) |e| {
        if (e.is_internal) continue;
        if (skip(e.conditionals)) continue;

        try writer.writeAll("pub const ");
        try writeTypeName(writer, e.name);
        try writer.writeAll(" = ");

        if (e.is_flags_enum) {
            try writeFlagsEnum(writer, e);
        } else {
            try writeNormalEnum(allocator, writer, e);
        }
    }
}

fn writeFlagsEnum(writer: anytype, e: Header.Enum) !void {
    const backing, const backing_bits = switch (e.storage_type.declaration) {
        .int => .{ "c_int", @typeInfo(c_int).int.bits },
        .ImU8 => .{ "u8", 8 },
    };
    try writer.print("packed struct({s}) {{\n", .{backing});
    var current_offset: usize = 0;
    var padding_i: usize = 0;
    for (e.elements) |element| {
        // Skip internal elements, and elements discarded by preprocessor
        if (skip(element.conditionals)) continue;
        if (element.is_internal) continue;
        if (element.value == 0) continue;

        // Calculate the offset of this element
        const offset = std.math.log2(@as(usize, @intCast(element.value)));

        // Sometimes at the end of flag sets, elements are defined that are combinations of
        // existing flags. Skip these--the only reasonable representation would be constants, but
        // they're hard to compose in Zig so it's not worth it.
        if (offset < current_offset) {
            continue;
        }

        // Add padding to get this element to the correct offset
        const padding = offset - current_offset;
        if (padding > 0) {
            try writer.print("    __padding{}: u{} = 0,\n", .{ padding_i, padding });
            padding_i += 1;
            current_offset = offset;
        }

        // Write the element
        try writer.writeAll("    ");
        try writeElementName(writer, e.name, element.name);
        try writer.writeAll(": bool = false,\n");
        current_offset += 1;
    }

    // Add padding at end to make total type the correct size
    const padding = backing_bits - current_offset;
    if (padding > 0) {
        try writer.print("    __padding{}: u{} = 0,\n", .{ padding_i, padding });
    }

    try writer.writeAll("};\n");
}

fn writeNormalEnum(allocator: Allocator, writer: anytype, e: Header.Enum) !void {
    var values = std.AutoArrayHashMap(i64, void).init(allocator);
    defer values.deinit();

    try writer.writeAll("enum(");
    switch (e.storage_type.declaration) {
        .int => try writer.writeAll("c_int"),
        .ImU8 => try writer.writeAll("u8"),
    }
    try writer.writeAll(") {\n");

    // Write elements
    for (e.elements) |element| {
        // Skip internal and count
        if (element.is_internal) continue;
        if (element.is_count) continue;
        if (skip(element.conditionals)) continue;

        // We skip duplicate values, these are sometimes present e.g. in the keys enum which
        // contains the mods enum and therefore two "none" options that are identical.
        if (values.contains(element.value)) continue;
        try values.put(element.value, {});

        // Write the element
        try writer.writeAll("    ");
        try writeElementName(writer, e.name, element.name);
        try writer.print(" = {},\n", .{element.value});
    }

    // Write constants since they're used internally, but keep them private
    for (e.elements) |element| {
        if (element.is_count) {
            try writer.writeAll("    const ");
            try writeElementName(writer, e.name, element.name);
            try writer.print(" = {};\n", .{element.value});
        }
    }

    try writer.writeAll("};\n");
}

fn writeStructs(
    writer: anytype,
    header: *const Header,
    declarations: *const Declarations,
    methods: *const Methods,
) !void {
    for (header.structs) |ty| {
        // Skip structs skipped by the preprocessor. We don't skip structs marked as internal,
        // because many of these appear to be generally useful (it may be set incorrectly in the
        // JSON?)
        if (skip(ty.conditionals)) continue;

        // Skip imported decls
        const decl_kind = declarations.get(ty.name).?;
        if (decl_kind == .import) continue;

        // Write the struct
        try writer.writeAll("pub const ");
        try writeTypeName(writer, ty.name);
        try writer.writeAll(" = ");

        // If we're opaque, don't try to fill out the struct fields
        if (decl_kind == .@"opaque") {
            try writer.writeAll("opaque {};\n");
            continue;
        }

        // Declare the struct or union
        switch (ty.kind) {
            .@"struct" => try writer.writeAll("extern struct {\n"),
            .@"union" => try writer.writeAll("extern union {\n"),
        }

        // Fill in the fields
        for (ty.fields) |field| {
            // Skip fields skipped by the preprocessor.
            if (skip(field.conditionals)) continue;

            // Not yet used, but when it is we want to start using it. Safe to disable this assert
            // if you're just trying to get things working with a different version.
            if (field.default_value != null) @panic("unimplemented");

            // Write the field.
            try writer.writeAll("    ");
            if (field.is_anonymous) {
                try writer.writeAll("data");
            } else {
                try writeFieldName(writer, field.name);
            }
            try writer.writeAll(": ");
            try writeType(writer, field.type, declarations, .{});
            try writer.writeAll(",\n");
        }

        // Alias all relevant methods into the type.
        const method_names = methods.types.getPtr(ty.name).?;
        for (method_names.items) |name| {
            try writer.writeAll("    pub const ");
            try writeFunctionName(writer, name[ty.name.len + 1 ..]);
            try writer.print(" = {s};\n", .{name});
        }

        try writer.writeAll("};\n");
    }
}

fn writeHelpers(writer: anytype) !void {
    try writer.writeAll(
        \\fn toUsize(v: anytype) usize {
        \\    if (@typeInfo(@TypeOf(v)) == .@"enum") return @intFromEnum(v);
        \\    return @intCast(v);
        \\}
        \\
    );
}

// Type hints aren't required, but they help us figure out the best pointer types to use.
const WriteTypeHints = packed struct {
    is_instance_pointer: bool = false,
    is_argument: bool = false,
    default_null: bool = false,
    is_result: bool = false,
};

// Write a cimgui type as a Zig type.
fn writeType(
    writer: anytype,
    ty: Header.Type,
    declarations: *const Declarations,
    hints: WriteTypeHints,
) @TypeOf(writer).Error!void {
    // Handle function pointers which are stored separately.
    if (ty.type_details) |details| switch (details.flavour) {
        .function_pointer => return writeFunctionPointer(writer, details, declarations),
    };

    // Handle all other types
    switch (ty.description.kind) {
        .Builtin => return writeBuiltinType(writer, ty.description.builtin_type.?),
        .Array => return writeArrayType(writer, ty.description, declarations),
        .Pointer => return writePointerType(writer, ty, declarations, hints),
        .User => try writeTypeName(writer, ty.description.name.?),
        .Type, .Function => @panic("unimplemented"),
    }
}

fn writeFunctionPointer(
    writer: anytype,
    details: Header.Type.Details,
    declarations: *const Declarations,
) !void {
    try writer.writeAll("*const fn(");
    for (details.arguments) |argument| {
        try writeType(writer, argument.type, declarations, .{});
        try writer.writeAll(", ");
    }
    try writer.writeAll(") callconv(.C) ");
    try writeType(writer, details.return_type.*, declarations, .{});
}

fn writeBuiltinType(writer: anytype, builtin_type: Header.Type.Description.Builtin) !void {
    switch (builtin_type) {
        .void => try writer.writeAll("void"),
        .char, .unsigned_char => try writer.writeAll("u8"),
        .short => try writer.writeAll("c_short"),
        .unsigned_short => try writer.writeAll("c_ushort"),
        .int => try writer.writeAll("c_int"),
        .unsigned_int => try writer.writeAll("c_uint"),
        .long => try writer.writeAll("c_long"),
        .unsigned_long => try writer.writeAll("c_ulong"),
        .long_long => try writer.writeAll("c_longlong"),
        .unsigned_long_long => try writer.writeAll("c_ulonglong"),
        .float => try writer.writeAll("f32"),
        .double => try writer.writeAll("f64"),
        .long_double => try writer.writeAll("c_longdouble"),
        .bool => try writer.writeAll("bool"),
    }
}

fn writeArrayType(
    writer: anytype,
    description: Header.Type.Description,
    declarations: *const Declarations,
) !void {
    if (description.bounds) |bounds| {
        try writeArrayBounds(writer, bounds);
    } else {
        try writer.writeAll("[*]");
    }
    try writeType(
        writer,
        .{ .description = description.inner_type.?.* },
        declarations,
        .{},
    );
}

// Array bounds sometimes include expressions, so we need to tokenize them and convert the
// expressions to Zig syntax.
fn writeArrayBounds(writer: anytype, bounds: []const u8) !void {
    try writer.writeByte('[');
    var token_start: usize = 0;
    while (token_start < bounds.len) {
        // Calculate token start
        if (bounds[token_start] == ' ') {
            token_start += 1;
            continue;
        }

        // Special handling for one character tokens
        switch (bounds[token_start]) {
            '(' => {
                const token = bounds[token_start .. token_start + 1];
                token_start += 1;
                try writer.writeAll(token);
                continue;
            },
            '+', '/' => {
                const token = bounds[token_start .. token_start + 1];
                token_start += 1;
                try writer.print(" {s} ", .{token});
                continue;
            },
            else => {},
        }

        // Calculate token end
        var token_end = token_start + 1;
        while (token_end < bounds.len) : (token_end += 1) {
            switch (bounds[token_end]) {
                ' ', '+', ')', '/' => break,
                else => {},
            }
        }
        const token = bounds[token_start..token_end];
        token_start = token_end;

        // As of the time of writing, tokens here are either numbers or enum values.
        if (std.mem.indexOfScalar(u8, token, '_')) |underscore| {
            // If it's all uppercase, it's a define. Otherwise it's an enum.
            const is_define = for (token) |c| {
                switch (c) {
                    'a'...'z' => break false,
                    else => {},
                }
            } else true;

            if (is_define) {
                try writer.writeAll(token);
            } else {
                try writer.writeAll("toUsize(");
                const type_name = token[0..underscore];
                try writeTypeName(writer, type_name);
                try writer.writeByte('.');
                try writeElementName(writer, type_name, token);
                try writer.writeAll(")");
            }
        } else {
            // Otherwise, just write the value as is.
            try writer.writeAll(token);
        }
    }
    try writer.writeByte(']');
}

fn writePointerType(
    writer: anytype,
    ty: Header.Type,
    declarations: *const Declarations,
    hints: WriteTypeHints,
) !void {
    // Check if we're a pointer to an opaque type
    var is_opaque = false;
    if (ty.description.inner_type.?.name) |name| {
        if (declarations.get(name)) |kind| {
            is_opaque = kind == .@"opaque";
        }
    }

    // Check if we're a pointer to void
    const is_void = ty.description.inner_type.?.builtin_type == .void;

    // Check if we're a string
    const is_string = b: {
        if (ty.description.inner_type.?.builtin_type != .char) break :b false;
        for (ty.description.inner_type.?.*.storage_classes) |storage_class| switch (storage_class) {
            .@"const" => break :b true,
        };
        break :b false;
    };

    // Use the hints to decide what kind of pointer we are
    if (is_string) {
        // We currently write all strings as c pointers since some are null terminated, and some are
        // not.
        try writer.writeAll("[*c]");
    } else if (hints.is_instance_pointer) {
        // We assume all instance pointers do *not* allow null.
        std.debug.assert(!hints.default_null);
        try writer.writeByte('*');
    } else if (hints.is_argument) {
        // Arguments are assumed to be single value pointers, because many value pointers when
        // passed as arguments get marked as arrays and handled separately from pointers.
        if (hints.default_null) {
            // If the default value is set to null, we must be nullable. Otherwise we conservatively
            // assume null is not allowed, which tends to be correct in practice more often than
            // not.
            try writer.writeByte('?');
        }
        try writer.writeByte('*');
    } else if (hints.is_result) {
        // Results are assumed to be single value pointers, since otherwise, we'd have no way of
        // knowing the length. We conservatively assume these are nullable since we have no way of
        // knowing. Ideally dear bindings would mark this eventually (there is a field for it but
        // it is unused), if it becomes annoying we can always add a whitelist.
        try writer.writeAll("?*");
    } else {
        // If we've reached this case, we're a struct field, and we don't know whether it's many
        // value or nullable. We fall back to a c pointer so that the user can decide how to
        // interpret it with less friction, unless it's an opaque type in which case that's not
        // allowed so we assume it's a nullable single value pointer.
        if (is_opaque or is_void) {
            try writer.writeAll("?*");
        } else {
            try writer.writeAll("[*c]");
        }
    }

    // Write any storage classes
    for (ty.description.inner_type.?.*.storage_classes) |storage_class| switch (storage_class) {
        .@"const" => try writer.writeAll("const "),
    };

    // Write the actual type
    if (is_void) {
        // Treat pointers to c void as pointers to anyopaque
        try writer.writeAll("anyopaque");
    } else {
        try writeType(
            writer,
            .{ .description = ty.description.inner_type.?.* },
            declarations,
            .{},
        );
    }
}

// Returns true if we should skip due to a conditional
fn skip(conditionals: []const Header.Conditional) bool {
    for (conditionals) |conditional| {
        const defined = switch (conditional.expression) {
            .IMGUI_DISABLE_OBSOLETE_FUNCTIONS,
            .IMGUI_DISABLE_OBSOLETE_KEYIO,
            .CIMGUI_API,
            .CIMGUI_IMPL_API,
            .@"defined(IMGUI_IMPL_VULKAN_NO_PROTOTYPES)&&!defined(VK_NO_PROTOTYPES)",
            .@"defined(VK_USE_PLATFORM_WIN32_KHR)&&!defined(NOMINMAX)",
            .IMGUI_IMPL_VULKAN_HAS_DYNAMIC_RENDERING,
            .@"defined(VK_VERSION_1_3)|| defined(VK_KHR_dynamic_rendering)",
            => true,
            .IMGUI_OVERRIDE_DRAWVERT_STRUCT_LAYOUT,
            .IMGUI_USE_WCHAR32,
            .ImTextureID,
            .ImDrawIdx,
            .ImDrawCallback,
            .@"defined(_MSC_VER)&&!defined(__clang__)&&!defined(__INTEL_COMPILER)&&!defined(IMGUI_DEBUG_PARANOID)",
            .@"defined(IMGUI_DISABLE_OBSOLETE_FUNCTIONS)&&!defined(IMGUI_DISABLE_OBSOLETE_KEYIO)",
            .IMGUI_DEFINE_MATH_OPERATORS,
            .IM_COL32_R_SHIFT,
            .IMGUI_USE_BGRA_PACKED_COLOR,
            .IM_DRAWLIST_TEX_LINES_WIDTH_MAX,
            .@"defined(IMGUI_DISABLE_METRICS_WINDOW)&&!defined(IMGUI_DISABLE_OBSOLETE_FUNCTIONS)&&!defined(IMGUI_DISABLE_DEBUG_TOOLS)",
            .@"defined(IMGUI_HAS_IMSTR)",
            .IMGUI_HAS_IMSTR,
            .IMGUI_DISABLE_DEBUG_TOOLS,
            => false,
        };
        switch (conditional.condition) {
            .ifdef, .@"if" => if (!defined) return true,
            .ifndef, .ifnot => if (defined) return true,
        }
    }
    return false;
}

// Converts a cimgui type name to a Zig type name
fn writeTypeName(writer: anytype, raw: []const u8) !void {
    // These are considered user types
    if (std.mem.eql(u8, raw, "size_t")) {
        try writer.writeAll("usize");
        return;
    }

    if (std.mem.eql(u8, raw, "uint32_t")) {
        try writer.writeAll("u32");
        return;
    }

    // We skip all declarations that contain `va_list`, so this shouldn't trigger.
    if (std.mem.eql(u8, raw, "va_list")) unreachable;

    // Remove prefixes
    var name = raw;
    {
        // Imgui prefixes
        {
            const prefixes: []const []const u8 = &.{ "ImGui", "Im" };
            for (prefixes) |prefix| {
                if (std.mem.startsWith(u8, name, prefix)) {
                    name = name[prefix.len..];
                    break;
                }
            }
        }

        // Backend prefixes
        {
            const prefixes: []const []const u8 = &.{ "_ImplVulkanH", "_ImplVulkan" };
            for (prefixes) |prefix| {
                if (std.mem.startsWith(u8, name, prefix)) {
                    name = name[prefix.len..];
                    break;
                }
            }
        }
    }

    for (name) |c| switch (c) {
        '_' => {},
        else => try writer.writeByte(c),
    };
}

// Convert a cimgui field name to a Zig field name
fn writeFieldName(writer: anytype, name: []const u8) !void {
    var escape = false;
    for (name, 0..) |c, i| {
        switch (c) {
            '0'...'9' => {
                if (i == 0) {
                    escape = true;
                    try writer.writeAll("@\"");
                }
                try writer.writeByte(c);
            },
            'a'...'z' => try writer.writeByte(c),
            'A'...'Z' => {
                if (i > 0 and i < name.len - 1) switch (name[i + 1]) {
                    'A'...'Z', '_' => {},
                    else => try writer.writeByte('_'),
                };
                try writer.writeByte(c + 32);
            },
            '_' => if (i != name.len - 1) try writer.writeByte('_'),
            else => std.debug.panic("unexpected char in name: {c}", .{c}),
        }
    }
    if (escape) try writer.writeAll("\"");
}

// Convert a cimgui element name to a Zig element name
fn writeElementName(writer: anytype, type_name: []const u8, raw: []const u8) !void {
    var name = if (std.mem.startsWith(u8, raw, type_name)) raw[type_name.len..] else raw;
    name = if (std.mem.startsWith(u8, name, "ImGui")) name["ImGui".len..] else name;
    name = if (name[0] == '_') name[1..] else name;
    try writeFieldName(writer, name);
}

// Write a cimgui function name as a Zig function name
fn writeFunctionName(writer: anytype, raw: []const u8) !void {
    var name = raw;

    // Imgui prefixes
    {
        const prefixes: []const []const u8 = &.{ "cImGui_ImplVulkan", "ImGui", "Im" };
        for (prefixes) |prefix| {
            if (std.mem.startsWith(u8, name, prefix)) {
                name = name[prefix.len..];
                break;
            }
        }
    }

    if (name[0] == '_') name = name[1..];

    // Lowercase the first set of contiguous capital letters
    var i: usize = 0;
    while (i < name.len and name[i] >= 'A' and name[i] <= 'Z') : (i += 1) {
        try writer.writeByte(name[i] + 32);
    }

    // The rest of the string is usually already camelcase, write it as is unless we encounter an
    // underscore in which case we should skip it an uppercase the next letter.
    if (i < name.len) {
        var uppercase_next = false;
        for (name[i..]) |c| {
            // If we're an underscore, skip it and uppercase the next letter
            if (c == '_') {
                uppercase_next = true;
                continue;
            }

            // Write the next character, adjusting the case as necessary
            switch (c) {
                'a'...'z' => try writer.writeByte(if (uppercase_next) c - 32 else c),
                else => try writer.writeByte(c),
            }
            uppercase_next = false;
        }
    }
}
