pub const raylib = @cImport({
    @cInclude("stddef.h"); // NULL
    @cInclude("raylib.h");
    @cInclude("raygui.h"); // Required for GUI controls
    @cInclude("raymath.h");
});
