const std = @import("std");

const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = @import("zgui");

const assets_dir = @import("build-options").assets_dir;

const window_title = "Free Away Forum Admin";

const State = struct {
    showDemo: bool,
    user_window_size: [2]f32,
    users: []const User,
};

const User = struct {
    id: u64,
    username: []const u8,
    avatar_template: []const u8,
    email: []const u8,
    is_frozen: bool,
    is_blocked: bool,
    has_free_access: bool,
    end_date: i64,
};

var state = State{
    .showDemo = false,
    .user_window_size = [2]f32{ 400.0, 0.0 },
    .users = &.{
        .{
            .id = 1,
            .username = "Dima",
            .avatar_template = "",
            .email = "mail@dimsuz.ru",
            .is_frozen = false,
            .is_blocked = false,
            .has_free_access = true,
            .end_date = 0,
        },
        .{
            .id = 2,
            .username = "Mint",
            .avatar_template = "",
            .email = "mail1@dimsuz.ru",
            .is_frozen = false,
            .is_blocked = false,
            .has_free_access = true,
            .end_date = 0,
        },
    },
};

fn ui_users(window_w: i32) void {
    zgui.setNextWindowPos(.{ .x = 0.0, .y = 0.0, .cond = .first_use_ever });
    state.user_window_size[1] = @floatFromInt(window_w);
    zgui.setNextWindowSize(.{ .w = state.user_window_size[0], .h = state.user_window_size[1] });

    if (zgui.begin("Users", .{ .flags = .{ .no_move = true } })) {
        for (state.users) |u| {
            ui_user_list_item(u);
        }
        if (zgui.button("Press me!", .{})) {
            state.showDemo = true;
        }
    }
    state.user_window_size[0] = zgui.getWindowSize()[0];
    zgui.end();
    if (state.showDemo) {
        zgui.showDemoWindow(&state.showDemo);
    }
}

fn ui_user_list_item(user: User) void {
    if (zgui.beginChildId(zgui.getStrId(user.email), .{ .border = true, .h = 80.0 })) {
        zgui.text("{s}", .{user.username});
        zgui.text("{s}", .{user.email});
    }
    zgui.endChild();
}

pub fn main() !void {
    zglfw.init() catch {
        std.log.err("Failed to initialize GLFW library.", .{});
        return;
    };
    defer zglfw.terminate();

    // Change current working directory to where the executable is located.
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.os.chdir(path) catch {};
    }

    const window = zglfw.Window.create(1200, 800, window_title, null) catch {
        std.log.err("Failed to create window.", .{});
        return;
    };
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const gctx = try zgpu.GraphicsContext.create(gpa, window, .{});
    defer gctx.destroy(gpa);

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.init(gpa);
    defer zgui.deinit();

    _ = zgui.io.addFontFromFile(
        assets_dir ++ "Roboto-Medium.ttf",
        std.math.floor(16.0 * scale_factor),
    );

    zgui.backend.init(
        window,
        gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
    );
    defer zgui.backend.deinit();

    zgui.getStyle().scaleAllSizes(scale_factor);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();

        zgui.backend.newFrame(
            gctx.swapchain_descriptor.width,
            gctx.swapchain_descriptor.height,
        );

        ui_users(window.getSize()[0]);

        const swapchain_texv = gctx.swapchain.getCurrentTextureView();
        defer swapchain_texv.release();

        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            // GUI pass
            {
                const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
                defer zgpu.endReleasePass(pass);
                zgui.backend.draw(pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();

        gctx.submit(&.{commands});
        _ = gctx.present();
    }
}
