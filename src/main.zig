// Zig Documentation — https://ziglang.org/documentation/master/#Case-Study-printf-in-Zig
// SDL Documentation — https://www.libsdl.org/release/SDL-1.2.15/docs/html/index.html

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

const Position = struct {
    x: c_int,
    y: c_int,
};

const Tetromino = struct {
    blocks: *[4]Block,
    pos: Position,
    rotationIndex: u32, // index into the rotation dim-2
    rotationOffset: u32, // offset from the rotation index 0 - 3
};

const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
};

const Block = struct {
    pos: Position,
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
const screen_width = 384;
const screen_height = 704;
const boundary_width = (screen_width - 2 * block_width);
const boundary_width_blocks = boundary_width / block_width;
const boundary_height = (screen_height - 2 * block_width);
const boundary_height_blocks = boundary_height / block_width;
const block_num = (screen_width * screen_height) / (block_width * block_width);

var placed_blocks_count = 0;


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

    const allocator: std.mem.Allocator = std.heap.page_allocator; // this is not the best choice of allocator, see below.
    const blocks: []Block = try allocator.alloc(Block, block_num);
    defer allocator.free(blocks);

    var tet = Tetromino{
        .pos = .{
            .x = 0,
            .y = 0,
        },
        .blocks = blocks[0..4],
        .rotationIndex = 8,
        .rotationOffset = 0,
    };

    reset_tetromino(&tet);

    var prevTime: u32 = 0;
    var secondsCount: u32 = 0;
    var placementTime: u32 = 0;

    var fastMoveDown: bool = false;

    var quit = false;
    while (!quit) {
        var currTime = c.SDL_GetTicks();

        var elapsedTime = (currTime - prevTime);

        secondsCount += elapsedTime;

        if (secondsCount >= 1000) {
            print("tick. {}\n", .{secondsCount});

            print("place {},{}, min_x = {}", .{ tet.pos.x, tet.pos.y, get_min_x(&tet) });

            secondsCount = 0;

            move_down(&tet);
        }

        if (fastMoveDown) {
            move_down(&tet);
        }

        if (placement_available(&tet)) {
            fastMoveDown = false;
            placementTime += elapsedTime;
        }

        if (placementTime > 3) {
            place_tetromino(&tet);
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
                            move_left(&tet);
                        },
                        c.SDLK_RIGHT => {
                            move_right(&tet);
                        },
                        c.SDLK_UP => {
                            rotate(&tet);
                            bounds_bounce_tetromino(&tet);
                        },
                        c.SDLK_DOWN => {
                            move_down(&tet);
                        },
                        32 => {
                            print("fast move down enabled", .{});
                            fastMoveDown = true;
                        },
                        114 => { // r
                            reset_tetromino(&tet);
                        },
                        44 => {
                            if (tet.rotationIndex == 0) tet.rotationIndex = rotations.len;
                            tet.rotationIndex -= 4;
                            tet.rotationOffset = 0;
                            bounds_bounce_tetromino(&tet);
                        },
                        46 => {
                            tet.rotationIndex += 4;
                            if (tet.rotationIndex >= rotations.len) tet.rotationIndex = 0;
                            tet.rotationOffset = 0;
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

        render_tetromino(renderer, &tet);

        c.SDL_Delay(17);
    }
}

pub fn render_background(renderer: *c.SDL_Renderer) void {
    _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
    _ = c.SDL_RenderClear(renderer);
}

pub fn render_tetromino(renderer: *c.SDL_Renderer, tet: *Tetromino) void {

    for (tet.blocks) |block| {
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0xff, 0, 0xff);

        const x = (block.pos.x + tet.pos.x) * block_width;
        const y = (block.pos.y + tet.pos.y) * block_width;
        const rect = c.SDL_Rect{ .x = x, .y = y, .w = block_width, .h = block_width };

        _ = c.SDL_RenderFillRect(renderer, &rect);
    }

    c.SDL_RenderPresent(renderer);
}

pub fn get_rotation_offset_max_x(tet: *Tetromino) c_int {
    const rotatinOffset = get_rotation(tet);

    var maxx = rotatinOffset[0].x;

    for (rotatinOffset) |offset| {
        if (offset.x > maxx) maxx = offset.x;
    }

    return maxx;
}

pub fn get_min_x(tet: *Tetromino) c_int {
    var min_x = tet.blocks[0].pos.x;
    for (tet.blocks) |block| {
        if (block.pos.x < min_x) min_x = block.pos.x;
    }
    return min_x + tet.pos.x;
}

pub fn get_max_x(tet: *Tetromino) c_int {
    var max_x = tet.blocks[0].pos.x;
    for (tet.blocks) |block| {
        if (block.pos.x > max_x) max_x = block.pos.x;
    }
    return max_x + tet.pos.x;
}

pub fn get_min_y(tet: *Tetromino) c_int {
    var min_y = tet.blocks[0].y;
    for (tet.blocks) |block| {
        if (block.y < min_y) min_y = block.y;
    }
    return min_y + tet.pos.y;
}

pub fn get_rotation_offset_max_y(tet: *Tetromino) c_int {
    const rotatinOffset = get_rotation(tet);

    var maxy = rotatinOffset[0].y;

    for (rotatinOffset) |offset| {
        if (offset.y > maxy) maxy = offset.y;
    }

    return maxy;
}

pub fn get_max_y(tet: *Tetromino) c_int {
    var max_y = tet.blocks[0].pos.y;
    for (tet.blocks) |block| {
        if (max_y < block.pos.y) max_y = block.pos.y;
    }
    return max_y + tet.pos.y;
}

pub fn get_rotation(tet: *Tetromino) *const [4]Position {
    return &rotations[tet.rotationIndex + tet.rotationOffset];
}

pub fn rotate(tet: *Tetromino) void {
    tet.rotationOffset += 1;
    if (tet.rotationOffset >= 4) tet.rotationOffset = 0;
    set_blocks_to_rotation(tet);
}

pub fn bounds_bounce_tetromino(tet: *Tetromino) void {
    if (get_min_x(tet) <= 1) tet.pos.x = 2;
    if (get_max_x(tet) > boundary_width_blocks) tet.pos.x = boundary_width_blocks - 1;
    if (get_max_y(tet) > boundary_height_blocks) tet.pos.y = boundary_height_blocks - 1;
}

pub fn place_tetromino(tet: *Tetromino) void {
     print("place {},{}", .{ tet.pos.x, tet.pos.y });
    // block
}

pub fn placement_available(tet: *Tetromino) bool {
    const max_y = get_max_y(tet);
    return (max_y >= boundary_height_blocks);
}

pub fn move_left(tet: *Tetromino) void {
    if (get_min_x(tet) > 1) tet.pos.x -= 1;
}

pub fn move_right(tet: *Tetromino) void {
    if (get_max_x(tet) < boundary_width_blocks) tet.pos.x += 1;
}

pub fn move_down(tet: *Tetromino) void {
    if (get_max_y(tet) < boundary_height_blocks) tet.pos.y += 1;
}

pub fn reset_tetromino(tet: *Tetromino) void {

    tet.pos.x = boundary_width_blocks / 2;
    tet.pos.y = 0;

    set_blocks_to_rotation(tet);
}

pub fn set_blocks_to_rotation(tet: *Tetromino) void {

    const rotation = get_rotation(tet);

    tet.blocks[0].pos.x = rotation[0].x;
    tet.blocks[0].pos.y = rotation[0].y;

    tet.blocks[1].pos.x = rotation[1].x;
    tet.blocks[1].pos.y = rotation[1].y;

    tet.blocks[2].pos.x = rotation[2].x;
    tet.blocks[2].pos.y = rotation[2].y;

    tet.blocks[3].pos.x = rotation[3].x;
    tet.blocks[3].pos.y = rotation[3].y;

}