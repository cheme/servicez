const servicez = @import("servicez");
const std = @import("std");
const ReturnTy = servicez.ReturnTy;
const Reg = servicez.Reg;
const zig_version_api = servicez.zig_version_api;

export fn run() void {}

const GetThirdNumber = struct {
    //    const MStruct = extern struct {
    //        d: [5]u8,
    //    };
    //    const ms: MStruct = .{ .d = .{ 1, 2, 3, 4, 5 } };
    //    comptime {
    //        @export(&ms, .{ .name = "test_METADATA", .section = ".polkavm_metadata", .linkage = .strong });
    //        asm (".insn r 0xb, 0, 0, zero, zero, zero\n\n.4byte " ++ metadata_symbol ++ "_METADATA\n");
    //        asm (".insn r 0xb, 0, 0, zero, zero, zero\n\n.4byte test_METADATA\n");
    //    }

    pub const metadata_symbol: []const u8 = "get_third_number";
    //extern fn GetThirdNumber() u32;
    // TODO is v2 in rust proc macro
    pub const index = std.hash.XxHash32.hash(0, metadata_symbol);
    pub const metadata = servicez.metaToExtern(servicez.ExternMetadata{
        .version = zig_version_api,
        .flags = 0,
        .symbol_length = metadata_symbol.len,
        .symbol = metadata_symbol,
        .input_regs = 0,
        .output_regs = 1,
        .index = index,
    });
    // TODO should use @export like for exports.
    pub noinline fn trampoline(
        a0: Reg,
        a1: Reg,
        a2: Reg,
        a3: Reg,
        a4: Reg,
        a5: Reg,
    ) callconv(.c) ReturnTy {
        _ = .{ a0, a1, a2, a3, a4, a5 };
        //    11f0:0000000b          .insn 4, 0x000b
        //    11f4:00002017          auipc zero,0x2
        //    11f8:8082                ret

        //return asm (".insn r 0xb, 0, 0, zero, zero, zero\n\nauipc zero, %pcrel_hi(%[ret])\n"
        //return asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\n"
        //    : [ret] "=rdi" (-> ReturnTy),
        //    :
        //    : .{});

        // TODO 0x01 from a metadata actual index
        //return asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\n.4byte " ++ metadata_symbol ++ "_METADATA\n"
        //return asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\n.4byte " ++ metadata_symbol ++ "_METADATA\n"
        return asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\n.4byte " ++ std.fmt.comptimePrint("{}", .{index}) ++ "\n"
            : [ret] "=rdi" (-> ReturnTy),
            :
            : .{});

        //asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\n.4byte test_METADATA\n");
        //return 5;
        //return asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\nauipc zero, %pcrel_hi(%[tes])\n"
        //    : [ret] "=rdi" (-> ReturnTy),
        //    : [tes] "rdi" (a),
        //    : .{});

        // asm (".insn r 0xb, 0, 0, zero, zero, zero\n\nauipc zero, %pcrel_hi({8})\n"
        //        return asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\nauipc zero, %pcrel_hi(%[ret])\n"
        //            : [ret] "=&r8" (-> ReturnTy),
        //            : [a0] "rdi" (a0),
        //              [a1] "rax" (a1),
        //              [a2] "rdx" (a2),
        //              [a3] "rbp" (a3),
        //              [a4] "r10" (a4),
        //              [a5] "r11" (a5),
        //            : .{});
    }

    //        Reg::A0 => rdi,
    //        Reg::A1 => rax,
    //        Reg::SP => rsi,
    //        Reg::RA => rbx,
    //        Reg::A2 => rdx,
    //        Reg::A3 => rbp,
    //        Reg::S0 => r8,
    //        Reg::S1 => r9,
    //        Reg::A4 => r10,
    //        Reg::A5 => r11,
    //        Reg::T0 => r13,
    //        Reg::T1 => r14,
    //        Reg::T2 => r12,

};

fn getThirdNumber() u32 {
    return 1;
}

const AddNumbers = struct {
    pub const metadata_symbol: []const u8 = "add_numbers";
    pub const metadata = servicez.metaToExtern(servicez.ExternMetadata{
        .version = zig_version_api,
        .flags = 0,
        .symbol_length = metadata_symbol.len,
        .symbol = metadata_symbol,
        .input_regs = 2,
        .output_regs = 1,
    });

    pub fn trampoline(
        a0: Reg,
        a1: Reg,
        a2: Reg,
        a3: Reg,
        a4: Reg,
        a5: Reg,
    ) callconv(.c) ReturnTy {
        _ = .{ a2, a3, a4, a5 };
        const a = a0;
        const b = a1;
        //        const c = GetThirdNumber.GetThirdNumber();
        const c = GetThirdNumber.trampoline(a0, a1, a2, a3, a4, a5);
        //const c = getThirdNumber();
        //const c = GetThirdNumber.trampoline();

        // TODO differnt for u64?
        return @intCast(a + b + c);

        //return ((@as(u64, @intFromPtr(&ok_auth)) << 32) | @as(u64, @sizeOf(@TypeOf(ok_auth))));
    }
};

const exports: []const servicez.ExportDef =
    &.{
        .{ .T = AddNumbers, .name = "add_numbers" },
    };

const imports: []const servicez.ExportDef =
    &.{
        .{ .T = GetThirdNumber, .name = "get_third_number" },
    };

fn importsIx(imps: []const servicez.ExportDef, T: type) comptime_int {
    for (0..imps.len) |i| {
        if (imps[i].T == T) return i;
    }

    @compileError("import fn not in import declaration");
}

const exports_imports: []const servicez.ExportDef =
    &.{
        .{ .T = AddNumbers, .name = "add_numbers" },
        .{ .T = GetThirdNumber, .name = "get_third_number" },
    };

comptime {
    //asm (servicez.metaExports(exports_imports));
    asm (servicez.metaExports(exports));
    asm (servicez.metaImports(imports));
    if (!@import("builtin").is_test) {
        servicez.exportExports(exports);
        servicez.exportImports(imports);
    }
}

//#![no_std]
//#![no_main]
//
//#[panic_handler]
//fn panic(_info: &core::panic::PanicInfo) -> ! {
//    unsafe {
//        core::arch::asm!("unimp", options(noreturn));
//    }
//}
//
//#[polkavm_derive::polkavm_import]
//extern "C" {
//    fn get_third_number() -> u32;
//}
//
//#[polkavm_derive::polkavm_export]
//extern "C" fn add_numbers(a: u32, b: u32) -> u32 {
//    a + b + unsafe { get_third_number() }
//}
