const std = @import("std");
const builtin = @import("builtin");
pub const scale = @import("scale.zig");
pub const utils = @import("utils.zig");
pub const jam = @import("jam.zig");

pub const zig_version_api = 0;

pub const riscv32 = builtin.target.cpu.arch == .riscv32; // * 2 on riscv64
pub const riscv64 = builtin.target.cpu.arch == .riscv64;

// TODO actually incorrect: just get from builtin
pub const is_freestanding = riscv32 or riscv64;

// TODO should be is_32 (not just riscv32)
pub const Reg = if (riscv32) u32 else u64; // * 2 on riscv64
// TODO should be is_32 (not just riscv32)
pub const ReturnTy = if (riscv32) u64 else u128; // * 2 on riscv64

// thats two reg packed sa
// const SHIFT: usize = core::mem::size_of::<Reg>() * 8;
// (a0 as ReturnTy) | ((a1 as ReturnTy) << SHIFT)

pub const ExternMetadata = struct {
    //const ExternMetadata = packed struct {
    version: u8, // issue: this need to be written as a single byte and here extren align it to u32
    flags: u32,
    symbol_length: u32,
    symbol: []const u8,
    input_regs: u8,
    output_regs: u8,
    index: ?u32 = null,
};

pub fn ExternMetadataC(symbol_len: comptime_int) type {
    return extern struct {
        pub const encoded_size = symbol_len + 16;
        //data: [@sizeOf(ExternMetadata)]u8,
        data: [encoded_size]u8,
    };
}

pub fn metaToExtern(meta: ExternMetadata) ExternMetadataC(meta.symbol_length) {
    comptime {
        var d_ix = 0;
        var data: [ExternMetadataC(meta.symbol_length).encoded_size]u8 = undefined;
        data[d_ix] = meta.version;
        d_ix += 1;
        const flags: [4]u8 = @bitCast(meta.flags);
        for (d_ix..d_ix + 4) |i| {
            data[i] = flags[i - d_ix];
        }
        d_ix += 4;
        const sl: [4]u8 = @bitCast(meta.symbol_length);
        for (d_ix..d_ix + 4) |i| {
            data[i] = sl[i - d_ix];
        }
        d_ix += 4;
        for (d_ix..d_ix + meta.symbol_length) |i| {
            data[i] = meta.symbol[i - d_ix];
        }
        d_ix += meta.symbol_length;
        data[d_ix] = meta.input_regs;
        d_ix += 1;
        data[d_ix] = meta.output_regs;
        d_ix += 1;
        if (meta.index) |i| {
            data[d_ix] = 1;
            // TODO likely byte ordering issue here
            data[d_ix + 1] = @intCast((i << 24) >> 24);
            data[d_ix + 2] = @intCast((i << 16) >> 24);
            data[d_ix + 3] = @intCast((i << 8) >> 24);
            data[d_ix + 4] = @intCast(i >> 24);
        } else {
            for (0..5) |i| data[d_ix + i] = 0;
        }
        return .{ .data = data };
    }
}

pub const ExportDef = struct {
    T: type,
    // TODO name from T. symbol?
    name: []const u8,

    fn meta(self: ExportDef) []const u8 {
        //const name = @typeName(self.T);
        const padding = if (riscv32) "" else "\n.4byte 0x00\n";
        const version = "\n.byte 0x00";
        const s1 = "\n.4byte ";
        const m = self.name ++ "_METADATA";
        const s2 = "\n.4byte ";
        const t = self.name ++ "_trampoline";

        return version ++ s1 ++ m ++ padding ++ s2 ++ t ++ padding;
    }
};

pub fn metaExports(exs: []const ExportDef) []const u8 {
    var r: []const u8 =
        \\.pushsection .polkavm_exports,"R",@note
        \\
    ;
    inline for (exs) |e| {
        r = r ++ e.meta();
    }

    return r ++
        \\
        \\.popsection
    ;
}

pub fn metaImports(exs: []const ExportDef) []const u8 {
    // check unique indexes, expect small number of imports
    comptime {
        for (exs, 0..) |import1, i|
            for (exs[i + 1 ..]) |import2|
                if (import1.T.index == import2.T.index) @compileError("duplicated import index");
    }
    var r: []const u8 =
        \\.pushsection .polkavm_imports,"R",@note
        \\
    ;
    inline for (exs) |e| {
        r = r ++ e.meta();
    }

    return r ++
        \\
        \\.popsection
    ;
}

pub fn exportExports(exs: []const ExportDef) void {
    inline for (exs) |e| {
        @export(&e.T.trampoline, .{ .name = e.name ++ "_trampoline", .section = ".text.polkavm_export." ++ e.name, .linkage = .strong });
        @export(&e.T.metadata, .{ .name = e.name ++ "_METADATA", .section = ".polkavm_metadata", .linkage = .strong });
    }
}
pub fn exportImports(exs: []const ExportDef) void {
    inline for (exs) |e| {
        // TODO should not need this, try remove frme e.meta in metaImport
        @export(&e.T.trampoline, .{ .name = e.name ++ "_trampoline", .section = ".text.polkavm_import" ++ e.name, .linkage = .strong });
        @export(&e.T.metadata, .{ .name = e.name ++ "_METADATA", .section = ".polkavm_metadata", .linkage = .strong });
    }
}

// TODO see if rust impl would allow 0 or 1 so can be just u1
pub const ConsoleStream = enum(u2) {
    stdout = 1,
    stderr = 2,
};

test "compact_integers_encoded_as_expected" {
    const expectEqual = std.testing.expectEqual;
    const expect = std.testing.expect;
    const tests = .{
        .{ 0, "00" },
        .{ 63, "fc" },
        .{ 64, "0101" },
        .{ 16383, "fdff" },
        .{ 16384, "02000100" },
        .{ 1073741823, "feffffff" },
        .{ 1073741824, "0300000040" },
        .{ (1 << 32) - 1, "03ffffffff" },
        .{ 1 << 32, "070000000001" },
        .{ 1 << 40, "0b000000000001" },
        .{ 1 << 48, "0f00000000000001" },
        .{ (1 << 56) - 1, "0fffffffffffffff" },
        .{ 1 << 56, "130000000000000001" },
        .{ std.math.maxInt(u64), "13ffffffffffffffff" },
    };
    var hex_buf: [9]u8 = undefined;
    var buf: [16]u8 = undefined;
    inline for (tests) |t| {
        const result = std.fmt.hexToBytes(&hex_buf, t[1]) catch unreachable;
        try expectEqual(result.len, scale.CompactInt.compact_len(64, t[0]));
        var out = std.Io.Writer.fixed(&buf);
        try scale.CompactInt.encode(64, t[0], &out);
        const written = out.end;
        //std.debug.print("{any} : {any}\n\n", .{ written, result });
        try expect(std.mem.eql(u8, result, buf[0..written]));
        var in_read = std.Io.Reader.fixed(&buf);
        const r = try scale.CompactInt.decode(64, &in_read);
        try expectEqual(t[0], r);
    }
}
