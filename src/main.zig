// Zig Documentation — https://ziglang.org/documentation/master/#Case-Study-printf-in-Zig
// SDL Documentation — https://www.libsdl.org/release/SDL-1.2.15/docs/html/index.html

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const rand = std.rand.DefaultPrng;

const Position = struct {
    x: i32,
    y: i32,
};

const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
};

const Block = struct {
    position: Position,
    colour: Colour,
};

const Input = enum {
    NONE,
    MOVE_LEFT,
    STOP_MOVE_LEFT,
    MOVE_RIGHT,
    STOP_MOVE_RIGHT,
    MOVE_DOWN,
    STOP_MOVE_DOWN,
    ROTATE,
    PLACE_TETROMINO,
};

const Event = struct {
    time: u32,
    input: Input,
};

const block_width = 32;
const screen_width = 384 + 256;
const screen_height = 768;
const grid_width = 10; // 10 block_widths across
const grid_height = 20; // 20 block_widths down
const boundary_width = (grid_width * block_width);
const boundary_height = (grid_height * block_width);

const allocator: std.mem.Allocator = std.heap.page_allocator;

var rnd = rand.init(0);


const State = struct {
    const Self = @This();

    paused: bool = false,
    failed: bool = false,

    time_delta: u32,
    curr_time: u32,

    blocks: std.ArrayList(Block),

    up_next: [3]u8,

    tet: Position,
    tet_shape: u8 = 0,
    tet_rotation: u8 = 0,
    tet_blocks: [4]Block,

    move_left: bool = false,
    move_right: bool = false,
    move_down: bool = false,
    moves_timer: u32 = 0,

    // Hit spacebar and this commits to placing it
    tet_commit_place: bool = false,
    tet_commit_place_speed: u32 = 2000,
    tet_commit_place_max_speed_ms: u32 = 2000,
    tet_commit_place_timer: u32 = 0,

    // Timer for turning the tet into block if no movement
    tet_place_timer: u32 = 0,
    tet_place_max_time_ms: u32 = 600,

    // Speed for dropping tetromino
    tet_drop_speed: u32 = 32,
    tet_drop_max_speed_ms: u32 = 2000,
    tet_drop_timer: u32 = 0,

    pub fn reset(self: *Self) !void {

        self.paused = false;
        self.failed = false;

        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        rnd = rand.init(seed);

        self.blocks = std.ArrayList(Block).init(allocator);

        self.tet_commit_place = false;
        self.tet_commit_place_speed = 2000;
        self.tet_commit_place_max_speed_ms = 2000;
        self.tet_commit_place_timer = 0;

        self.tet_place_timer = 0;
        self.tet_place_max_time_ms = 1000;

        self.tet_drop_speed = 14;
        self.tet_drop_max_speed_ms = 1000;
        self.tet_drop_timer = 0;

        self.time_delta = 0;
        self.curr_time = 0;

        self.up_next = [3]u8{
            self.random_shape(),
            self.random_shape(),
            self.random_shape()
        };

        self.reset_tet();

    }

    pub fn reset_tet(self: *Self) void {

        self.tet.x = grid_width/2 - 1;
        self.tet.y = 1;
        self.tet_shape = self.up_next[0];
        self.tet_rotation = 0;

        self.tet_blocks = self.project_blocks(self.tet, self.tet_rotation);
    }

    pub fn next_tet(self: *Self) void {

        self.reset_tet();

        self.tet_shape = self.up_next[0];
        self.up_next[0] = self.up_next[1];
        self.up_next[1] = self.up_next[2];
        self.up_next[2] = self.random_shape();

    }

    pub fn process(self: *Self, events: []Event) !usize {

        var processed_count: usize  = 0;

        if (self.failed or self.paused) return 0;

        for (events) |event| {

            processed_count += 1;

            self.time_delta = event.time - self.curr_time;
            self.curr_time = event.time;

            var next_down  = .{ .x = self.tet.x,      .y = self.tet.y + 1 };

            if (self.tet_commit_place) {

                self.tet_commit_place_timer += self.time_delta;
                self.tet_commit_place_timer = 0;
                self.move(next_down, self.tet_rotation);

                // If it can't move down anymore, we place the tet and add as blocks
                if (!self.possible_move(next_down, self.tet_rotation)) {
                    try self.place_tet();
                }
            }

            // Timer based placement if movement down is not possible
            if (!self.possible_move(next_down, self.tet_rotation)) {
                self.tet_place_timer += self.time_delta;

                if (self.tet_place_timer >= self.tet_place_max_time_ms) {
                    self.tet_place_timer = 0;
                    try self.place_tet();
                }
            } else {
                self.tet_place_timer = 0;
            }

            self.tet_drop_timer += self.time_delta;

            if (self.tet_drop_timer >= (self.tet_drop_max_speed_ms / self.tet_drop_speed)) {
                // every 1 second we drop
                self.tet_drop_timer = 0;
                const next = .{ .x = self.tet.x, .y = self.tet.y + 1 };
                self.move(next, self.tet_rotation);

            }


            switch (event.input) {
                Input.MOVE_LEFT => {
                    if (self.ignore_input()) break;
                    self.move_left = true;
                },
                Input.STOP_MOVE_LEFT => {
                    if (self.ignore_input()) break;
                    self.move_left = false;
                },
                Input.MOVE_RIGHT => {
                    if (self.ignore_input()) break;
                    self.move_right = true;
                },
                Input.STOP_MOVE_RIGHT => {
                    if (self.ignore_input()) break;
                    self.move_right = false;
                },
                Input.MOVE_DOWN => {
                    if (self.ignore_input()) break;
                    self.move_down = true;
                },
                Input.STOP_MOVE_DOWN => {
                    if (self.ignore_input()) break;
                    self.move_down = false;
                },
                Input.ROTATE => {
                    if (self.ignore_input()) break;
                    const next = .{ .x = self.tet.x, .y = self.tet.y };
                    var next_rotation = self.tet_rotation + 1;
                    if (next_rotation > 3) next_rotation = 0;

                    if (self.possible_move(next, next_rotation)) {
                        self.move(next, next_rotation);
                    } else {
                        // Rotation not possible directly but we
                        // might be able to do a 'bounce'

                        // Check every direction of a possible bounce
                        // with the given rotation, pick the first one

                        const up_bounce     = .{ .x = self.tet.x,       .y = self.tet.y - 1 };
                        const down_bounce   = .{ .x = self.tet.x,       .y = self.tet.y + 1 };
                        const left_bounce   = .{ .x = self.tet.x - 1,   .y = self.tet.y     };
                        const right_bounce  = .{ .x = self.tet.x + 1,   .y = self.tet.y     };

                        const bounces = [_]Position{ up_bounce, down_bounce, left_bounce, right_bounce };
                        for (bounces) |bounce| {
                            if (self.possible_move(bounce, next_rotation)) {
                                self.move(bounce, next_rotation);
                                break;
                            }
                        }

                        //long boys are special
                        const double_left_bounce   = .{ .x = self.tet.x - 2,   .y = self.tet.y     };
                        if (self.tet_shape == 1 and self.possible_move(double_left_bounce, next_rotation)) {
                            self.move(double_left_bounce, next_rotation);
                        }

                    }
                },
                Input.PLACE_TETROMINO => {
                    if (self.ignore_input()) break;
                    self.move_left = false;
                    self.move_right = false;
                    self.tet_commit_place = true;

                },
                else => {

                }
            }

            self.moves_timer += self.time_delta;

            if (self.moves_timer >= 60) {

                self.moves_timer = 0;

                if (self.move_left) {
                    const next = .{ .x = self.tet.x - 1, .y = self.tet.y };
                    self.move(next, self.tet_rotation);
                }

                if (self.move_right) {
                    const next = .{ .x = self.tet.x + 1, .y = self.tet.y };
                    self.move(next, self.tet_rotation);
                }

                if (self.move_down) {
                    const next = .{ .x = self.tet.x, .y = self.tet.y + 1 };
                    self.move(next, self.tet_rotation);
                }

            }

            {
                next_down  = .{ .x = self.tet.x,      .y = self.tet.y + 1 };
                const next_left  = .{ .x = self.tet.x - 1,  .y = self.tet.y     };
                const next_right = .{ .x = self.tet.x + 1,  .y = self.tet.y     };

                if (self.tet.y == 1 and
                    !self.possible_move(next_down, self.tet_rotation) and
                    !self.possible_move(next_left, self.tet_rotation) and
                    !self.possible_move(next_right, self.tet_rotation)
                ) {
                    self.failed = true;
                }

            }

        }

        return processed_count;
    }

    pub fn full_row(self: Self, row: i32) bool {
        var grid_x: i32 = 0;
        while (grid_x < grid_width): (grid_x += 1) {
            if (!self.block_exists_at_position(.{ .x = grid_x, .y = row })) {
                return false;
            }
        }
        return true;
    }

    pub fn block_exists_at_position(self: Self, pos: Position) bool {
        for (self.blocks.items) |block| {
            if (block.position.x != pos.x or block.position.y != pos.y) continue;
            return true;
        }
        return false;
    }

    pub fn ignore_input(self: Self) bool {
        return self.tet_commit_place;
    }

    pub fn possible_move(self: Self, next: Position, rotation: u8) bool {

        const next_blocks = self.project_blocks(next, rotation);

        for (next_blocks) |next_block| {
            if (next_block.position.x < 0) return false;
            if (next_block.position.x > grid_width - 1) return false;
            if (next_block.position.y > grid_height - 1) return false;

            for (self.blocks.items) |block| {
                if (next_block.position.x == block.position.x and
                    next_block.position.y == block.position.y) return false;
            }
        }

        return true;
    }

    pub fn move(self: *Self, next: Position, rotation: u8) void {
        if (!self.possible_move(next, rotation)) return;
        self.tet = next;
        self.tet_rotation = rotation;
        self.tet_blocks = self.project_blocks(next, rotation);
    }

    pub fn project_blocks(self: Self, pos: Position, rotation: u8) [4]Block {
        return State.project_generic_blocks(self.tet_shape, pos, rotation);
    }

    pub fn project_generic_blocks(shape: u8, pos: Position, rotation: u8) [4]Block {
        const rotations = shape_rotations[shape][rotation];
        return [4]Block{
            .{
                .position = .{ .x = pos.x + rotations[0].x, .y = pos.y + rotations[0].y },
                .colour = shape_colours[shape],
            },
            .{
                .position = .{ .x = pos.x + rotations[1].x, .y = pos.y + rotations[1].y },
                .colour = shape_colours[shape],
            },
            .{
                .position = .{ .x = pos.x + rotations[2].x, .y = pos.y + rotations[2].y },
                .colour = shape_colours[shape],
            },
            .{
                .position = .{ .x = pos.x + rotations[3].x, .y = pos.y + rotations[3].y },
                .colour = shape_colours[shape],
            }
        };
    }

    pub fn random_shape(_: Self) u8 {
        return rnd.random().int(u8) % @as(u8, shape_rotations.len);
    }

    pub fn random_colour(_: Self) u8 {
        return rnd.random().int(u8) % @as(u8, shape_colours.len);
    }

    pub fn place_tet(self: *Self) !void {

        // Create blocks in tets current position
        for (self.tet_blocks) |block| {
            try self.blocks.append(block);
        }

        var down_movement: i32 = 0;
        var grid_y: i32 = grid_height;
        while (grid_y > 0): (grid_y -= 1) {
            if (self.full_row(grid_y)) {
                down_movement += 1;
                for (self.blocks.items) |_| {
                    var block = self.blocks.orderedRemove(0);
                    // Reinsert if not on this current row
                    if (block.position.y != grid_y) try self.blocks.append(block);
                }
            } else {
                for (self.blocks.items) |block, index| {
                    if (block.position.y != grid_y) continue;
                    self.blocks.items[index].position.y += down_movement;
                }
            }
        }

        // Place disabled
        self.tet_commit_place = false;

        self.next_tet();

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
    try state.reset();

    var index: usize = 0;

    var quit = false;

    var prev_time: u32 = 0;
    var curr_time = c.SDL_GetTicks();
    var last_tick_event: u32 = 0;

    var paused = false;

    while (!quit) {

        prev_time = curr_time;

        {
            var delta = c.SDL_GetTicks() - prev_time;
            if (delta < 16) c.SDL_Delay(16 - delta);
        }

        curr_time = c.SDL_GetTicks();

        {
            last_tick_event = curr_time;
            const event: Event = .{ .input = Input.NONE, .time =  curr_time };
            try events.append(event);
        }

        var sdl_event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&sdl_event) != 0) {
            switch (sdl_event.@"type") {
                c.SDL_QUIT => { quit = true; },
                c.SDL_KEYDOWN => {

                    switch (sdl_event.key.keysym.sym) {
                        112 => { // p
                            state.paused = !state.paused;
                        },
                        114 => { // r

                            allocator.destroy(state);
                            state = try allocator.create(State);

                            events.deinit();
                            events = std.ArrayList(Event).init(allocator);

                            index = 0;
                            try state.reset();
                        },
                        116 => { // t
                            try state.reset();
                            index = 0;
                        },
                        else => {

                            const input = sdl_keydown_event_to_input(sdl_event);
                            if (input == Input.NONE) break;

                            if (state.failed and sdl_event.key.keysym.sym == 32) {

                                allocator.destroy(state);
                                state = try allocator.create(State);

                                events.deinit();
                                events = std.ArrayList(Event).init(allocator);

                                index = 0;
                                try state.reset();

                            } else {
                                const event: Event = .{ .input = input, .time =  curr_time };
                                try events.append(event);
                            }

                        }
                    }
                },
                c.SDL_KEYUP => {

                    const input = sdl_keyup_event_to_input(sdl_event);
                    if (input == Input.NONE) break;
                    const event: Event = .{ .input = input, .time =  curr_time };
                    try events.append(event);

                },
                else => {},
            }
        }

        if (!paused and index < events.items.len) {
            index += try state.process(events.items[index..]);
        }

        const bg_colour = .{
            .r = 0x64,
            .g = 0x95,
            .b = 0xff
        };

        // Render Background
        _ = c.SDL_SetRenderDrawColor(renderer, bg_colour.r, bg_colour.g, bg_colour.b, 255);
        _ = c.SDL_RenderClear(renderer);

        const grid_offset_x = 1;
        const grid_offset_y = 2;

        {
            const x = grid_offset_x * block_width;
            const y = grid_offset_y * block_width;

            const rect = c.SDL_Rect{ .x = x, .y = y, .w = boundary_width, .h = boundary_height };
            _ = c.SDL_SetRenderDrawColor(renderer, 0xef, 0xef, 0xef, 0xff);
            _ = c.SDL_RenderFillRect(renderer, &rect);
        }

        // Tetromino Blocks
        {
            // Offsets of the grid for rendering
            var x: c_int = grid_offset_x;
            var y: c_int = grid_offset_y;

            for (state.tet_blocks) |block| {

                x = grid_offset_x;
                y = grid_offset_y;

                x += block.position.x;
                y += block.position.y;

                x *= block_width;
                y *= block_width;

                const brect = c.SDL_Rect{ .x = x, .y = y, .w = block_width, .h = block_width };
                _ = c.SDL_SetRenderDrawColor(renderer, block.colour.r, block.colour.g, block.colour.b, 0xff);
                _ = c.SDL_RenderFillRect(renderer, &brect);
            }

        }

        // Placed Blocks
        {

            for (state.blocks.items) |block| {
                var x: c_int = grid_offset_x;
                var y: c_int = grid_offset_y;

                x += block.position.x;
                y += block.position.y;

                x *= block_width;
                y *= block_width;

                const rect = c.SDL_Rect{ .x = x, .y = y, .w = block_width, .h = block_width };
                _ = c.SDL_SetRenderDrawColor(renderer, block.colour.r, block.colour.g, block.colour.b, 0x10);
                _ = c.SDL_RenderFillRect(renderer, &rect);
            }

        }

        // Render box above starting position to hide tet above grid
        {

            const x = grid_offset_x * block_width;
            const y = (grid_offset_y - 4) * block_width;

            const rect = c.SDL_Rect{ .x = x, .y = y, .w = boundary_width, .h = 4 * block_width };
            _ = c.SDL_SetRenderDrawColor(renderer, bg_colour.r, bg_colour.g, bg_colour.b, 255);
            _ = c.SDL_RenderFillRect(renderer, &rect);

        }

        // Render up next box

        {

            const x = (grid_offset_x + grid_width + 2);
            const y = grid_offset_y;

            const rect = c.SDL_Rect{ .x = x * block_width, .y = y * block_width, .w = block_width * 5, .h = block_width * 13 - 15 };
            _ = c.SDL_SetRenderDrawColor(renderer, 0xef, 0xef, 0xef, 0xff);
            _ = c.SDL_RenderFillRect(renderer, &rect);

            const positions = [_]Position{
                .{ .x = x + 2, .y = y + 2 },
                .{ .x = x + 2, .y = y + 6 },
                .{ .x = x + 2, .y = y + 10 },
            };

            for (state.up_next) |shape, i| {
                const blocks = State.project_generic_blocks(shape, positions[i], 0);

                for (blocks) |block| {

                    var brect = c.SDL_Rect{
                        .x = block.position.x * block_width,
                        .y = block.position.y * block_width - 15,
                        .w = block_width,
                        .h = block_width
                    };

                    if (shape == 1) brect.x -= 15;

                    _ = c.SDL_SetRenderDrawColor(renderer, block.colour.r, block.colour.g, block.colour.b, 0x10);
                    _ = c.SDL_RenderFillRect(renderer, &brect);

                }
            }
        }

        // pause overlay
        {
            if (state.paused or state.failed) {

                _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

                const rect = c.SDL_Rect{ .x = 0, .y = 0, .w = screen_width, .h = screen_height };
                _ = c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0x55);
                _ = c.SDL_RenderFillRect(renderer, &rect);

                _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_NONE);

            }

        }

        // Finish Render
        c.SDL_RenderPresent(renderer);
    }
}

pub fn sdl_keydown_event_to_input(sdl_event: c.SDL_Event) Input {
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

pub fn sdl_keyup_event_to_input(sdl_event: c.SDL_Event) Input {
    switch (sdl_event.key.keysym.sym) {
        c.SDLK_LEFT => { return Input.STOP_MOVE_LEFT; },
        c.SDLK_RIGHT => { return Input.STOP_MOVE_RIGHT; },
        c.SDLK_DOWN => { return Input.STOP_MOVE_DOWN; },
        else => {},
    }
    return Input.NONE;
}

const shape_colours = [_]Colour{

  .{ .r = 0xff, .g = 0xc0, .b = 0xcb }, // pink
  .{ .r = 0xad, .g = 0xd8, .b = 0xe6 }, // light blue
  .{ .r = 0xd7, .g = 0xbf, .b = 0xdc }, // purple
  .{ .r = 0xff, .g = 0xd5, .b = 0x80 }, // light orange
  .{ .r = 0xfa, .g = 0x80, .b = 0x72 }, // red
  .{ .r = 0x90, .g = 0xee, .b = 0x90 }, // light green
  .{ .r = 0xf5, .g = 0xe0, .b = 0x50 }, // yellow

};

const shape_rotations = [_][4][4]Position{

    [4][4]Position {
        //
        //[][][]
        //  []
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 } },

        //  []
        //[][]
        //  []
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = -1 }, .{ .x = -1, .y = 0 } },

        //  []
        //[][][]
        //
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = -1 } },

        //  []
        //  [][]
        //  []
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = 0 } },
    },

    [4][4]Position {

        //
        //[][][][]
        //
        [_]Position{ .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 } },

        //  []
        //  []
        //  []
        //  []
        [_]Position{ .{ .x = 0, .y = -1 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = 2 } },

        //
        //[][][][]
        //
        [_]Position{ .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 } },

        //  []
        //  []
        //  []
        //  []
        [_]Position{ .{ .x = 0, .y = -1 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = 2 } },

    },

    [4][4]Position {

        //[]
        //[][][]
        //
        [_]Position{ .{ .x = -1, .y = -1 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 } },

        //  [][]
        //  []
        //  []
        [_]Position{ .{ .x = 1, .y = -1 }, .{ .x = 0, .y = -1 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 } },

        //
        //[][][]
        //    []
        [_]Position{ .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 } },

        //  []
        //  []
        //[][]
        [_]Position{ .{ .x = 0, .y = -1 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 1 } },

    },

    [4][4]Position {

        //    []
        //[][][]
        //
        [_]Position{ .{ .x = 1, .y = -1 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 } },

        //  []
        //  []
        //  [][]
        [_]Position{ .{ .x = 0, .y = -1 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 } },

        //
        //[][][]
        //[]
        [_]Position{ .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = -1, .y = 1 } },

        //[][]
        //  []
        //  []
        [_]Position{ .{ .x = -1, .y = -1 }, .{ .x = 0, .y = -1 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 } },

    },

    [4][4]Position {

        //[][]
        //  [][]
        //
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = -1, .y = -1 } },

        //  []
        //[][]
        //[]
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = -1, .y = 0 }, .{ .x = -1, .y = 1 } },

        //
        //[][]
        //  [][]
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 } },

        //    []
        //  [][]
        //  []
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = -1 }, .{ .x = 0, .y = 1 } },

    },

    [4][4]Position {

        //  [][]
        //[][]
        //
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 } },

        //  []
        //  [][]
        //    []
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 } },

        //
        //  [][]
        //[][]
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 1 } },

        //[]
        //[][]
        //  []
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = -1, .y = -1 }, .{ .x = 0, .y = 1 } },

    },

    [4][4]Position {

        //  [][]
        //  [][]
        //
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 } },

        //  [][]
        //  [][]
        //
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 } },

        //  [][]
        //  [][]
        //
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 } },

        //  [][]
        //  [][]
        //
        [_]Position{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 } }

    }
};
