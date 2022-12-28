// Zig Documentation — https://ziglang.org/documentation/master/#Case-Study-printf-in-Zig
// SDL Documentation — https://www.libsdl.org/release/SDL-1.2.15/docs/html/index.html

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

const Position = struct {
    x: u8,
    y: u8,
};

const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
};

const Input = enum {
    MOVE_LEFT,
    MOVE_RIGHT,
    MOVE_DOWN,
    ROTATE,
    PLACE_TETROMINO,
};

const Event = struct {
    time: u32,
    input: Input,
};

const allocator: std.mem.Allocator = std.heap.page_allocator;

const events = undefined;

pub fn main() !void {

    // ##### SDL SETUP
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("Esching", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, screen_width, screen_height, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    events = try std.mem.Allocator.allocate(Event, 1000);

//    print("{}\n", .{ .len = events.len});


    var prev_time = c.SDL_GetTicks();

    var quit = false;

    while (true) {
        var curr_time = c.SDL_GetTicks();
        var elapsed_time = (curr_time - prev_time);

        var sdl_event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (sdl_event.@"type") {
                c.SDL_QUIT => { quit = true; },
                c.SDL_KEYDOWN => {
                    const game_event = sdl_event_to_input(sdl_event);
                    print("game_event = {} \n", .{game_event});
                },
                c.SDL_KEYUP => { print("keyup event: {}\n", .{event.@"key".keysym.sym}); },
                else => {},
            }
        }

        // Render Background
        _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
        _ = c.SDL_RenderClear(renderer);

        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}

pub fn sdl_event_to_input(sdl_event: c.SDL_Event) Input {
    switch (event.key.keysym.sym) {
        c.SDLK_LEFT => { return Input.MOVE_LEFT; } },
        c.SDLK_RIGHT => { return Input.MOVE_RIGHT; },
        c.SDLK_DOWN => { return Input.MOVE_DOWN },
        c.SDLK_UP => { return Input.ROTATE; },
        32 => { return Input.PLACE_TEROMINO  }, // spacebar
        else => {},
    }
}
