const std = @import("std");
const r = @import("ray.zig").raylib;

pub fn main() !void {
    r.InitWindow(1920, 1080, "Zie v0.1");
    r.SetTargetFPS(60);
    while (!r.WindowShouldClose()) {
        r.BeginDrawing();
        r.EndDrawing();
    }
    r.CloseWindow();
}
