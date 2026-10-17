const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("fiscus", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // === CLI EXE
    const exe = b.addExecutable(.{
        .name = "fis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fiscus", .module = mod },
            },
        }),
    });

    // === TUI EXE
    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    const vaxis_mod = vaxis.module("vaxis");

    const tui_exe = b.addExecutable(.{
        .name = "fis-tui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tui/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fiscus", .module = mod },
                .{ .name = "vaxis", .module = vaxis_mod },
            },
        }),
    });

    b.installArtifact(exe);
    b.installArtifact(tui_exe);

    const run_step = b.step("run", "Run the CLI");
    const tui_step = b.step("tui", "Run the TUI");

    const run_cmd = b.addRunArtifact(exe);
    const tui_cmd = b.addRunArtifact(tui_exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    tui_step.dependOn(&tui_cmd.step);
    tui_cmd.step.dependOn(b.getInstallStep());
    tui_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "fiscus",
                    .module = mod,
                },
            },
        }),
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_integration_tests.step);
}
