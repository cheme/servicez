const servicez = @import("servicez");
const mod_scale = servicez.scale;
const metaToExtern = servicez.metaToExtern;
const ExternMetadata = servicez.ExternMetadata;
const ExportOptions = @import("std").builtin.ExportOptions;
const ExternOptions = @import("std").builtin.ExternOptions;
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const utils = servicez.utils;
const mod_jam = servicez.jam;
const AuthParams = mod_jam.AuthParams;
const BoundedArray = utils.BoundedArray;
const typeApply = mod_scale.typeApply;

const zig_version_api = 0;

const riscv64 = builtin.target.cpu.arch == .riscv64; // * 2 on riscv64
const riscv32 = builtin.target.cpu.arch == .riscv32; // * 2 on riscv64
const Reg = if (riscv32) u32 else u64; // * 2 on riscv64
const ReturnTy = if (riscv32) u64 else u128; // * 2 on riscv64
// thats two reg packed sa
// const SHIFT: usize = core::mem::size_of::<Reg>() * 8;
// (a0 as ReturnTy) | ((a1 as ReturnTy) << SHIFT)

fn refineExt(ptr: u32, size: u32) callconv(.c) u64 {
    _ = ptr;
    _ = size;
    return 0;
}

//#[polkavm_derive::polkavm_export]
//pub extern "C" fn alloc(size: u32) -> u32 {
//        let ptr = unsafe { alloc::alloc::alloc(Layout::from_size_align(size as
// usize, 4).unwrap()) };
//        ptr as u32
//
//        ret null if cannot allocate
//}
//pub extern "C" fn dealloc(ptr: u32, size: u32) {

const mem_param: usize = 1 << 20; // 1 Meg

// dummy alloc for param passing.
const ParamAlloc = struct {
    const Self = @This();
    heap: [mem_param]u8,
    top: usize,

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc2,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    fn alloc(self: *Self, s: usize) ?*u8 {
        if (self.top + s >= mem_param) {
            return null;
        }
        self.top += s;
        return &self.heap[self.top];
    }
    fn alloc2(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = .{ ptr_align, ret_addr };
        const self: *Self = @ptrCast(@alignCast(ctx));
        return @ptrCast(self.alloc(len));
    }
    pub fn remap(self: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = .{ self, buf, buf_align, new_len, ret_addr };
        // TODO or not we try to have no alloc.
        return null;
    }
    pub fn resize(self: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = .{ self, buf, buf_align, new_len, ret_addr };
        // TODO or not we try to have no alloc.
        return false;
    }
    pub fn free(self: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = .{ self, buf, buf_align, ret_addr };
        // TODO or not we try to have no alloc.
        return;
    }
};

var param_heap: ParamAlloc = ParamAlloc{
    .heap = undefined,
    .top = 0,
};

const RefineExt = struct {
    pub fn trampoline(
        a0: Reg,
        a1: Reg,
        a2: Reg,
        a3: Reg,
        a4: Reg,
        a5: Reg,
    ) callconv(.c) ReturnTy {
        _ = .{ a0, a1, a2, a3, a4, a5 };
        return 0;
    }

    pub const metadata_symbol: []const u8 = "refine_ext";

    pub const metadata = metaToExtern(ExternMetadata{
        .version = zig_version_api,
        .flags = 0,
        //.symbol_length = std.mem.len(METADATA_SYMBOL),
        .symbol_length = metadata_symbol.len,
        //.symbol_length = @sizeOf std.mem.len(METADATA_SYMBOL),
        .symbol = metadata_symbol,
        //.symbol = "refine_ext",
        .input_regs = 2,
        .output_regs = 1,
        ._filler = 0,
    });
};

const ParamAllocExt = struct {
    pub const metadata_symbol: []const u8 = "alloc";
    pub const metadata = metaToExtern(ExternMetadata{
        .version = zig_version_api,
        .flags = 0,
        .symbol_length = metadata_symbol.len,
        .symbol = metadata_symbol,
        .input_regs = 1,
        .output_regs = 1,
        ._filler = 0,
    });

    pub fn trampoline(
        a0: Reg,
        a1: Reg,
        a2: Reg,
        a3: Reg,
        a4: Reg,
        a5: Reg,
    ) callconv(.c) ReturnTy {
        _ = .{ a1, a2, a3, a4, a5 };
        return @intFromPtr(param_heap.alloc(a0));
    }
};

const IsAuthorizedExt = struct {
    pub const metadata_symbol: []const u8 = "is_authorized_ext";
    pub const metadata = metaToExtern(ExternMetadata{
        .version = zig_version_api,
        .flags = 0,
        .symbol_length = metadata_symbol.len,
        .symbol = metadata_symbol,
        .input_regs = 1,
        .output_regs = 1,
        ._filler = 0,
    });

    // 1 compacte is 0 as type and 1 << 2 (type on 2 bit
    const ok_auth: [3]u8 = .{ 1, 1 << 2, 1 };
    const ko_auth: [3]u8 = .{ 1, 1 << 2, 0 };
    const err_auth: [1]u8 = .{0};
    pub fn trampoline(
        a0: Reg,
        a1: Reg,
        a2: Reg,
        a3: Reg,
        a4: Reg,
        a5: Reg,
    ) callconv(.c) ReturnTy {
        _ = .{ a2, a3, a4, a5 };
        const encoded_ptr: [*]u8 = @ptrFromInt(a0);
        const encoded: []u8 = encoded_ptr[0..a1];

        //var fbs = std.io.fixedBufferStream(encoded);
        //const in = fbs.reader();
        var in_r: std.Io.Reader = .fixed(encoded);
        const alloc = param_heap.allocator();
        var result: AuthParams = undefined;
        var builder = mod_scale.Builder(AuthParams){ .in = &in_r, .instance = &result, .oalloc = alloc };
        typeApply(AuthParams, &builder) catch {
            return ((@as(u64, @intFromPtr(&err_auth)) << 32) | @as(u64, @sizeOf(@TypeOf(err_auth))));
        };
        defer result.deinit(alloc);
        // ptr<<32 & size as u32
        // of encoded of Option::<AuthOutput>
        // -> why Option... ok, None is probably error passing.
        // AuthOutput is a bounded bytes vec of max len 256
        // so 256 len get scale encoded in 2 bytes plus one bytes of option then
        // max buf is 259.
        // But here for example we encode a 1 byte reply (yes or no) so 1 for some then 1
        // for len then 1 for ok.
        return ((@as(u64, @intFromPtr(&ok_auth)) << 32) | @as(u64, @sizeOf(@TypeOf(ok_auth))));
    }
};

const exports: []const servicez.ExportDef =
    &.{
        .{ .T = RefineExt, .name = "refine_ext" },
        .{ .T = ParamAllocExt, .name = "param_alloc_ext" },
        .{ .T = IsAuthorizedExt, .name = "is_authorized_ext" },
    };

comptime {
    asm (servicez.metaExports(exports));
}

comptime {
    if (!@import("builtin").is_test) {
        servicez.exportExports(exports);
        //        @export(&RefineExt.trampoline, .{ .name = "refine_ext_trampoline", .section = ".text.polkavm_export.refine_ext", .linkage = .strong });
        //        @export(&RefineExt.metadata, .{ .name = "refine_ext_METADATA", .section = ".polkavm_metadata", .linkage = .strong });
        //
        //        @export(&ParamAllocExt.trampoline, .{ .name = "param_alloc_ext_trampoline", .section = ".text.polkavm_export.param_alloc_ext", .linkage = .strong });
        //        @export(&ParamAllocExt.metadata, .{ .name = "param_alloc_ext_METADATA", .section = ".polkavm_metadata", .linkage = .strong });
        //        @export(&IsAuthorizedExt.trampoline, .{ .name = "is_authorized_ext_trampoline", .section = ".text.polkavm_export.is_authorized_ext", .linkage = .strong });
        //        @export(&IsAuthorizedExt.metadata, .{ .name = "is_authorized_ext_METADATA", .section = ".polkavm_metadata", .linkage = .strong });
    }
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}
export fn trampoline2(
    a0: Reg,
    a1: Reg,
    a2: Reg,
    a3: Reg,
    a4: Reg,
    a5: Reg,
) ReturnTy {
    _ = .{ a0, a1, a2, a3, a4, a5 };
    return 0;
}

export fn run() void {}

pub fn main() !void {}

test "simple test" {
    const d = "hello world";
    try std.testing.expect((IsAuthorizedExt.trampoline(@intFromPtr(d), d.len, 0, 0, 0, 0) != 0));
}

test "simple decode" {
    const expectEqual = std.testing.expectEqual;
    const expect = std.testing.expect;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        std.debug.assert(gpa.deinit() == .ok);
    }
    const ENCODED_LEN: usize = 229;
    const encoded: [ENCODED_LEN]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 190, 173, 208, 31, 72, 226, 249, 60, 221, 207, 53, 102, 145, 58, 166, 225, 125, 228, 228, 45, 144, 175, 13, 149, 204, 205, 85, 150, 63, 234, 49, 87, 0, 79, 15, 133, 72, 106, 82, 221, 91, 0, 50, 152, 71, 60, 6, 174, 29, 34, 136, 83, 179, 249, 133, 189, 62, 105, 251, 224, 255, 134, 211, 125, 186, 220, 117, 154, 191, 243, 89, 213, 175, 134, 194, 194, 32, 74, 51, 228, 64, 161, 221, 237, 68, 54, 42, 169, 202, 63, 97, 30, 252, 210, 67, 23, 98, 220, 117, 154, 191, 243, 89, 213, 175, 134, 194, 194, 32, 74, 51, 228, 64, 161, 221, 237, 68, 54, 42, 169, 202, 63, 97, 30, 252, 210, 67, 23, 98, 207, 63, 47, 38, 43, 196, 146, 233, 221, 95, 168, 246, 87, 121, 15, 202, 191, 153, 54, 24, 141, 217, 168, 200, 50, 143, 222, 132, 12, 24, 9, 152, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 190, 20, 193, 71, 165, 139, 183, 179, 22, 208, 37, 150, 11, 100, 245, 251, 203, 56, 127, 170, 180, 218, 37, 49, 7, 161, 59, 30, 141, 79, 213, 1, 20, 87, 111, 114, 108, 100, 64, 66, 15, 0, 0, 0, 0, 0, 0, 0 };
    var reader = std.Io.Reader.fixed(&encoded);
    var validate = mod_scale.Validate{ .in = &reader };
    try typeApply(AuthParams, &validate);
    var result: AuthParams = undefined;
    var fbs = std.Io.Reader.fixed(&encoded);
    var builder = mod_scale.Builder(AuthParams){ .in = &fbs, .instance = &result, .oalloc = alloc };
    try typeApply(AuthParams, &builder);
    var reencoded: [ENCODED_LEN]u8 = .{0} ** ENCODED_LEN;
    var out = std.Io.Writer.fixed(&reencoded);
    try mod_scale.encode(AuthParams, &result, &out);
    try expectEqual(encoded.len, mod_scale.encodedLen(AuthParams, &result));
    const written = out.end;
    try expectEqual(encoded.len, written);
    try expectEqual(written, reencoded.len);
    try expect(std.mem.eql(u8, reencoded[0..written], encoded[0..]));
    @constCast(&result).deinit(alloc);
}
