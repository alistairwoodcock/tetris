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

const block_width = 32;
const screen_width = 384;
const screen_height = 704;
const block_num = (screen_width * screen_height) / (block_width * block_width);

pub fn main() !void {
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

    var pos = Position{
        .x = 0,
        .y = 0,
    };

    var prevTime: u32 = 0;
    var secondsCount: u32 = 0;
    var placementTime: u32 = 0;

    var quit = false;
    while (!quit) {
        var currTime = c.SDL_GetTicks();

        var elapsedTime = (currTime - prevTime);

        secondsCount += elapsedTime;

        if (secondsCount >= 1000) {
            print("tick. {}\n", .{secondsCount});
            secondsCount = 0;

            move_down(&pos);
        }

        if (placement_available(&pos)) {
            placementTime += elapsedTime;
        }

        if (placementTime > 3) {
            place_block(&pos);
            placementTime = 0;
        }

        prevTime = currTime;

        var event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => {
                    quit = true;
                },

                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_LEFT => {
                            move_left(&pos);
                        },
                        c.SDLK_RIGHT => {
                            move_right(&pos);
                        },
                        c.SDLK_UP => {},
                        c.SDLK_DOWN => {
                            move_down(&pos);
                        },
                        114 => { // r
                            pos.x = 0;
                            pos.y = 0;
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

        render_background(renderer);

        render_block(renderer, &pos);

        c.SDL_Delay(17);
    }
}

pub fn render_background(renderer: *c.SDL_Renderer) void {
    _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
    _ = c.SDL_RenderClear(renderer);
}

pub fn render_block(renderer: *c.SDL_Renderer, pos: *Position) void {
    _ = c.SDL_SetRenderDrawColor(renderer, 0, 0xff, 0, 0xff);
    const rect = c.SDL_Rect{ .x = pos.x, .y = pos.y, .w = block_width, .h = block_width };

    _ = c.SDL_RenderFillRect(renderer, &rect);

    c.SDL_RenderPresent(renderer);
}

pub fn place_block(pos: *Position) void {
    print("place {},{}", .{ pos.x, pos.y });
}

pub fn placement_available(pos: *Position) bool {
    return (pos.y >= (screen_height - 2 * block_width));
}

pub fn move_left(pos: *Position) void {
    if (pos.x > 0) pos.x -= block_width;
}

pub fn move_right(pos: *Position) void {
    if (pos.x <= (screen_width - 2 * block_width)) pos.x += block_width;
}

pub fn move_down(pos: *Position) void {
    if (pos.y <= (screen_height - 2 * block_width)) pos.y += block_width;
}
