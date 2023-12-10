# Zig Image Editor!
I have no idea how to write an image editing tool like gimp or PS.

I'm not going to try to find out how to write one. I am just going to write one from scratch. 
Hopefully the end result after a lot of iteration is something usable + fast. 

My biggest issues with these tools are complexity and slowness. This tool will try to remain simple, 
but still have useful features.

Startup time is critical! You can not use PS or Gimp as your default program for opening images, since they
are so slow that it will take tens of seconds to even see the image! It is critical to me that you can use this
tool as your default tool for opening images.

## Plan:
1. Basic image viewing using raylib as the way to open windows etc..
2. Basic editing tools.
3. Swap raylib's image loading to some other C solution that is a better fit, but keep raylib as the programs graphics thing.
4. More advanced editing tools
5. Still keep raylib around for windows and basic rendering, but at some point look into replacing Raygui with a self-written solution or some other skinnable imgui library.
