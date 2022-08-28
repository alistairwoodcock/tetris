// Zig Documentation — https://ziglang.org/documentation/master/#Case-Study-printf-in-Zig
// SDL Documentation — https://www.libsdl.org/release/SDL-1.2.15/docs/html/index.html

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const print = std.debug.print;

const Position = struct {
    x: c_int,
    y: c_int,
};

var pos = Position {
    .x = 0,
    .y = 0,
};

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow(
        "Esching", 
        c.SDL_WINDOWPOS_UNDEFINED, 
        c.SDL_WINDOWPOS_UNDEFINED, 
        1280, 720, 
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE
    ) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);


    var quit = false;
    while (!quit) {

        var event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => {
                    quit = true;
                },

                c.SDL_KEYDOWN => {
                    switch( event.key.keysym.sym ) {
                        c.SDLK_LEFT => {
                            pos.x -= 1;
                        },
                        c.SDLK_RIGHT => {
                            pos.x += 1;
                        },
                        c.SDLK_UP => {
                            pos.y -= 1;
                        },
                        c.SDLK_DOWN => {
                            pos.y += 1;
                        },  
                        else => {},
                    }
                },

                c.SDL_KEYUP => {
                    print("keyup event: {}\n", .{event.@"key".keysym.sym});
                },

                else => {},
            }
        }
        
        _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
        _ = c.SDL_RenderClear(renderer);

        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0xff, 0, 0xff);
        const rect = c.SDL_Rect{ .x=pos.x, .y=pos.y, .w=100, .h=100};
        
        _ = c.SDL_RenderFillRect(renderer, &rect);

        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}