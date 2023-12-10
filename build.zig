// I am building my own build.zig based on using the actual raylib c bindings in the engine.
// This build file is based on the one made in raylib-zig repo, but I have modified it to
// be for using the C bindings straight.

// We are using the C bindings because I want to learn how to actually link a C library to Zig
// and also not be dependent on the zig bindings being maintained.

// - Katajisto

const std = @import("std");
const ngn = @This();

fn linkRaylibDeps(b: *std.Build, exe: *std.Build.Step.Compile, target: std.zig.CrossTarget, optimize: std.builtin.Mode) void {
    const rl = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    var a = rl.artifact("raylib");
    const rg = b.dependency("raygui", .{
        .target = target,
        .optimize = optimize,
    });
    const includepath = rg.path("/src/");
    exe.linkLibrary(a);
    exe.addIncludePath(includepath);
    exe.addCSourceFiles(.{ .files = &[_][]const u8{"./src/c/raygui_impl.c"}, .flags = &[_][]const u8{ "-g", "-O3" } });
}

pub fn link(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
) void {
    const target_os = exe.target.toTarget().os.tag;
    switch (target_os) {
        .windows => {
            exe.linkSystemLibrary("winmm");
            exe.linkSystemLibrary("gdi32");
            exe.linkSystemLibrary("opengl32");
        },
        .macos => {
            exe.linkFramework("OpenGL");
            exe.linkFramework("Cocoa");
            exe.linkFramework("IOKit");
            exe.linkFramework("CoreAudio");
            exe.linkFramework("CoreVideo");
        },
        .freebsd, .openbsd, .netbsd, .dragonfly => {
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("rt");
            exe.linkSystemLibrary("dl");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("X11");
            exe.linkSystemLibrary("Xrandr");
            exe.linkSystemLibrary("Xinerama");
            exe.linkSystemLibrary("Xi");
            exe.linkSystemLibrary("Xxf86vm");
            exe.linkSystemLibrary("Xcursor");
        },
        .emscripten, .wasi => {
            // emscripten handles this for web builds
        },
        else => { // linux
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("rt");
            exe.linkSystemLibrary("dl");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("X11");
        },
    }
    linkRaylibDeps(b, exe, target, optimize);
}

pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    if (target.getOsTag() == .emscripten) {
        std.debug.print("Starting emscripten build", .{});
        const exe_lib = compileForEmscripten(b, "ngn", "src/main.zig", target, optimize);
        const rl = b.dependency("raylib", .{
            .target = target,
            .optimize = optimize,
        });
        var a = rl.artifact("raylib");
        const rg = b.dependency("raygui", .{
            .target = target,
            .optimize = optimize,
        });
        const includepath = rg.path("/src/");
        exe_lib.linkLibrary(a);
        exe_lib.addIncludePath(includepath);
        exe_lib.addCSourceFiles(.{ .files = &[_][]const u8{"./src/c/raygui_impl.c"}, .flags = &[_][]const u8{ "-g", "-O3" } });
        const link_step = try linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, a });
        link_step.addArg("--embed-file");
        link_step.addArg("resources/");
        const run_step = try emscriptenRunStep(b);
        run_step.step.dependOn(&link_step.step);
        const run_option = b.step("run", "run?");
        run_option.dependOn(&run_step.step);
    } else {
        const exe = b.addExecutable(.{
            .name = "tmp",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        ngn.link(b, exe, target, optimize);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        b.installArtifact(exe);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        const run_unit_tests = b.addRunArtifact(unit_tests);

        // Similar to creating the run step earlier, this exposes a `test` step to
        // the `zig build --help` menu, providing a way for the user to request
        // running the unit tests.
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    }
}

pub fn compileForEmscripten(
    b: *std.Build,
    name: []const u8,
    root_source_file: []const u8,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
) *std.Build.Step.Compile {
    // TODO: It might be a good idea to create a custom compile step, that does
    // both the compile to static library and the link with emcc by overidding
    // the make function of the step. However it might also be a bad idea since
    // it messes with the build system itself.

    const new_target = updateTargetForWeb(target);

    // The project is built as a library and linked later.
    const exe_lib = b.addStaticLibrary(.{
        .name = name,
        .root_source_file = .{ .path = root_source_file },
        .target = new_target,
        .optimize = optimize,
    });

    // There are some symbols that need to be defined in C.
    const webhack_c_file_step = b.addWriteFiles();
    const webhack_c_file = webhack_c_file_step.add("webhack.c", webhack_c);
    exe_lib.addCSourceFile(.{ .file = webhack_c_file, .flags = &[_][]u8{} });
    // Since it's creating a static library, the symbols raylib uses to webgl
    // and glfw don't need to be linked by emscripten yet.
    exe_lib.step.dependOn(&webhack_c_file_step.step);
    return exe_lib;
}

// <--- Following is straight stolen from the raylib-zig repo build.zig --->

// TODO: each zig update, remove this and see if everything still works.
// https://github.com/ziglang/zig/issues/16776 is where the issue is submitted.
fn updateTargetForWeb(target: std.zig.CrossTarget) std.zig.CrossTarget {
    // Zig building to emscripten doesn't work, because the Zig standard library
    // is missing some things in the C system. "std/c.zig" is missing fd_t,
    // which causes compilation to fail. So build to wasi instead, until it gets
    // fixed.
    return std.zig.CrossTarget{
        .cpu_arch = target.cpu_arch,
        .cpu_model = target.cpu_model,
        .cpu_features_add = target.cpu_features_add,
        .cpu_features_sub = target.cpu_features_sub,
        .os_tag = .wasi,
        .os_version_min = target.os_version_min,
        .os_version_max = target.os_version_max,
        .glibc_version = target.glibc_version,
        .abi = target.abi,
        .dynamic_linker = target.dynamic_linker,
        .ofmt = target.ofmt,
    };
}

const webhack_c =
    \\// Zig adds '__stack_chk_guard', '__stack_chk_fail', and 'errno',
    \\// which emscripten doesn't actually support.
    \\// Seems that zig ignores disabling stack checking,
    \\// and I honestly don't know why emscripten doesn't have errno.
    \\// TODO: when the updateTargetForWeb workaround gets removed, see if those are nessesary anymore
    \\#include <stdint.h>
    \\uintptr_t __stack_chk_guard;
    \\//I'm not certain if this means buffer overflows won't be detected,
    \\// However, zig is pretty safe from those, so don't worry about it too much.
    \\void __stack_chk_fail(void){}
    \\int errno;
;

const builtin = @import("builtin");
const emccOutputDir = "zig-out" ++ std.fs.path.sep_str ++ "htmlout" ++ std.fs.path.sep_str;
const emccOutputFile = "index.html";

pub fn linkWithEmscripten(
    b: *std.Build,
    itemsToLink: []const *std.Build.Step.Compile,
) !*std.Build.Step.Run {
    // Raylib uses --sysroot in order to find emscripten, so do the same here.
    if (b.sysroot == null) {
        @panic("Pass '--sysroot \"[path to emsdk installation]/upstream/emscripten\"'");
    }
    const emccExe = switch (builtin.os.tag) {
        .windows => "emcc.bat",
        else => "emcc",
    };
    var emcc_run_arg = try b.allocator.alloc(u8, b.sysroot.?.len + emccExe.len + 1);
    defer b.allocator.free(emcc_run_arg);

    emcc_run_arg = try std.fmt.bufPrint(
        emcc_run_arg,
        "{s}" ++ std.fs.path.sep_str ++ "{s}",
        .{ b.sysroot.?, emccExe },
    );

    // Create the output directory because emcc can't do it.
    const mkdir_command = b.addSystemCommand(&[_][]const u8{ "mkdir", "-p", "./zig-out/htmlout/" });

    // Actually link everything together.
    const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_run_arg});

    for (itemsToLink) |item| {
        emcc_command.addFileArg(item.getEmittedBin());
        emcc_command.step.dependOn(&item.step);
    }
    // This puts the file in zig-out/htmlout/index.html.
    emcc_command.step.dependOn(&mkdir_command.step);
    emcc_command.addArgs(&[_][]const u8{
        "-o",
        emccOutputDir ++ emccOutputFile,
        "-sFULL-ES3=1",
        "-sUSE_GLFW=3",
        "-sASYNCIFY",
        "-O3",
        "--emrun",
    });
    return emcc_command;
}

pub fn emscriptenRunStep(b: *std.Build) !*std.Build.Step.Run {
    // Find emrun.
    if (b.sysroot == null) {
        @panic("Pass '--sysroot \"[path to emsdk installation]/upstream/emscripten\"'");
    }
    // If compiling on windows , use emrun.bat.
    const emrunExe = switch (builtin.os.tag) {
        .windows => "emrun.bat",
        else => "emrun",
    };
    const emrun_run_arg = try b.allocator.alloc(u8, b.sysroot.?.len + emrunExe.len + 1);
    defer b.allocator.free(emrun_run_arg);

    _ = try std.fmt.bufPrint(emrun_run_arg, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ b.sysroot.?, emrunExe });

    const run_cmd = b.addSystemCommand(&[_][]const u8{ emrun_run_arg, emccOutputDir ++ emccOutputFile });
    return run_cmd;
}
