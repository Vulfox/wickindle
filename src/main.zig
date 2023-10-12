const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const std_options = struct {
    pub const log_level = .info;
};

const wic = @import("wickindle.zig");

fn hello(req: *const wic.Request) []const u8 {
    _ = req;
    return "Hello, World!";
}

fn hello2(req: *const wic.Request, resp: *wic.Response) !void {
    _ = req;
    //return "Hello, World!";

    const w = resp.writer();
    const content = "Hello, World2!";
    try w.writeAll(content);
}

pub fn main() !void {
    std.debug.print("Test\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("Leak Detected!");
    }

    var server = try wic.HttpServer.init(allocator, .{});
    defer server.deinit();
    try server.listen("0.0.0.0", 3000);
    try server.registerHandler("/get", .{ .methods = &[_]std.http.Method{.GET}, .callback = hello2 });
    try server.run();
}
