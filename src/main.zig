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

const Block = struct {
    pos: Position,
    min: Position,
    max: Position,
    rotationIndex: u32, // index into the rotation dim-2
    rotationOffset: u32, // offset from the rotation index 0 - 3
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
const boundary_height = (screen_height - 2 * block_width);
const block_num = (screen_width * screen_height) / (block_width * block_width);

var placed_blocks_count = 0;
const blocks: []Block = .{} * block_num;

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

    var block = Block{
        .pos = .{
            .x = 0,
            .y = 0,
        },
        .min = .{
            .x = 0,
            .y = 0,
        },
        .max = .{
            .x = 0,
            .y = 0,
        },
        .rotationIndex = 8,
        .rotationOffset = 0,
    };

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
            secondsCount = 0;

            move_down(&block);
        }

        if (fastMoveDown) {
            move_down(&block);
        }

        if (placement_available(&block.pos)) {
            fastMoveDown = false;
            placementTime += elapsedTime;
        }

        if (placementTime > 3) {
            place_block(&block);
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
                            move_left(&block);
                        },
                        c.SDLK_RIGHT => {
                            move_right(&block);
                        },
                        c.SDLK_UP => {
                            rotate(&block);
                            bounds_bounce_block(&block);
                        },
                        c.SDLK_DOWN => {
                            move_down(&block);
                        },
                        32 => {
                            print("fast move down enabled", .{});
                            fastMoveDown = true;
                        },
                        114 => { // r
                            reset_block(&block);
                        },
                        44 => {
                            if (block.rotationIndex == 0) block.rotationIndex = rotations.len;
                            block.rotationIndex -= 4;
                            block.rotationOffset = 0;
                            bounds_bounce_block(&block);
                        },
                        46 => {
                            block.rotationIndex += 4;
                            if (block.rotationIndex >= rotations.len) block.rotationIndex = 0;
                            block.rotationOffset = 0;
                            bounds_bounce_block(&block);
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

        render_block(renderer, &block);

        c.SDL_Delay(17);
    }
}

pub fn render_background(renderer: *c.SDL_Renderer) void {
    _ = c.SDL_SetRenderDrawColor(renderer, 96, 128, 255, 255);
    _ = c.SDL_RenderClear(renderer);
}

pub fn render_block(renderer: *c.SDL_Renderer, block: *Block) void {
    const rotatinOffset = get_rotation(block);

    for (rotatinOffset) |offset| {
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0xff, 0, 0xff);

        const x = (offset.x * 32) + block.pos.x;
        const y = (offset.y * 32) + block.pos.y;

        const rect = c.SDL_Rect{ .x = x, .y = y, .w = block_width, .h = block_width };

        _ = c.SDL_RenderFillRect(renderer, &rect);
    }

    c.SDL_RenderPresent(renderer);
}

pub fn get_rotation_offset_max_x(block: *Block) c_int {
    const rotatinOffset = get_rotation(block);

    var maxx = rotatinOffset[0].x;

    for (rotatinOffset) |offset| {
        if (offset.x > maxx) maxx = offset.x;
    }

    return maxx;
}

pub fn get_rotation_offset_min_x(block: *Block) c_int {
    const rotatinOffset = get_rotation(block);

    var minx = rotatinOffset[0].x;

    for (rotatinOffset) |offset| {
        if (offset.x < minx) minx = offset.x;
    }

    return minx;
}

pub fn get_min_x(block: *Block) c_int {
    return block.pos.x + (get_rotation_offset_min_x(block) * block_width);
}

pub fn get_max_x(block: *Block) c_int {
    return block.pos.x + (get_rotation_offset_max_x(block) * block_width);
}

pub fn get_min_y(block: *Block) c_int {
    const rotatinOffset = get_rotation(block);

    var miny = rotatinOffset[0].y * 32 + block.pos.y;

    for (rotatinOffset) |offset| {
        const y = (offset.y * 32) + block.pos.y;
        if (y < miny) miny = y;
    }

    return miny;
}

pub fn get_rotation_offset_max_y(block: *Block) c_int {
    const rotatinOffset = get_rotation(block);

    var maxy = rotatinOffset[0].y;

    for (rotatinOffset) |offset| {
        if (offset.y > maxy) maxy = offset.y;
    }

    return maxy;
}

pub fn get_max_y(block: *Block) c_int {
    return block.pos.y + get_rotation_offset_max_y(block) * block_width;
}

pub fn get_rotation(block: *Block) *const [4]Position {
    return &rotations[block.rotationIndex + block.rotationOffset];
}

pub fn rotate(block: *Block) void {
    block.rotationOffset += 1;
    if (block.rotationOffset >= 4) block.rotationOffset = 0;
}

pub fn bounds_bounce_block(block: *Block) void {
    if (get_min_x(block) < block_width) {
        var abs_left_width = get_rotation_offset_min_x(block) * block_width;
        if (abs_left_width < 0) abs_left_width *= -1;
        block.pos.x = block_width + abs_left_width;
    }
    if (get_max_x(block) > boundary_width) block.pos.x = boundary_width - (get_rotation_offset_max_x(block) * block_width);
    if (get_max_y(block) > boundary_height) block.pos.y = boundary_height - (get_rotation_offset_max_y(block) * block_width);
}

pub fn place_block(block: *Block) void {
    print("place {},{}", .{ block.pos.x, block.pos.y });
    blocks
}

pub fn placement_available(pos: *Position) bool {
    return (pos.y >= (screen_height - 2 * block_width));
}

pub fn move_left(block: *Block) void {
    if (get_min_x(block) > block_width) block.pos.x -= block_width;
}

pub fn move_right(block: *Block) void {
    if (get_max_x(block) < boundary_width) block.pos.x += block_width;
}

pub fn move_down(block: *Block) void {
    if (get_max_y(block) < boundary_height) block.pos.y += block_width;
}

pub fn reset_block(block: *Block) void {
    block.pos.x = 0;
    block.pos.y = 0;
}
