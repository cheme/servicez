const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("servicez", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
    });

    const test_z_exe = b.addExecutable(.{
        .name = "test_z",

        .root_module = b.createModule(.{
            .root_source_file = b.path("src/guests/test_z.zig"),
            .target = target,
            .optimize = optimize,
            .pic = true,
            .strip = false,
            .imports = &.{
                .{ .name = "servicez", .module = mod },
            },
        }),
        .linkage = .static,
        .use_lld = true,
    });

    test_z_exe.link_emit_relocs = true; // emit reloc needed for polkavm linker
    test_z_exe.pie = true;
    test_z_exe.lto = .none;
    test_z_exe.entry = .{ .symbol_name = "run" };
    test_z_exe.discard_local_symbols = true;
    test_z_exe.link_z_notext = true;
    //test_z_exe.link_z_lazy = false;
    //test_z_exe.link_z_notext = true;
    //test_z_exe.link_z_lazy = true;
    //test_z_exe.link_z_max_page_size =

    b.installArtifact(test_z_exe);

    //const tools_step = b.step("tools", "Compiles all tools required in the build process");
    //tools_step.dependOn(&test_z_exe.step);

    //    const run_cmd = b.addRunArtifact(test_z_exe);
    //    run_cmd.step.dependOn(b.getInstallStep());
    //    if (b.args) |args| {
    //        run_cmd.addArgs(args);
    //    }
    //
    //    const run_step = b.step("run", "Run the app");
    //    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_z_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/guests/test_z.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "servicez", .module = mod },
            },
        }),
    });

    const run_test_z_unit_tests = b.addRunArtifact(test_z_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_test_z_unit_tests.step);
}
