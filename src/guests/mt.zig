//! mem test

const std = @import("std");
const servicez = @import("servicez");
const SmallRng = std.Random.DefaultPrng;
const ReturnTy = servicez.ReturnTy;
const Reg = servicez.Reg;
const zig_version_api = servicez.zig_version_api;
const metaToExtern = servicez.metaToExtern;
const ExternMetadata = servicez.ExternMetadata;
const Writer = std.Io.Writer;

export fn run() void {}

pub const page_size: usize = 4096;

pub const max_pages: usize = 100;

pub const num_pages: usize = max_pages * 3 / 2;

// TODO actually alloc??
const Pages = [num_pages]struct { [page_size]u8, u64 };

fn generatePages(rng: *SmallRng) Pages {
    var pages: Pages = undefined;
    for (0..num_pages) |i| {
        const data = &pages[i][0];
        rng.fill(data);
        const checksum = pageChecksum(&(data.*));
        pages[i][1] = checksum;
    }
    return pages;
}

pub fn pageChecksum(page: []const u8) u64 {
    var sum: u64 = 0;
    for (page) |p| sum += @intCast(p);
    return sum;
}

const MainExt = struct {
    pub fn trampoline(
        a0: Reg,
        a1: Reg,
        a2: Reg,
        a3: Reg,
        a4: Reg,
        a5: Reg,
    ) callconv(.c) ReturnTy {
        _ = .{ a0, a1, a2, a3, a4, a5 };
        var rng = SmallRng.init(0);
        const pages = generatePages(&rng);
        const fmt_msg = "{} {} {} {}";
        var buffer: [if (servicez.is_freestanding) 64 else 0]u8 = undefined;
        // Touch random pages until we ran out of exported pages.
        // Compute checksums and append them to the program output.
        for (0..num_pages) |_| {
            const j = rng.random().intRangeLessThanBiased(if (servicez.riscv32) u32 else u64, 0, num_pages);
            const data = &pages[j][0];
            const expected_checksum = pages[j][1];
            const actual_checksum = pageChecksum(data);
            const fmt_param = .{ j, @intFromPtr(data), expected_checksum, actual_checksum };
            if (comptime servicez.is_freestanding) {
                var writer = consoleDataWriter(&buffer);
                // TODO proper error?
                writer.print(fmt_msg, fmt_param) catch unreachable;
            } else {
                //    var buffer: [64]u8 = undefined;
                //    const bw, _ = lockStderrWriter(&buffer);
                //    defer unlockStderrWriter();
                //    nosuspend bw.print(fmt, args) catch return;
                std.debug.print(fmt_msg, fmt_param);
            }
        }

        return 0;
    }

    pub const metadata_symbol: []const u8 = "main";

    pub const metadata = metaToExtern(ExternMetadata{
        .version = zig_version_api,
        .flags = 0,
        //.symbol_length = std.mem.len(METADATA_SYMBOL),
        .symbol_length = metadata_symbol.len,
        //.symbol_length = @sizeOf std.mem.len(METADATA_SYMBOL),
        .symbol = metadata_symbol,
        //.symbol = "refine_ext",
        .input_regs = 0,
        .output_regs = 0,
    });
};

// TODO should corevm_yield_console_data_ext have a size limit?? should really.
// TODO should we have const size variant, with fix len buffer.
const WriteConsoleData = struct {
    pub const metadata_symbol: []const u8 = "corevm_yield_console_data_ext";
    //extern fn GetThirdNumber() u32;
    // TODO is v2 in rust proc macro
    pub const index = std.hash.XxHash32.hash(0, metadata_symbol);
    pub const metadata = servicez.metaToExtern(servicez.ExternMetadata{
        .version = zig_version_api,
        .flags = 0,
        .symbol_length = metadata_symbol.len,
        .symbol = metadata_symbol,
        .input_regs = 3,
        .output_regs = 0,
        .index = index,
    });
    pub fn trampoline(
        stream: Reg,
        address: Reg,
        len: Reg,
        a3: Reg,
        a4: Reg,
        a5: Reg,
    ) callconv(.c) ReturnTy {
        _ = .{ a3, a4, a5 };
        const filler_64 = if (servicez.riscv32) "" else "\n\n.4byte 0";
        _ = asm volatile (".insn r 0xb, 0, 0, zero, zero, zero\n\n.4byte " ++ std.fmt.comptimePrint("{}", .{index}) ++ filler_64 ++ "\n"
            : [ret] "=rdi" (-> ReturnTy), // TODO rather void ret or use other reg
            : [a0] "rdi" (stream),
              [a1] "rax" (address),
              [a2] "rdx" (len),
            : .{});
        return 0;
    }
};

const exports: []const servicez.ExportDef = &.{
    .{ .T = MainExt, .name = "main" },
};

const imports: []const servicez.ExportDef = &.{
    .{ .T = WriteConsoleData, .name = "corevm_yield_console_data_ext" },
};

comptime {
    asm (servicez.metaExports(exports));
    asm (servicez.metaImports(imports));
    if (!@import("builtin").is_test) {
        servicez.exportExports(exports);
        servicez.exportImports(imports);
    }
}

pub fn writeConsoleData(stream: servicez.ConsoleStream, bytes: []const u8) void {
    const bytes_ptr: *const u8 = @ptrCast(bytes);
    _ = WriteConsoleData.trampoline(@intCast(@intFromEnum(stream)), @intCast(@intFromPtr(bytes_ptr)), @intCast(bytes.len), 0, 0, 0);
    return;
}

fn consoleDrain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    try consoleFlush(w);
    if (data.len == 0) return 0;

    var written: usize = 0;
    for (data[0 .. data.len - 1]) |d| {
        writeConsoleData(.stdout, d);
        written += d.len;
    }

    for (0..splat) |_|
        writeConsoleData(.stdout, data[data.len - 1]);
    written += data[data.len - 1].len * splat;

    return written;
}

fn consoleFlush(w: *Writer) Writer.Error!void {
    writeConsoleData(.stdout, w.buffer[0..w.end]);
    w.end = 0;
}

pub fn consoleDataWriter(buffer: []u8) Writer {
    return .{
        .vtable = &.{
            .drain = consoleDrain,
            .flush = consoleFlush,
            .rebase = Writer.failingRebase,
        },
        .buffer = buffer,
    };
}

//extern "C" {
//        // symbol = "corevm_alloc_ext"
//        pub fn alloc(size: u64) -> u64;
//
//        // symbol = "corevm_free_ext"
//        pub fn free(address: u64, size: u64);
//}
//
//pub unsafe fn free2(address: *mut u8, size: u64) {
//    free(address as u64, size)
//}
//
//static ALLOCATOR: NaiveAlloc = NaiveAlloc;
//
//pub struct NaiveAlloc;
//
//unsafe impl GlobalAlloc for NaiveAlloc {
//    #[inline]
//        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
//                let size = layout.size() as u64;
//                alloc(size)
//        }
//
//        #[inline]
//        unsafe fn dealloc(&self, address: *mut u8, layout: Layout) {
//                let size = layout.size() as u64;
//                free2(address, size)
//        }
//}
