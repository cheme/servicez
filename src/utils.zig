const utils = @import("utils.zig");
const std = @import("std");

pub fn isFnType(N: type, f: anytype) bool {
    switch (@typeInfo(@TypeOf(f))) {
        .type => return N == f,
        .@"fn" => |fi| {
            if (!fi.is_generic or fi.return_type != type or fi.is_var_args) @compileError("expect a type fn");
            switch (@typeInfo(N)) {
                .@"struct", .@"union", .@"enum", .@"opaque" => {},
                else => {
                    return false;
                },
            }
            if (@hasDecl(N, "FnType") and @TypeOf(f) == @TypeOf(N.FnType)) {
                return N.FnType == f;
            }
            return false;
        },
        else => @compileError("expect fn(..) type as param"),
    }
}

/// Bounded array. Using old std api in case it get added back, but likely a good idea to change this api later, and move to single_type.zig.
/// (eg no error in our use cases, no param init)
/// Warning this can involve nasty copy.
pub fn BoundedArray(T: type, buffer_capacity: comptime_int) type {
    return struct {
        const Self = @This();
        pub const FnType = BoundedArray;
        buffer: [buffer_capacity]T = undefined,
        len: usize = 0, // std.meta.rangeint next? also compime_int opt

        pub fn init(len: usize) !Self {
            if (len > buffer_capacity) return error.Overflow;
            return Self{ .len = len };
        }
        pub fn set(self: *Self, i: usize, item: T) void {
            self.slice()[i] = item;
        }
        pub fn slice(self: *Self) []T {
            return self.buffer[0..self.len];
        }
        pub fn constSlice(self: *const Self) []const T {
            return self.buffer[0..self.len];
        }
        pub fn fromSlice(s: []const T) Self {
            var res: Self = undefined;
            for (s, 0..) |o, i| res.buffer[i] = o;
            res.len = s.len;
            return res;
        }

        pub fn appendAssumeCapacity(self: *Self, item: T) void {
            std.debug.assert(self.len < buffer_capacity);
            self.buffer[self.len] = item;
            self.len += 1;
        }
    };
}

pub inline fn hasMethod(t: anytype, comptime name: [:0]const u8) bool {
    return structHasMethod(@TypeOf(t), name);
}

pub inline fn structHasMethod(comptime t: type, comptime name: [:0]const u8) bool {
    const type_info = @typeInfo(t);
    switch (type_info) {
        .@"struct", .@"enum", .@"union" => {
            return @hasDecl(t, name);
        },
        .pointer => |p| {
            // TODO @hasField should be fine here: test
            return structHasMethod(p.child, name);
        },
        else => {},
    }
    return false;
}

// avoid error of @hasField on non struct type.
pub inline fn hasField(t: anytype, comptime name: [:0]const u8) bool {
    return structHasField(@TypeOf(t), name);
}

pub inline fn structHasField(comptime t: type, comptime name: [:0]const u8) bool {
    const type_info = @typeInfo(t);
    switch (type_info) {
        .@"struct" => {
            return @hasField(t, name);
        },
        .pointer => |p| {
            // TODO @hasField should be fine here: test
            return structHasField(p.child, name);
        },
        else => {},
    }
    return false;
}

pub inline fn fieldType(comptime t: type, comptime name: FName) ?type {
    const type_info: std.builtin.Type = @typeInfo(t);
    switch (type_info) {
        .@"struct" => |s| {
            inline for (s.fields) |f| {
                if (inlineSliceEql(u8, f.name, name)) return f.type;
            }
        },
        .pointer => |p| {
            return fieldType(p.child, name);
        },
        else => unreachable,
    }
    return null;
}

pub inline fn fieldTypeOrVoid(comptime t: type, comptime name: FName) type {
    return fieldType(t, name) orelse void;
}

inline fn inlineSliceEql(comptime T: type, a: []const T, b: []const T) bool {
    if (@sizeOf(T) == 0) return true;

    if (a.len != b.len) return false;
    if (a.len == 0 or a.ptr == b.ptr) return true;

    inline for (a, b) |a_elem, b_elem| {
        if (a_elem != b_elem) return false;
    }
    return true;
}

pub inline fn nbFields(comptime T: type) comptime_int {
    switch (T) {
        //BoundedArray => {},
        std.ArrayListUnmanaged(u8) => {
            return 1;
        },
        else => {},
    }
    comptime var bounded_array: bool = undefined;
    comptime {
        bounded_array = utils.isFnType(T, BoundedArray);
    }
    if (bounded_array == true) {
        return 1;
    }
    const type_info = @typeInfo(T);
    switch (type_info) {
        .@"struct" => |s| {
            // TODO filter unencoded ones??
            return s.fields.len;
        },
        .pointer => |p| {
            return nbFields(p.child);
        },
        .array => {
            return 1;
        },
        .vector => {
            unreachable;
        },
        .bool => {
            unreachable;
        },
        .void => return 1,
        .int => {
            return 1;
        },
        .comptime_int => {
            unreachable;
        },
        .float, .comptime_float => {
            unreachable;
        },
        .optional => {
            return 1;
        },
        .error_union => {
            unreachable;
        },
        .error_set => {
            unreachable;
        },
        .@"enum" => {
            // no content in variant
            return 1;
        },
        .enum_literal => {
            // no content in variant
            // TODO check diff of Enum and EnumLiteral
            return 1;
        },
        .@"union" => {
            unreachable;
        },
        .@"fn" => {
            return 1;
        },
        .type, .noreturn, .undefined, .null, .@"opaque", .frame, .@"anyframe" => {
            @compileLog(T);
            unreachable;
        },
    }
}

// Field name for meta.
pub const FName: type = [:0]const u8;
