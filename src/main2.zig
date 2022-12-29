// Zig Documentation — https://ziglang.org/documentation/master/#Case-Study-printf-in-Zig
// SDL Documentation — https://www.libsdl.org/release/SDL-1.2.15/docs/html/index.html

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

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
    held_by_tetromino: bool,
    placed: bool,
    visible: bool,
    coords: Coordinates,
    colour: Colour,
};

const Grid = struct {
    colour: Colour,
};

const Field = struct {
    coords: *Coordinates,
    grid: []Grid,
};

const block_width = 32;
const screen_width = 384 + 256;
const screen_height = 704 + 128;
const boundary_width = (384 - 2 * block_width);
const boundary_height = (704 - 2 * block_width);
const grid_width = boundary_width / block_width;
const grid_height = boundary_height / block_width;
const grid_num = grid_width * grid_height;
const block_num = (screen_width * screen_height) / (block_width * block_width);

var state: State = undefined;

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

    const grid = try allocator.alloc(Grid, grid_num);
    for (grid) |_, i| {
        grid[i].colour = .{ .r = 0xef, .g= 0xef, .b= 0xef};
    }

    const field_coords = try allocator.create(Coordinates);
    field_coords.parent = global;
    field_coords.pos.x = 1;
    field_coords.pos.y = 4;

    const field: Field = .{
        .coords = field_coords,
        .grid = grid,
     };

    const blocks: []Block = try allocator.alloc(Block, block_num);
    defer allocator.free(blocks);

    var tet = Tetromino{
        .coords = .{
            .parent = field_coords,
            .pos = .{
                .x = grid_width / 2,
                .y = 0,
            },
        },
        .block_offset = 0,
        .blocks = blocks[0..4],
        .rotation_index = 8,
        .rotation_offset = 0,
    };

    init_tetromino(&tet);

    state = State{
        .global = global,
        .field = field_coords,
        .blocks = blocks,
        .tet = &tet,
    };

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

pub fn render_field(renderer: *c.SDL_Renderer, field: Field) void {

    _ = c.SDL_SetRenderDrawColor(renderer, 0xef, 0xef, 0xef, 0xff);

    const pos = get_absolute_position(field.coords.*);
    const x = pos.x * block_width;
    const y = pos.y * block_width;

    for (field.grid) |grid, i| {

        const gx = @intCast(c_int, ((i % grid_width) * block_width)) + x;
        const gy = @intCast(c_int, ((i / grid_width) * block_width)) + y;

        const grect = c.SDL_Rect{ .x = gx, .y = gy, .w = block_width, .h = block_width };
        _ = c.SDL_SetRenderDrawColor(renderer, grid.colour.r, grid.colour.g, grid.colour.b, 0xff);
        _ = c.SDL_RenderFillRect(renderer, &grect);

    }




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

pub fn get_position_relative_to_parent(coords: Coordinates) Position {
    var pos = coords.pos;
    if (coords.parent) |parent| {
        pos.x += parent.pos.x;
        pos.y += parent.pos.y;
    }
    return pos;
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
    if (max.pos.x >= grid_width) tet.coords.pos.x = grid_width - 2;
    if (max.pos.y > grid_height + 1) tet.coords.pos.y = grid_height;




// TODO(AW): Make a more general approach to hitting objects and
//           bouncing
//
//    for (state.blocks) |block, i| {
//        if (i >= tet.block_offset+4) break;
//        if (block.held_by_tetromino) continue;
//
//        var pos = block.coords.pos;
//
//        const overlap = (pos.x >= min.pos.x and pos.x <= max.pos.x) and
//                        (pos.y >= min.pos.y and pos.y <= max.pos.y);
//
//        no_collisions = no_collisions and !overlap;
//
//        print("collision - {} \n", .{i});
//        print("          - overlap = {} \n", .{overlap});
//        print("          - pos = {} \n", .{pos});
//        print("          - min.pos = {} \n", .{min.pos});
//        print("          - max.pos = {} \n", .{max.pos});
//
//        if (overlap) break;
//
//    }


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
        block.held_by_tetromino = false;

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
    return (max.pos.y >= grid_height - 1);
}

pub fn move_left(tet: *Tetromino) void {
    const position = .{ .x = -1, .y = 0 };
    const rotation = tet.rotation_offset;
    if (valid_move(tet, position, rotation)) apply_move(tet, position);
    bounds_bounce_tetromino(tet);
}

pub fn move_right(tet: *Tetromino) void {
    const position = .{ .x = 1, .y = 0 };
    const rotation = tet.rotation_offset;
    if (valid_move(tet, position, rotation)) apply_move(tet, position);
    bounds_bounce_tetromino(tet);
}

pub fn move_down(tet: *Tetromino) void {
    const position = .{ .x = 0, .y = 1 };
    const rotation = tet.rotation_offset;
    if (valid_move(tet, position, rotation)) apply_move(tet, position);
    bounds_bounce_tetromino(tet);
}

pub fn apply_move(tet: *Tetromino, move: Position) void {
    tet.coords.pos.x += move.x;
    tet.coords.pos.y += move.y;
}

pub fn valid_move(tet: *Tetromino, move: Position, rotation: u32) bool {

    if (move.y < 0) return false;

    var copy = tet.*;
    copy.coords.pos.x += move.x;
    copy.coords.pos.y += move.y;
    copy.rotation_offset = rotation;
    apply_rotation_to_blocks(&copy);

    var no_collision = true;

    for (state.blocks) |sb, i| {
//        if (i >= tet.block_offset+4) break;
        if (!sb.visible) continue;
        if (sb.held_by_tetromino) continue;

        for (copy.blocks) |tb, j| {
            const tb_pos = get_position_relative_to_parent(tb.coords);

            var hit_bounds =
                        (tb_pos.y >= grid_height) and
                        (tb_pos.x >= grid_width - 1) and
                        (tb_pos.x <= 0);

            print("{}{} - hit_bounds = {}\n", .{i, j, hit_bounds});

            print("{}{} - sb_pos = {}\n", .{i, j, sb.coords.pos});
            print("{}{} - tb_pos = {}\n", .{i, j, tb_pos});
            var collision = (sb.coords.pos.x == tb_pos.x and sb.coords.pos.y == tb_pos.y);

            print("{}{} - collision = {}\n", .{i, j, collision});

            no_collision = no_collision and (!hit_bounds and !collision);

            print("{}{} - no_scollision = {}\n", .{i, j, no_collision});

            if (!no_collision) break;
        }

        if (!no_collision) break;
    }


    return no_collision;
}


pub fn rotate(tet: *Tetromino) void {
    const position = .{ .x = 0, .y = 0};
    var rotation = tet.rotation_offset + 1;

    if (rotation >= 4) rotation = 0;
    if (!valid_move(tet, position, rotation)) return;

    tet.rotation_offset = rotation;

    apply_rotation_to_blocks(tet);
    bounds_bounce_tetromino(tet);
}

pub fn init_tetromino(tet: *Tetromino) void {

    tet.coords.pos.x = grid_width / 2;
    tet.coords.pos.y = 0;

    for (tet.blocks) |_, index| {
        const block = &tet.blocks[index];
        block.visible = true;
        block.held_by_tetromino = true;
        block.placed = false;
        block.coords.parent = &tet.coords;
    }

    apply_rotation_to_blocks(tet);
}

pub fn apply_rotation_to_blocks(tet: *Tetromino) void {

    const rotation = get_rotation(tet);

    for (tet.blocks) |_, index| {
        const block = &tet.blocks[index];
        block.coords.pos.x = rotation[index].x;
        block.coords.pos.y = rotation[index].y;
    }
}