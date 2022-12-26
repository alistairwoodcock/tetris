// Zig Documentation — https://ziglang.org/documentation/master/#Case-Study-printf-in-Zig
// SDL Documentation — https://www.libsdl.org/release/SDL-1.2.15/docs/html/index.html

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

const State = struct {
    global: *Coordinates,
    field: *Coordinates,
    blocks: []Block,
    tet: *Tetromino,
};

const Coordinates = struct {
    parent: ?*Coordinates,
    pos: Position,
};

const Position = struct {
    x: c_int,
    y: c_int,
};

const Tetromino = struct {
    block_offset: u32,
    blocks: []Block,
    coords: Coordinates,
    rotation_index: u32, // index into the rotation dim-2
    rotation_offset: u32, // offset from the rotation index 0 - 3
};

const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
};

const Block = struct {
    placed: bool,
    visible: bool,
    coords: Coordinates,
    colour: Colour,
};

const rotations = [_][4]Position{
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

    //
    //[][][][]
    //
    [_]Position{ .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 } },

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
};

const block_width = 32;
const screen_width = 384 + 256;
const screen_height = 704 + 128;
const boundary_width = (384 - 2 * block_width);
const boundary_width_blocks = boundary_width / block_width;
const boundary_height = (704 - 2 * block_width);
const boundary_height_blocks = boundary_height / block_width;
const block_num = (screen_width * screen_height) / (block_width * block_width);



var placed_blocks_count = 0;

pub fn main() !void {

    print("{}", .{block_num});

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

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    const global = try allocator.create(Coordinates);
    global.parent = null;
    global.pos.x = 0;
    global.pos.y = 0;

    const field = try allocator.create(Coordinates);
    field.parent = global;
    field.pos.x = 1;
    field.pos.y = 4;

    const blocks: []Block = try allocator.alloc(Block, block_num);
    defer allocator.free(blocks);

    var tet = Tetromino{
        .coords = .{
            .parent = field,
            .pos = .{
                .x = boundary_width_blocks / 2,
                .y = 0,
            },
        },
        .block_offset = 0,
        .blocks = blocks[0..4],
        .rotation_index = 8,
        .rotation_offset = 0,
    };

    init_tetromino(&tet);

    var prev_time: u32 = 0;
    var seconds_count: u32 = 0;
    var placement_time: u32 = 0;

    var fast_move_down: bool = false;

    var quit = false;
    // TODO(AW): Record all events & replay (including time)
    while (!quit) {
        var curr_time = c.SDL_GetTicks();

        var elapsed_time = (curr_time - prev_time);

        seconds_count += elapsed_time;

        if (seconds_count >= 1000) {
            print("tick. {}\n", .{seconds_count});

            seconds_count = 0;

            move_down(&tet);
        }

        // TODO(AW): Check if any movement is possible before
        // allowing the move.
        if (fast_move_down) {
            move_down(&tet);
        }

        if (placement_available(&tet)) {
            fast_move_down = false;
            placement_time += elapsed_time;
        }

        if (placement_time > 3) {
            place_tetromino(&tet, blocks);
            placement_time = 0;
        }

        prev_time = curr_time;

        var event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => {
                    quit = true;
                },

                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_LEFT => {
                            move_left(&tet);
                        },
                        c.SDLK_RIGHT => {
                            move_right(&tet);
                        },
                        c.SDLK_UP => {
                            if (!fast_move_down) rotate(&tet);
                        },
                        c.SDLK_DOWN => {
                            move_down(&tet);
                        },
                        32 => {
                            print("fast move down enabled", .{});
                            fast_move_down = true;
                        },
                        114 => { // r
                            init_tetromino(&tet);
                        },
                        44 => {
                            if (tet.rotation_index == 0) tet.rotation_index = rotations.len;
                            tet.rotation_index -= 4;
                            tet.rotation_offset = 0;
                            bounds_bounce_tetromino(&tet);
                        },
                        46 => {
                            tet.rotation_index += 4;
                            if (tet.rotation_index >= rotations.len) tet.rotation_index = 0;
                            tet.rotation_offset = 0;
                            bounds_bounce_tetromino(&tet);
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

        render_field(renderer, field);

        render_blocks(renderer, blocks);

        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}

pub fn render_background(renderer: *c.SDL_Renderer) void {
    _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
    _ = c.SDL_RenderClear(renderer);
}

pub fn render_field(renderer: *c.SDL_Renderer, field: *Coordinates) void {

    _ = c.SDL_SetRenderDrawColor(renderer, 0xef, 0xef, 0xef, 0xff);

    const pos = get_absolute_position(field.*);
    const x = pos.x * block_width;
    const y = pos.y * block_width;

    const rect = c.SDL_Rect{ .x = x, .y = y, .w = boundary_width, .h = boundary_height };

    _ = c.SDL_RenderFillRect(renderer, &rect);

}

pub fn render_blocks(renderer: *c.SDL_Renderer, blocks: []Block) void {

    var draw = false;

    for (blocks) |block| {
        if (!block.visible) continue;

        draw = true;

        _ = c.SDL_SetRenderDrawColor(renderer, 0, block.colour.r, block.colour.g, block.colour.b);

        const pos = get_absolute_position(block.coords);
        const x = pos.x * block_width;
        const y = pos.y * block_width;

        const rect = c.SDL_Rect{ .x = x, .y = y, .w = block_width, .h = block_width };

        _ = c.SDL_RenderFillRect(renderer, &rect);
    }


}

pub fn get_absolute_position(coords: Coordinates) Position {
    if (coords.parent) |parent| {
        const pos = get_absolute_position(parent.*);
        return .{ .x = coords.pos.x + pos.x, .y = coords.pos.y + pos.y};
    }
    return .{ .x = coords.pos.x, .y = coords.pos.y };
}

pub fn get_max_position(tet: *Tetromino) Position {
    var max_pos = get_absolute_position(tet.blocks[0].coords);
    for (tet.blocks) |block| {
        var pos = get_absolute_position(block.coords);
        if (pos.x > max_pos.x) max_pos.x = pos.x;
        if (pos.y > max_pos.y) max_pos.y = pos.y;
    }
    return max_pos;
}

pub fn get_min_position(tet: *Tetromino) Position {
    var min_pos = get_absolute_position(tet.blocks[0].coords);
    for (tet.blocks) |block| {
        var pos = get_absolute_position(block.coords);
        if (pos.x < min_pos.x) min_pos.x = pos.x;
        if (pos.y < min_pos.y) min_pos.y = pos.y;
    }
    return min_pos;
}

pub fn get_rotation(tet: *Tetromino) *const [4]Position {
    return &rotations[tet.rotation_index + tet.rotation_offset];
}

pub fn bounds_bounce_tetromino(tet: *Tetromino) void {
    const max = get_max_coordinates(tet);
    const min = get_min_coordinates(tet);

    if (min.pos.x < 0) tet.coords.pos.x = 1;
    if (max.pos.x >= boundary_width_blocks) tet.coords.pos.x = boundary_width_blocks - 2;
    if (max.pos.y > boundary_height_blocks + 1) tet.coords.pos.y = boundary_height_blocks;
}

pub fn get_max_coordinates(tet: *Tetromino) Coordinates {
    var max = tet.blocks[0].coords;

    // Max coordinates should be in tet's coords, not it's child blocks coords
    max.pos.x += tet.coords.pos.x;
    max.pos.y += tet.coords.pos.y;

    for (tet.blocks) |block| {
        var pos = block.coords.pos;
        pos.x += tet.coords.pos.x;
        pos.y += tet.coords.pos.y;
        if (pos.x > max.pos.x) max.pos.x = pos.x;
        if (pos.y > max.pos.y) max.pos.y = pos.y;
    }
    return max;
}

pub fn get_min_coordinates(tet: *Tetromino) Coordinates {
    var min = tet.blocks[0].coords;

    // Max coordinates should be in tet's coords, not it's child blocks coords
    min.pos.x += tet.coords.pos.x;
    min.pos.y += tet.coords.pos.y;

    for (tet.blocks) |block| {
        var pos = block.coords.pos;
        pos.x += tet.coords.pos.x;
        pos.y += tet.coords.pos.y;
        if (pos.x < min.pos.x) min.pos.x = pos.x;
        if (pos.y < min.pos.y) min.pos.y = pos.y;
    }
    return min;
}

pub fn place_tetromino(tet: *Tetromino, blocks: []Block) void {
    print("1 - place {},{}\n", .{ tet.coords.pos.x, tet.coords.pos.y });

    bounds_bounce_tetromino(tet);

    for (tet.blocks) |_, index| {

        const block = &tet.blocks[index];
        // Blocks are now free floating where they were placed
        // they're not part of any particular tetromino
        block.placed = true;

        const coords = block.coords;

        var pos = .{ .x = coords.pos.x, .y = coords.pos.y };

        print("2 - place {},{}\n", .{ pos.x, pos.y });

        if (coords.parent) |parent| {

            pos.x += parent.pos.x;
            pos.y += parent.pos.y;

            print("3 - place {},{}\n", .{ pos.x, pos.y });

            if (parent.parent) |grandparent| {

                // The parent is now the global parent instead of the local Tetromino parent
                block.coords.parent = grandparent;
                block.coords.pos.x = pos.x;
                block.coords.pos.y = pos.y;
                block.colour.r = 0xff;
                block.colour.g = 0x00;
                block.colour.b = 0x00;

                print("4 - place {},{}\n", .{ pos.x, pos.y });

            }
        }

    }

    tet.block_offset += 4;
    if (tet.block_offset >= blocks.len) tet.block_offset = 0;

    tet.blocks = blocks[tet.block_offset..tet.block_offset+4];

    init_tetromino(tet);
}

pub fn placement_available(tet: *Tetromino) bool {
    const max = get_max_coordinates(tet);
    return (max.pos.y >= boundary_height_blocks - 1);
}

pub fn move_left(tet: *Tetromino) void {
    const move = .{ .x = -1, .y = 0 };
    if (can_move(tet, move)) apply_move(tet, move);
    bounds_bounce_tetromino(tet);
}

pub fn move_right(tet: *Tetromino) void {
    const move = .{ .x = 1, .y = 0 };
    if (can_move(tet, move)) apply_move(tet, move);
    bounds_bounce_tetromino(tet);
}

pub fn move_down(tet: *Tetromino) void {
    const move = .{ .x = 0, .y = 1 };
    if (can_move(tet, move)) apply_move(tet, move);
    bounds_bounce_tetromino(tet);
}

pub fn apply_move(tet: *Tetromino, move: Position) void {
    tet.coords.pos.x += move.x;
    tet.coords.pos.y += move.y;
}

pub fn can_move(tet: *Tetromino, move: Position) bool {
    var max = get_max_coordinates(tet);
    var min = get_min_coordinates(tet);

    // move the current max and min positions
    // by their next possible movement
    max.pos.x += move.x;
    max.pos.y += move.y;
    min.pos.x += move.x;
    min.pos.y += move.y;

    var no_collisions = true;

    // TODO(AW): Implement collision checking here

    return
        (move.y >= 0) and
        (max.pos.y < boundary_height_blocks) and
        (max.pos.x <= boundary_width_blocks - 1) and
        (min.pos.x >= 0) and
        (no_collisions)
   ;
}


pub fn rotate(tet: *Tetromino) void {
    tet.rotation_offset += 1;
    if (tet.rotation_offset >= 4) tet.rotation_offset = 0;

    const rotation = get_rotation(tet);

    for (tet.blocks) |_, index| {
        tet.blocks[index].coords.pos.x = rotation[index].x;
        tet.blocks[index].coords.pos.y = rotation[index].y;
    }

    bounds_bounce_tetromino(tet);
}

pub fn init_tetromino(tet: *Tetromino) void {

    tet.coords.pos.x = boundary_width_blocks / 2;
    tet.coords.pos.y = 0;

    const rotation = get_rotation(tet);

    for (tet.blocks) |_, index| {
        const block = &tet.blocks[index];
        block.visible = true;
        block.placed = false;
        block.coords.parent = &tet.coords;

        block.coords.pos.x = rotation[index].x;
        block.coords.pos.y = rotation[index].y;
    }

}