const std = @import("std");
const zmath = @import("zmath");
const math = std.math;
const rl = @import("raylib");
const Rng = std.rand.DefaultPrng;

const test_allocator = std.testing.allocator;

const epsilon = 0.00000001;

const win_title = "antsy";
const win_width = 800;
const win_height = 800;
const grid_width = 8;
const grid_height = grid_width;
const grid_size_x = win_width / grid_width;
const grid_size_y = win_height / grid_height;
const grid_size = grid_size_x * grid_size_y;

const AntState = enum { exploring, found_food, default };

////////////////////////////////////////////////////
// PHEREMONES
////////////////////////////////////////////////////
const Pheremone = struct {
    from_home: f32,
    to_food: f32,
};

// generated with 1/(dist to particle + 1)^2
// then normalised
var diffusion_distances = [_]f32{ @sqrt(@as(f32, 2)), 1, @sqrt(@as(f32, 2)), 1, 0, 1, @sqrt(@as(f32, 2)), 1, @sqrt(@as(f32, 2)) };

const pheremone_scale = 1;

fn generate_diffusion_pattern(times: f32) [9]f32 {
    var sum: f32 = 0;
    var diffusion_pattern = [_]f32{0} ** 9;
    for (diffusion_distances) |val, i| {
        const k = val + 1;
        diffusion_pattern[i] = 1 / math.pow(f32, k, times);
        sum += diffusion_pattern[i];
    }
    for (diffusion_pattern) |*val| {
        val.* /= sum;
        val.* *= pheremone_scale;
    }
    return diffusion_pattern;
}

const pheremone_diffuse_from_home = 10;
const pheremone_diffuse_to_food = 12;

const PheremoneGrid = struct {
    from_home_grid: [grid_size]f32 = [_]f32{0} ** grid_size,
    to_food_grid: [grid_size]f32 = [_]f32{0} ** grid_size,
    from_home_grid_2: [grid_size]f32 = [_]f32{0} ** grid_size,
    to_food_grid_2: [grid_size]f32 = [_]f32{0} ** grid_size,

    fn get(self: *PheremoneGrid, state: AntState, x: usize, y: usize) f32 {
        switch (state) {
            AntState.exploring => {
                return self.to_food_grid[x + y * grid_size_x];
            },
            AntState.found_food => {
                return self.from_home_grid[x + y * grid_size_x];
            },
            else => {
                unreachable;
            },
        }
    }

    fn add(self: *PheremoneGrid, state: AntState, x: usize, y: usize, amt: f32) void {
        switch (state) {
            AntState.exploring => {
                self.from_home_grid[x + y * grid_size_x] += amt;
            },
            AntState.found_food => {
                self.to_food_grid[x + y * grid_size_x] += amt;
            },
            else => {
                unreachable;
            },
        }
    }

    fn diffuse(self: *PheremoneGrid) void {
        {
            const diffusion_pattern = generate_diffusion_pattern(pheremone_diffuse_from_home);
            for (self.from_home_grid) |home_cell, i| {
                const ii = @intCast(i32, i);
                self.from_home_grid_2[@intCast(usize, @mod(ii - grid_size_x - 1, grid_size))] += diffusion_pattern[0] * home_cell;
                self.from_home_grid_2[@intCast(usize, @mod(ii - grid_size_x + 0, grid_size))] += diffusion_pattern[1] * home_cell;
                self.from_home_grid_2[@intCast(usize, @mod(ii - grid_size_x + 1, grid_size))] += diffusion_pattern[2] * home_cell;
                self.from_home_grid_2[@intCast(usize, @mod(ii - 1, grid_size))] += diffusion_pattern[3] * home_cell;
                self.from_home_grid_2[@intCast(usize, @mod(ii + 0, grid_size))] += diffusion_pattern[4] * home_cell;
                self.from_home_grid_2[@intCast(usize, @mod(ii + 1, grid_size))] += diffusion_pattern[5] * home_cell;
                self.from_home_grid_2[@intCast(usize, @mod(ii + grid_size_x - 1, grid_size))] += diffusion_pattern[6] * home_cell;
                self.from_home_grid_2[@intCast(usize, @mod(ii + grid_size_x + 0, grid_size))] += diffusion_pattern[7] * home_cell;
                self.from_home_grid_2[@intCast(usize, @mod(ii + grid_size_x + 1, grid_size))] += diffusion_pattern[8] * home_cell;
            }
        }
        {
            const diffusion_pattern = generate_diffusion_pattern(pheremone_diffuse_to_food);
            for (self.to_food_grid) |food_cell, i| {
                const ii = @intCast(i32, i);
                self.to_food_grid_2[@intCast(usize, @mod(ii - grid_size_x - 1, grid_size))] += diffusion_pattern[0] * food_cell;
                self.to_food_grid_2[@intCast(usize, @mod(ii - grid_size_x + 0, grid_size))] += diffusion_pattern[1] * food_cell;
                self.to_food_grid_2[@intCast(usize, @mod(ii - grid_size_x + 1, grid_size))] += diffusion_pattern[2] * food_cell;
                self.to_food_grid_2[@intCast(usize, @mod(ii - 1, grid_size))] += diffusion_pattern[3] * food_cell;
                self.to_food_grid_2[@intCast(usize, @mod(ii + 0, grid_size))] += diffusion_pattern[4] * food_cell;
                self.to_food_grid_2[@intCast(usize, @mod(ii + 1, grid_size))] += diffusion_pattern[5] * food_cell;
                self.to_food_grid_2[@intCast(usize, @mod(ii + grid_size_x - 1, grid_size))] += diffusion_pattern[6] * food_cell;
                self.to_food_grid_2[@intCast(usize, @mod(ii + grid_size_x + 0, grid_size))] += diffusion_pattern[7] * food_cell;
                self.to_food_grid_2[@intCast(usize, @mod(ii + grid_size_x + 1, grid_size))] += diffusion_pattern[8] * food_cell;
            }
        }
        std.mem.copy(f32, self.from_home_grid[0..], self.from_home_grid_2[0..]);
        std.mem.set(f32, self.from_home_grid_2[0..], 0);
        std.mem.copy(f32, self.to_food_grid[0..], self.to_food_grid_2[0..]);
        std.mem.set(f32, self.to_food_grid_2[0..], 0);
    }

    fn update(self: *PheremoneGrid) void {
        self.diffuse();
    }

    //TODO: THIS IS *VERY* SLOW
    fn draw(self: *PheremoneGrid, every: u32) void {
        var i: u32 = 0;
        while (i < grid_size) : (i += every) {
            if (@mod(i / grid_size_x, every) == 1 and @mod(i, grid_size_x) == 0) {
                i += grid_size_x * (every - 1);
                if (i >= grid_size) break;
            }
            const col = rl.Color{
                .r = @intCast(u8, 0),
                .g = @floatToInt(u8, @min(self.from_home_grid[i], 255)),
                .b = @floatToInt(u8, @min(self.to_food_grid[i], 255)),
                .a = 255,
            };
            const x = @mod(i, grid_size_x) * grid_width;
            const y = @divFloor(i, grid_size_x) * grid_height;
            rl.DrawRectangle(@intCast(i32, x), @intCast(i32, y), @intCast(i32, grid_width * every), @intCast(i32, grid_height * every), col);
        }
    }
};

//DONE: diffusion through grid
//TODO: vector flow field type beat
//TODO: replace checks for food with similar pheremone idea
//TODO: diff pheremones spread at diff rates
// ok cool

////////////////////////////////////////////////////
// ANTS
////////////////////////////////////////////////////
const ant_speed = 1;
const ant_rad = 2;
const ant_count = 100;
const view_dst = 1;
const threshold = 10;

fn weight_rotation(amt: f32) f32 {
    if (amt < 0) return -amt * amt;
    return amt * amt;
}

const Ant = struct {
    pos: rl.Vector2 = rl.Vector2{ .x = win_width / 2, .y = win_height / 2 },
    dir: f32,
    state: AntState = AntState.exploring,
    carrying: f32 = 0,

    fn move(self: *Ant) void {
        switch (self.state) {
            AntState.exploring, AntState.found_food => {
                const sind: f32 = @sin(self.dir);
                const cosd: f32 = @cos(self.dir);
                self.pos.x += cosd * ant_speed;
                self.pos.y += sind * ant_speed;
                self.pos.x = @mod(self.pos.x, win_width);
                self.pos.y = @mod(self.pos.y, win_width);
            },
            else => {
                std.debug.print("State Not Implemented", .{});
            },
        }
    }

    fn draw(self: *Ant) void {
        switch (self.state) {
            AntState.exploring => {
                rl.DrawCircleV(self.pos, ant_rad, rl.RED);
            },
            AntState.found_food => {
                rl.DrawCircleV(self.pos, ant_rad, rl.GREEN);
            },
            else => {
                unreachable;
            },
        }
    }

    fn emitPheremones(self: *Ant, pheremone_grid: *PheremoneGrid) void {
        const x = @floatToInt(usize, self.pos.x / grid_width);
        const y = @floatToInt(usize, self.pos.y / grid_height);
        switch (self.state) {
            AntState.exploring => {
                pheremone_grid.add(self.state, x, y, 3);
            },
            AntState.found_food => {
                pheremone_grid.add(self.state, x, y, 20);
            },
            else => {
                unreachable;
            },
        }
    }

    fn moveTowardsPheremones(self: *Ant, pheremone_grid: *PheremoneGrid) void {
        const ang = 3.14159265358979 / 4.0;
        const dir_p = self.dir + ang;
        const dir_m = self.dir - ang;
        const x1 = @floatToInt(usize, @mod((self.pos.x + grid_width * @cos(self.dir)) / grid_width, grid_size_x));
        const y1 = @floatToInt(usize, @mod((self.pos.y + grid_height * @sin(self.dir)) / grid_height, grid_size_y));
        const x2 = @floatToInt(usize, @mod((self.pos.x + grid_width * @cos(dir_p)) / grid_width, grid_size_x));
        const y2 = @floatToInt(usize, @mod((self.pos.y + grid_height * @sin(dir_p)) / grid_height, grid_size_y));
        const x3 = @floatToInt(usize, @mod((self.pos.x + grid_width * @cos(dir_m)) / grid_width, grid_size_x));
        const y3 = @floatToInt(usize, @mod((self.pos.y + grid_height * @sin(dir_m)) / grid_height, grid_size_y));

        const Idx = struct {
            d: f32,
            v: f32,
        };
        var state = self.state;
        var flr = [3]Idx{ Idx{ .d = 0, .v = pheremone_grid.get(state, x1, y1) }, Idx{ .d = dir_m, .v = pheremone_grid.get(state, x3, y3) }, Idx{ .d = dir_p, .v = pheremone_grid.get(state, x2, y2) } };
        if (flr[0].v < flr[1].v) {
            const tmp = flr[0];
            flr[0] = flr[1];
            flr[1] = tmp;
        }
        if (flr[1].v < flr[2].v) {
            const tmp = flr[1];
            flr[1] = flr[2];
            flr[2] = tmp;
        }
        if (flr[0].v < flr[1].v) {
            const tmp = flr[0];
            flr[0] = flr[1];
            flr[1] = tmp;
        }

        const ma = flr[0].v;
        if (ma < threshold) {
            return;
        }
        //rl.DrawRectangle(@intCast(i32, x1 * grid_width), @intCast(i32, y1 * grid_width), grid_width, grid_height, rl.RED);
        //rl.DrawRectangle(@intCast(i32, x2 * grid_width), @intCast(i32, y2 * grid_width), grid_width, grid_height, rl.BLUE);
        //rl.DrawRectangle(@intCast(i32, x3 * grid_width), @intCast(i32, y3 * grid_width), grid_width, grid_height, rl.GREEN);
        const se = flr[1].v;
        const ma_dir = flr[0].d;
        const se_dir = flr[1].d;
        const prop = se / ma;
        const new_dir = ma_dir + prop * (se_dir - ma_dir);
        if (@fabs(self.dir - new_dir) > 3.14159265358979) { // dont allow turning 180 degrees
            return;
            //std.debug.print("Stuck in a loop L\n", .{});
        }
        if (false) { // randomly dont follow pheremones

        }
        self.dir = new_dir;
    }

    fn update(self: *Ant, rng: f32, home: *Colony, foods: std.ArrayList(Food), pheremone_grid: *PheremoneGrid) void {
        self.moveTowardsPheremones(pheremone_grid);
        self.dir += weight_rotation(rng - 0.5);
        self.move();
        self.emitPheremones(pheremone_grid);
        switch (self.state) {
            AntState.exploring => {
                for (foods.items) |*food| {
                    const dst = (food.pos.x - self.pos.x) * (food.pos.x - self.pos.x) +
                        (food.pos.y - self.pos.y) * (food.pos.y - self.pos.y);
                    if (dst < 0.25 * food.contained * food.contained) { // intersection
                        self.state = AntState.found_food; // TODO: implement food
                        self.carrying = food.take(5);
                        self.dir -= 3.14159265358979; // turn around !
                    }
                }
            },
            AntState.found_food => {
                const dst = math.pow(f32, (home.home_pos.x - self.pos.x), 2) + math.pow(f32, (home.home_pos.y - self.pos.y), 2);
                if (dst < home.rad) {
                    home.storeFood(self.carrying);
                    self.carrying = 0;
                    self.state = AntState.exploring;
                    self.dir -= 3.14159265358979; // turn around !
                }
            },
            else => {
                std.debug.print("", .{});
            },
        }
    }
};

//////////////////////////////////////////////////////
// COLONY
////////////////////////////////////////////////////
const Colony = struct {
    ants: std.ArrayList(Ant),
    foods: std.ArrayList(Food),
    pheremone_grid: PheremoneGrid,
    home_pos: rl.Vector2,
    rng: std.rand.DefaultPrng,
    tick: usize = 0,
    stored: f32 = 0,
    rad: f32 = 50,

    fn storeFood(self: *Colony, store: f32) void {
        self.stored += store;
    }

    fn spawn_ants(self: *Colony, n: usize) !void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var d = self.rng.random().float(f32) * 6.28;
            try self.ants.append(Ant{ .dir = d });
        }
    }

    fn spawn_foods(self: *Colony, n: usize) !void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const px = self.rng.random().float(f32) * win_width;
            const py = self.rng.random().float(f32) * win_height;
            try self.foods.append(Food{ .pos = rl.Vector2{ .x = px, .y = py } });
        }
    }

    fn create_pheremone_grid(self: *Colony) void {
        self.pheremone_grid = PheremoneGrid{};
    }

    fn update_ants(self: *Colony) void {
        for (self.ants.items) |*ant| {
            ant.update(self.rng.random().float(f32), self, self.foods, &self.pheremone_grid);
            ant.draw();
        }
    }

    fn update_pheremone_grid(self: *Colony) void {
        self.pheremone_grid.update();
        self.pheremone_grid.draw(1);
    }

    fn update_foods(self: *Colony) void {
        for (self.foods.items) |*food| {
            food.update(self.tick, &self.pheremone_grid);
            food.draw();
        }
    }

    fn update(self: *Colony) void {
        self.update_pheremone_grid();
        self.update_ants();
        self.update_foods();
        self.pheremone_grid.add(AntState.exploring, grid_size_x / 2, grid_size_y / 2, 80);
        rl.DrawCircleV(self.home_pos, self.rad, rl.WHITE);
        self.tick += 1;
    }

    fn deinit(self: *Colony) void {
        self.ants.deinit();
        self.foods.deinit();
    }
};

fn create_colony(pos: rl.Vector2, n_ants: usize, n_foods: usize, rng: *std.rand.DefaultPrng, alloc: std.mem.Allocator) !Colony {
    var c = Colony{ .rng = rng.*, .ants = std.ArrayList(Ant).init(alloc), .foods = std.ArrayList(Food).init(alloc), .pheremone_grid = PheremoneGrid{}, .home_pos = pos };
    try c.spawn_ants(n_ants);
    try c.spawn_foods(n_foods);
    c.create_pheremone_grid();

    return c;
}

////////////////////////////////////////////////////
// FOOD
////////////////////////////////////////////////////

const food_scale = 0.5;
const food_default_amount = 50;
const food_count = 4;

const Food = struct {
    pos: rl.Vector2,
    contained: f32 = food_default_amount,

    fn take(self: *Food, amt: f32) f32 {
        if (self.contained < amt) return self.contained;
        self.contained -= amt;
        return amt;
    }

    fn draw(self: *Food) void {
        rl.DrawCircleV(self.pos, self.contained * food_scale, rl.BLUE);
    }

    fn update(self: *Food, tick: usize, grid: *PheremoneGrid) void {
        if (@mod(tick, 5) == 0) {
            const x = @floatToInt(usize, self.pos.x / grid_width);
            const y = @floatToInt(usize, self.pos.y / grid_height);
            grid.add(AntState.found_food, x, y, 50);
        }
    }
};

////////////////////////////////////////////////////
// MAIN
////////////////////////////////////////////////////

pub fn main() !void {
    //NOTE: Switch to arena allocator
    var gpao = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpao.deinit();

    var aao = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = aao.deinit();

    const alloc = aao.allocator();

    var rand = Rng.init(420);

    const centre = rl.Vector2{ .x = 400, .y = 400 };

    var colony = try create_colony(centre, 50, 6, &rand, alloc);
    defer colony.deinit();

    rl.InitWindow(win_width, win_height, win_title);
    defer rl.CloseWindow();

    rl.SetTargetFPS(60);

    var frame: f64 = 0;
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);

        colony.update();

        rl.EndDrawing();
        frame += 1;
    }

    const dt = rl.GetTime();
    std.debug.print("***********************\nAverage Framerate: {}\n*********************\n", .{frame / dt});
}
