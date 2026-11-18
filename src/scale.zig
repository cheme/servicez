//! scale codec rough impl, not meant to be good (should use a config def independant struct.
const std = @import("std");
const ArrayList = std.ArrayList;

const BoundedArray = @import("utils.zig").BoundedArray;
const utils = @import("utils.zig");
const Allocator = std.mem.Allocator;
const FName = utils.FName;

pub const Validate = struct {
    const Self = @This();
    in: *std.Io.Reader,
    pub fn onStartSeq(self: Self) anyerror!?usize {
        const size = try CompactInt.decode(64, self.in);
        return @intCast(size);
    }
    pub fn onByteSeq(self: Self, size: usize) anyerror!void {
        //std.debug.print("{}\n\n", .{size});
        return self.in.discardAll(size);
    }
    pub fn onInt(self: Self, bits: comptime_int) anyerror!void {
        if (bits % 8 == 0) {
            return self.in.discardAll(bits / 8);
        } else {
            const s: comptime_int = try std.math.divCeil(comptime_int, bits, 8);
            return self.in.discardAll(s);
        }
    }
    pub fn onField(self: Self, comptime name: FName, C: type) anyerror!Self {
        _ = .{ name, C };
        return self;
    }
    pub fn deinitFieldOnErr(self: Self, comptime name: FName, C: type) void {
        _ = .{ self, C, name };
    }
    pub fn onSeq(self: Self, i: usize, C: type) anyerror!Self {
        _ = .{ i, C };
        return self;
    }
    pub inline fn deinitSeqOnErr(self: Self, i: usize, C: type) void {
        _ = .{ self, i, C };
    }
    pub fn onOption(self: Self, C: type) anyerror!?Self {
        _ = .{C};
        // TODO readbyte utils (must exist?).
        while (self.in.seek == self.in.end) try self.in.fillMore();
        const enc = self.in.buffer[self.in.seek];
        self.in.seek += 1;
        switch (enc) {
            0 => {
                return null;
            },
            1 => {
                return self;
            },
            else => {
                return DecodeError.InvalidEncoding;
            },
        }
    }
};

pub fn Builder(T: type) type {
    switch (T) {
        //BoundedArray => {},
        ArrayList(u8) => {
            return struct {
                const Self = @This();
                in: *std.Io.Reader,
                instance: *T,
                oalloc: ?Allocator,

                pub fn onStartSeq(self: Self) anyerror!?usize {
                    const size = try CompactInt.decode(64, self.in);
                    return @intCast(size);
                }

                pub fn onByteSeq(self: Self, size: usize) anyerror!void {
                    const alloc = self.oalloc orelse return DecodeError.RequiresAllocator;
                    var r = try ArrayList(u8).initCapacity(alloc, @intCast(size));
                    errdefer r.deinit(alloc);
                    r.expandToCapacity();
                    const bytes_read = try self.in.readSliceShort(r.items);
                    if (bytes_read != size) {
                        return DecodeError.NotEnoughBytes;
                    }
                    self.instance.* = r;
                }

                pub fn deinitSeqOnErr(self: Self, i: usize, C: type) void {
                    if (utils.structHasMethod(C, "deinit")) {
                        if (self.oalloc) |alloc| {
                            self.instance.items[i].deinit(alloc);
                        }
                    }
                }
            };
        },
        else => {},
    }

    return struct {
        const Self = @This();
        in: *std.Io.Reader,
        instance: *T,
        oalloc: ?Allocator,
        pub fn onStartSeq(self: Self) anyerror!?usize {
            const size = try CompactInt.decode(64, self.in);

            comptime var bounded_array: bool = undefined;
            comptime {
                bounded_array = utils.isFnType(T, BoundedArray);
            }
            if (bounded_array == true) {
                // TODO rather on end and in a specific impl
                self.instance.len = @intCast(size);
            }
            return @intCast(size);
        }
        pub fn onByteSeq(self: Self, size: usize) anyerror!void {
            _ = .{ self, size };
            //std.debug.print("{}\n\n", .{size});
            //return self.in.discardAll(size);
            const type_info = @typeInfo(T);
            switch (type_info) {
                .array => |a| {
                    // debug assert if (a.child == u8) {
                    const bytes_read = try self.in.readSliceShort(self.instance);
                    if (bytes_read != a.len) {
                        return DecodeError.NotEnoughBytes;
                    }
                },
                else => unreachable,
            }
        }
        pub fn onInt(self: Self, bits: comptime_int) anyerror!void {
            if (bits % 8 == 0) {
                self.instance.* = try self.in.takeInt(T, .little);
            } else {
                const s: comptime_int = try std.math.divCeil(comptime_int, bits, 8);
                const rbig = try self.in.takeInt(@Int(.unsigned, 8 * s), .little);
                if (rbig > @as(@Int(.unsigned, 8 * s), std.math.maxInt(T))) {
                    return DecodeError.InvalidEncoding;
                }
                self.instance.* = @intCast(rbig);
            }
        }

        pub fn onField(self: Self, comptime name: FName, C: type) anyerror!Builder(C) {
            return Builder(C){ .in = self.in, .instance = &@field(self.instance, name), .oalloc = self.oalloc };
        }

        pub inline fn deinitFieldOnErr(self: Self, comptime name: FName, C: type) void {
            if (utils.structHasMethod(C, "deinit")) {
                if (self.oalloc) |alloc| {
                    @field(self.instance, name).deinit(alloc);
                }
            }
        }

        pub fn onSeq(self: Self, i: usize, C: type) anyerror!Builder(C) {
            comptime var bounded_array: bool = undefined;
            comptime {
                bounded_array = utils.isFnType(T, BoundedArray);
            }
            if (bounded_array == true) {
                return Builder(C){ .in = self.in, .instance = &self.instance.buffer[i], .oalloc = self.oalloc };
            } else {
                unreachable;
            }
        }

        pub inline fn deinitSeqOnErr(self: Self, i: usize, C: type) void {
            comptime var bounded_array: bool = undefined;
            comptime {
                bounded_array = utils.isFnType(T, BoundedArray);
            }
            if (bounded_array == true) {
                if (utils.structHasMethod(C, "deinit")) {
                    if (self.oalloc) |alloc| {
                        self.instance.buffer[i].deinit(alloc);
                    }
                }
            } else {
                unreachable;
            }
        }

        pub fn onOption(self: Self, C: type) anyerror!?Builder(C) {
            while (self.in.seek == self.in.end) try self.in.fillMore();
            const enc = self.in.buffer[self.in.seek];
            self.in.seek += 1;

            switch (enc) {
                0 => {
                    self.instance.* = null;
                    return null;
                },
                1 => {
                    self.instance.* = undefined;
                    return Builder(C){ .in = self.in, .instance = &self.instance.*.?, .oalloc = self.oalloc };
                },
                else => {
                    return DecodeError.InvalidEncoding;
                },
            }
        }
    };
}

// TODO this one is the actual scale format one
// TODO check json scanner
//
// pub const TokenType = enum {
//   object_begin,
//  object_end,
// array_begin,
//array_end,
// true,
//  false,
//  null,
//  number,
//  string,
// end_of_document, // ??? should be either array_end or object_end
//};
const ScaleParser = struct {
    // call event for given struct in input
    // interact with parser state
};
// TODO direct action call
// TODO derive it from a struct to init ala dom too
const ParserState = struct {
    // TODO ret err.
    fn on_something() void {}
};

pub fn EncodedLen(T: type) type {
    return struct {
        const Self = @This();
        const type_info = @typeInfo(T);
        len: *usize,
        data: *const T,

        pub fn onStartSeq(self: *const Self) anyerror!?usize {
            const d = seqLen(T, self.data);
            if (!d.is_fix) {
                self.len.* += CompactInt.compact_len(64, d.len);
            }
            return d.len;
        }

        pub fn onByteSeq(self: *const Self, size: usize) anyerror!void {
            self.len.* += size;
        }

        pub fn onSeq(self: *const Self, i: usize, C: type) anyerror!EncodedLen(C) {
            // TODO comptime assert C is not u8
            return .{
                .len = self.len,
                .data = seqAt(T, C, i, self.data),
            };
        }
        pub inline fn deinitSeqOnErr(self: *const Self, i: usize, C: type) void {
            _ = .{ self, i, C };
        }

        pub fn onInt(self: *const Self, bits: comptime_int) anyerror!void {
            if (bits % 8 == 0) {
                self.len.* += bits / 8;
            } else {
                const s: comptime_int = try std.math.divCeil(comptime_int, bits, 8);
                self.len.* += s;
            }
        }
        pub fn onField(self: *const Self, comptime name: FName, C: type) anyerror!EncodedLen(C) {
            return .{
                .len = self.len,
                .data = &@field(self.data, name),
            };
        }
        pub fn deinitFieldOnErr(self: *const Self, comptime name: FName, C: type) void {
            _ = .{ self, C, name };
        }
        pub fn onOption(self: *const Self, C: type) anyerror!?EncodedLen(C) {
            self.len.* += 1; // 0 for null 1 for value
            if (self.data.*) |*d| {
                return .{
                    .len = self.len,
                    .data = d,
                };
            }
            return null;
        }
    };
}

pub fn encodedLen(comptime T: type, data: *const T) usize {
    var size: usize = 0;
    var counter = EncodedLen(T){
        .len = &size,
        .data = data,
    };
    typeApply(T, &counter) catch unreachable;
    return size;
}

pub fn Encoder(T: type) type {
    return struct {
        const Self = @This();
        const type_info = @typeInfo(T);
        out: *std.Io.Writer,
        data: *const T,

        pub fn onStartSeq(self: *const Self) anyerror!?usize {
            const d = seqLen(T, self.data);
            if (!d.is_fix) {
                try CompactInt.encode(64, d.len, self.out);
            }
            return d.len;
        }

        pub fn onByteSeq(self: *const Self, _: usize) anyerror!void {
            try self.out.writeAll(seqBytes(T, self.data));
        }

        pub fn onSeq(self: *const Self, i: usize, C: type) anyerror!Encoder(C) {
            // TODO comptime assert C is not u8
            return .{
                .out = self.out,
                .data = seqAt(T, C, i, self.data),
            };
        }
        pub inline fn deinitSeqOnErr(self: *const Self, i: usize, C: type) void {
            _ = .{ self, i, C };
        }

        pub fn onInt(self: *const Self, bits: comptime_int) anyerror!void {
            if (bits % 8 == 0) {
                try self.out.writeInt(T, self.data.*, .little);
            } else {
                const s: comptime_int = try std.math.divCeil(comptime_int, bits, 8);
                const T2 = @Int(.unsigned, 8 * s);
                const data2: T2 = @intCast(self.data);
                // TODO recheck needed to be align
                try self.out.writeInt(T2, data2, .little);
            }
        }
        pub fn onField(self: *const Self, comptime name: FName, C: type) anyerror!Encoder(C) {
            return .{
                .out = self.out,
                .data = &@field(self.data, name),
            };
        }
        pub fn deinitFieldOnErr(self: *const Self, comptime name: FName, C: type) void {
            _ = .{ self, C, name };
        }
        pub fn onOption(self: *const Self, C: type) anyerror!?Encoder(C) {
            if (self.data.*) |*d| {
                try self.out.writeByte(1);
                return .{
                    .out = self.out,
                    .data = d,
                };
            } else {
                try self.out.writeByte(0);
                return null;
            }
        }
    };
}

pub fn encode(comptime T: type, data: *const T, out: *std.Io.Writer) anyerror!void {
    var encoder = Encoder(T){
        .out = out,
        .data = data,
    };
    try typeApply(T, &encoder);
}

pub const DecodeError = error{
    NotEnoughBytes,
    RequiresAllocator,
    InvalidEncoding,
};

// TODO start from a encode compact int and decode and test, still using these
// TODO copy rust int fns and then from the impl (using generic re and generic w as inputs): have a buffer size constraint -> leading to global min buffer size from target (or just have a fix buffer on a custom sax like parser: then buffer size constraint need to be in function and comptime. TODO avoid writing in on multiple calls: if rem buf size is less than needed then return and put next: do not fear multiple alls.
pub const CompactInt = struct {
    const Error = error{
        ValueTooBigForType,
        InvalidEncoding,
    };

    // TODO can also return shifted u6
    pub fn compact_len(comptime L: u16, val: @Int(.unsigned, L)) u16 {
        if (L <= 6) {
            return 1;
        }
        if (val <= 0b0011_1111) {
            return 1;
        }
        if (L <= 14) {
            return 2;
        }
        if (val <= 0b0011_1111_1111_1111) {
            return 2;
        }
        if (L <= 32) {
            return 4;
        }
        if (val <= 0b0011_1111_1111_1111_1111_1111_1111_1111) {
            return 4;
        }
        return (std.math.divCeil(u16, L - @clz(val), 8) catch unreachable) + 1;
        //                    0..=0b0011_1111 => 1,
        //                    0..=0b0011_1111_1111_1111 => 2,
        //                    0..=0b0011_1111_1111_1111_1111_1111_1111_1111 => 4,
        //                    _ => {
        //                            (8 - val.leading_zeros() / 8) as usize + 1

    }

    pub fn encode(comptime L: u16, val: @Int(.unsigned, L), out: *std.Io.Writer) !void {
        const s = compact_len(L, val);
        switch (s) {
            1 => {
                //0b00
                const v: u8 = @intCast(val);
                try out.writeByte(v << 2);
            },
            2 => {
                //0b01
                const v: u16 = @intCast(val);
                try out.writeInt(u16, (v << 2) | 0b01, .little);
            },
            4 => {
                //0b10
                const v: u32 = @intCast(val);
                try out.writeInt(u32, (v << 2) | 0b10, .little);
            },
            else => {
                //0b11
                const s8: u8 = @intCast(s);
                try out.writeAll(&.{((s8 - 1 - 4) << 2) | 0b11});
                var val_buf = val;
                //try out.writeInt(@Int(.unsigned, L), val, .little);
                for (0..s - 1) |_| {
                    const v: u8 = @intCast(val_buf & std.math.maxInt(u8));
                    try out.writeByte(v);
                    val_buf >>= 8;
                }
            },
        }
    }

    pub fn decode(comptime L: u16, in: *std.Io.Reader) anyerror!@Int(.unsigned, L) {
        while (in.seek == in.end) try in.fillMore();

        const first_byte = in.buffer[in.seek];
        in.seek += 1;
        const prefix: u2 = @intCast(first_byte & 0b11);
        switch (prefix) {
            0b00 => {
                // 1 byte TODO pref value as const so no doc
                return std.math.cast(@Int(.unsigned, L), first_byte >> 2) orelse Error.ValueTooBigForType;
            },
            0b01 => {
                while (in.seek == in.end) try in.fillMore();
                // 1 bytes
                //std.debug.print("{any} : {any}\n\n", .{ @as(u16, try in.readByte()) << 8, @as(u16, first_byte >> 2) });
                const v: u16 = ((@as(u16, in.buffer[in.seek]) << 8) | @as(u16, first_byte)) >> 2;
                in.seek += 1;
                if (v <= 0b0011_1111) {
                    return Error.InvalidEncoding;
                }
                return std.math.cast(@Int(.unsigned, L), v) orelse Error.ValueTooBigForType;
            },
            0b10 => {
                // 4 bytes
                const v: u32 = ((@as(u32, try in.takeInt(u24, .little)) << 8) | @as(u32, first_byte)) >> 2;
                if (v <= 0b0011_1111_1111_1111) {
                    return Error.InvalidEncoding;
                }
                return std.math.cast(@Int(.unsigned, L), v) orelse Error.ValueTooBigForType;
            },
            0b11 => {
                const s: u16 = (first_byte >> 2) + 4;
                if (L < (s - 1) * 8) {
                    // might also be small value encoded in too many byte
                    // but rather error earlier.
                    return Error.ValueTooBigForType;
                }
                var result: @Int(.unsigned, L) = 0;
                switch (s) {
                    inline 4...8 => |s4| {
                        const v = try in.takeInt(@Int(.unsigned, s4 * 8), .little);
                        if (v <= std.math.maxInt(u32) >> 2) {
                            return Error.InvalidEncoding;
                        }
                        result = std.math.cast(@Int(.unsigned, L), v) orelse return Error.ValueTooBigForType;
                    },
                    9...(63 + 4) => |s4| {
                        for (0..s4) |i| {
                            while (in.seek == in.end) try in.fillMore();
                            const b = @as(@Int(.unsigned, L), in.buffer[in.seek]);
                            in.seek += 1;
                            result |= b << @intCast(i * 8);
                        }
                    },
                    else => {
                        return Error.InvalidEncoding;
                    },
                }
                if (result <= std.math.maxInt(u32) >> 2) {
                    return Error.InvalidEncoding;
                }
                return result;
            },
        }
    }
};

pub fn typeApply(T: type, callback: anytype) anyerror!void {
    //@compileLog(@typeName(T));
    switch (T) {
        //BoundedArray => {},
        ArrayList(u8) => {
            // TODO not sure this onStartSeq should be part of callback
            const osize = try callback.onStartSeq();
            if (osize) |size| {
                try callback.onByteSeq(size);
            } else {
                unreachable; // TODO api for terminated sequence.
            }
            return;
        },
        else => {},
    }
    comptime var bounded_array: bool = undefined;
    comptime {
        bounded_array = utils.isFnType(T, BoundedArray);
    }
    if (bounded_array == true) {
        const type_info = @typeInfo(T);
        const buffer = type_info.@"struct".field_types[0]; // TODO assert name
        const type_info_child = @typeInfo(buffer).array;
        //@compileLog(type_info_child);
        const osize = try callback.onStartSeq();
        if (osize) |s| {
            if (s >= type_info_child.len) {
                return DecodeError.InvalidEncoding;
            }
            if (type_info_child.child == u8) {
                try callback.onByteSeq(s);
            } else {
                var i: usize = 0;
                errdefer {
                    for (0..i) |j| {
                        // TODO better name: is clean up of past ix
                        callback.deinitSeqOnErr(j, type_info_child.child);
                    }
                }
                while (i < s) {
                    const child_callback = try callback.onSeq(i, type_info_child.child);
                    try typeApply(type_info_child.child, child_callback);
                    i += 1;
                }
            }
        } else {
            unreachable; // TODO api for terminated sequence (most likely on_end_seq).
        }
        return;
    }
    //@compileLog(@typeName(T));
    const type_info = @typeInfo(T);
    switch (type_info) {
        inline .@"struct" => |s| {
            comptime var i = 0;
            errdefer {
                comptime var j = 0;
                inline for (s.field_names, s.field_types) |f_name, f_type| {
                    if (j == i) {
                        break;
                    }
                    callback.deinitFieldOnErr(f_name, f_type);
                    j += 1;
                }
            }
            inline for (s.field_names, s.field_types) |f_name, f_type| {
                //@compileLog(f.type);
                const inner = try callback.onField(f_name, f_type);
                try typeApply(f_type, inner);

                i += 1;
            }
        },
        .pointer => {
            unreachable; // TODO likely allocate in this case??
        },
        .array => |a| {
            if (a.child == u8) {
                try callback.onByteSeq(a.len);
            } else {
                unreachable;
            }
        },
        .spirv => {
            unreachable;
        },
        .vector => {
            unreachable;
        },
        .bool => {
            unreachable;
        },
        .int => |i| {
            try callback.onInt(i.bits);
        },
        .comptime_int => {
            unreachable;
        },
        .float, .comptime_float => {
            unreachable;
        },
        .optional => |o| {
            if (try callback.onOption(o.child)) |inner| {
                try typeApply(o.child, inner);
            }
        },
        .error_union => {
            unreachable;
        },
        .error_set => {
            unreachable;
        },
        .@"enum" => {
            unreachable;
        },
        .enum_literal => {
            unreachable;
        },
        .@"union" => {
            unreachable;
        },
        .type, .void, .noreturn, .undefined, .null, .@"fn", .@"opaque", .frame, .@"anyframe" => {
            unreachable;
        },
    }
    return;
}

pub fn seqAt(T: type, C: type, i: usize, data: *const T) *const C {
    comptime var bounded_array: bool = undefined;
    comptime {
        bounded_array = utils.isFnType(T, BoundedArray);
    }
    if (bounded_array == true) {
        return &data.buffer[i];
    }

    switch (T) {
        ArrayList => return &data.items[i],
        else => {},
    }
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Array => return &data[i],
        else => {
            unreachable;
        },
    }
}

// TODO may it anon?
const SeqDesc = struct {
    len: usize,
    is_fix: bool,
};

pub fn seqLen(T: type, data: *const T) SeqDesc {
    comptime var bounded_array: bool = undefined;
    comptime {
        bounded_array = utils.isFnType(T, BoundedArray);
    }
    if (bounded_array == true) {
        return .{
            .len = data.len,
            .is_fix = false,
        };
    }

    switch (T) {
        ArrayList(u8) => return .{
            .len = data.items.len,
            .is_fix = false,
        },
        else => {},
    }
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Array => return .{
            .len = data.len(),
            .is_fix = true,
        },
        else => {
            unreachable;
        },
    }
}

pub fn seqBytes(T: type, data: *const T) []const u8 {
    comptime var bounded_array: bool = undefined;
    comptime {
        bounded_array = utils.isFnType(T, BoundedArray);
    }
    if (bounded_array == true) {
        return data;
    }

    switch (T) {
        ArrayList(u8) => return data.items,
        else => {},
    }
    const type_info = @typeInfo(T);
    switch (type_info) {
        .array => return data,
        else => {
            unreachable;
        },
    }
}
