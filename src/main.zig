// Zig Documentation — https://ziglang.org/documentation/master/#Case-Study-printf-in-Zig
// SDL Documentation — https://www.libsdl.org/release/SDL-1.2.15/docs/html/index.html

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

const Position = struct {
    x: i32,
    y: i32,
};

const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
};

const Input = enum {
    NONE,
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

const block_width = 32;
const screen_width = 384 + 256;
const screen_height = 704 + 128;
const grid_width = 10; // 10 block_widths across
const grid_height = 20; // 20 block_widths down
const boundary_width = (grid_width * block_width);
const boundary_height = (grid_height * block_width);

const allocator: std.mem.Allocator = std.heap.page_allocator;

const State = struct {
    const Self = @This();

    time_delta: u32,
    curr_time: u32,

    tet: Position,
    tet_drop: bool = false,
    tet_drop_speed: u32 = 1,
    tet_drop_max_speed_ms: u32 = 2000,
    tet_drop_timer: u32 = 0,

    pub fn reset(self: *Self) void {
        self.tet_drop = false;
        self.tet_drop_speed = 500;
        self.tet_drop_max_speed_ms = 1000;
        self.tet_drop_timer = 0;
        self.time_delta = 0;
        self.curr_time = 0;
        self.tet.x = 0;
        self.tet.y = 0;
    }

    pub fn process(self: *Self, events: []Event) void {

        for (events) |event| {
            self.time_delta = event.time - self.curr_time;
            self.curr_time = event.time;

            print("event = {} \n time_delta = {} \n curr_time = {} \n", .{event, self.time_delta, self.curr_time});

            if (self.tet_drop) {

                // TODO(AW) Turn this into the consistent drop and then do
                //          a separate one for the placement
                self.tet_drop_timer += self.time_delta;

                if (self.tet_drop_timer >= (self.tet_drop_max_speed_ms / self.tet_drop_speed)) {
                    // every 1 second we drop
                    self.tet_drop_timer = 0;
                    const next = .{ .x = self.tet.x, .y = self.tet.y + 1 };
                    print("drop next = {} \n", .{next});
                    self.move(next);

                }
            }

            switch (event.input) {
                Input.MOVE_LEFT => {
                    if (self.ignore_input()) break;
                    const next = .{ .x = self.tet.x - 1, .y = self.tet.y };
                    self.move(next);
                },
                Input.MOVE_RIGHT => {
                    if (self.ignore_input()) break;
                    const next = .{ .x = self.tet.x + 1, .y = self.tet.y };
                    self.move(next);
                },
                Input.MOVE_DOWN => {
                    if (self.ignore_input()) break;
                    const next = .{ .x = self.tet.x, .y = self.tet.y + 1 };
                    self.move(next);
                },
                Input.PLACE_TETROMINO => {
                    if (self.ignore_input()) break;

                    // TODO(AW): Moving tet down based on time delta
                    self.tet_drop = true;

                },
                else => {}
            }

        }

    }

    pub fn ignore_input(self: Self) bool {
        return self.tet_drop;
    }

    pub fn possible_move(_: Self, next: Position) bool {
        if (next.x < 0) return false;
        if (next.x > grid_width - 1) return false;
        if (next.y < 0) return false;
        if (next.y > grid_height - 1) return false;
        return true;
    }

    pub fn move(self: *Self, next: Position) void {
        if (!self.possible_move(next)) return;
        self.tet = next;
    }

};

pub fn main() !void {

    // ##### SDL SETUP
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("Tetris", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, screen_width, screen_height, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    var state = try allocator.create(State);
    defer allocator.destroy(state);
    state.reset();

    var index: usize = 0;

    var quit = false;

    var prev_time: u32 = 0;
    var curr_time = c.SDL_GetTicks();
    var last_tick_event: u32 = 0;

    while (!quit) {

        prev_time = curr_time;
        curr_time = c.SDL_GetTicks();

        if (curr_time - last_tick_event > 15) {
            last_tick_event = curr_time;
            print("append event {}    events.length = {}\n", .{curr_time, events.items.len});
            const event: Event = .{ .input = Input.NONE, .time =  curr_time };
            try events.append(event);
        }

        var sdl_event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&sdl_event) != 0) {
            switch (sdl_event.@"type") {
                c.SDL_QUIT => { quit = true; },
                c.SDL_KEYDOWN => {

                    switch (sdl_event.key.keysym.sym) {
                        114 => { // r
                            print("Replay events from beginning. Resetting state \n", .{});
                            state.reset();
                            index = 0;
                        },
                        else => {

                            const input = sdl_event_to_input(sdl_event);
                            if (input == Input.NONE) break;
                            print("game_event = {} \n", .{input});

                            const event: Event = .{ .input = input, .time =  curr_time };

                            try events.append(event);

                        }
                    }
                },
                c.SDL_KEYUP => { print("keyup event: {}\n", .{sdl_event.@"key".keysym.sym}); },
                else => {},
            }
        }

        if (index < events.items.len) {
            state.process(events.items[index..(index+1)]);
            index += 1;
        }

        // Render Background
        _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
        _ = c.SDL_RenderClear(renderer);

        {
            const x = 1 * block_width;
            const y = 4 * block_width;

            const rect = c.SDL_Rect{ .x = x, .y = y, .w = boundary_width, .h = boundary_height };
            _ = c.SDL_SetRenderDrawColor(renderer, 0xef, 0xef, 0xef, 0xff);
            _ = c.SDL_RenderFillRect(renderer, &rect);
        }
        // Tetromino Blocks
        {
            // Offsets of the grid for rendering
            var x: c_int = 1;
            var y: c_int = 4;

            x += state.tet.x;
            y += state.tet.y;

            x *= block_width;
            y *= block_width;

            const rect = c.SDL_Rect{ .x = x, .y = y, .w = block_width, .h = block_width };
            _ = c.SDL_SetRenderDrawColor(renderer, 0xcc, 0xcc, 0xff, 0xff);
            _ = c.SDL_RenderFillRect(renderer, &rect);

        }

        // Finish Render
        c.SDL_RenderPresent(renderer);
    }
}

pub fn sdl_event_to_input(sdl_event: c.SDL_Event) Input {
    switch (sdl_event.key.keysym.sym) {
        c.SDLK_LEFT => { return Input.MOVE_LEFT; },
        c.SDLK_RIGHT => { return Input.MOVE_RIGHT; },
        c.SDLK_DOWN => { return Input.MOVE_DOWN; },
        c.SDLK_UP => { return Input.ROTATE; },
        32 => { return Input.PLACE_TETROMINO;  }, // spacebar
        else => {},
    }
    return Input.NONE;
}