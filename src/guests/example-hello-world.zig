const servicez = @import("servicez");
const ReturnTy = servicez.ReturnTy;
const Reg = servicez.Reg;
const zig_version_api = servicez.zig_version_api;

export fn run() void {}

const GetThirdNumber = struct {
    pub const metadata_symbol: []const u8 = "get_third_number";
    extern fn GetThirdNumber() u32;
    // TODO is v2 in rust proc macro
    pub const metadata = servicez.metaToExtern(servicez.ExternMetadata{
        .version = zig_version_api,
        .flags = 0,
        .symbol_length = metadata_symbol.len,
        .symbol = metadata_symbol,
        .input_regs = 0,
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
        _ = .{ a0, a1, a2, a3, a4, a5 };

        // asm (".insn r 0xb, 0, 0, zero, zero, zero\n\nauipc zero, %pcrel_hi({8})\n"
        return asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\nauipc zero, %pcrel_hi(%[ret])\n"
            : [ret] "={a1}" (-> ReturnTy),
            : [a0] "{a0}" (a0),
              [a1] "{a1}" (a1),
              [a2] "{a2}" (a2),
              [a3] "{a3}" (a3),
              [a4] "{a4}" (a4),
              [a5] "{a5}" (a5),
            : .{});
    }
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
        //_ = .{ a2, a3, a4, a5 };
        const a = a0;
        const b = a1;
        //        const c = GetThirdNumber.GetThirdNumber();
        const c = GetThirdNumber.trampoline(a0, a1, a2, a3, a4, a5);
        //const c = getThirdNumber();

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

const exports_imports: []const servicez.ExportDef =
    &.{
        .{ .T = AddNumbers, .name = "add_numbers" },
        .{ .T = GetThirdNumber, .name = "get_third_number" },
    };

comptime {
    //asm (servicez.metaExports(exports_imports));
    asm (servicez.metaExports(exports));
    //asm (servicez.metaImports(imports));
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
