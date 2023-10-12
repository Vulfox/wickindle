const std = @import("std");
const log = std.log.scoped(.Connection);

const xev = @import("xev");

const HttpServer = @import("server.zig").HttpServer;
const Request = @import("request.zig");
const Response = @import("response.zig");

// Connection Interface for use by Response/Request
pub const Connection = struct {
    const Self = @This();

    context: *anyopaque,
    readFn: *const fn (context: *anyopaque) void,
    writeFn: *const fn (context: *anyopaque, buf: []const u8) void,

    pub fn read(self: Self) void {
        return self.readFn(self.context);
    }

    pub fn write(self: Self, buf: []const u8) void {
        return self.writeFn(self.context, buf);
    }
};

pub const ServerConnection = struct {
    const Self = @This();
    //allocator: Allocator,
    server: *const HttpServer,
    state: ServerConnectionState = .none,
    loop: *xev.Loop,
    completion: xev.Completion = undefined,
    socket: ?xev.TCP = null,
    request: Request,
    // TODO: configurable io_buf size
    io_buf: [8192]u8 = std.mem.zeroes([8192]u8),

    pub fn deinit(_: *Self) void {
        //if (self.request != null) self.request.?.headers.deinit();
    }

    pub fn read(self: *Self) void {
        self.socket.?.read(self.loop, &self.completion, .{ .slice = &self.io_buf }, Self, self, read_callback5);
    }
    pub fn write(self: *Self, buf: []const u8) void {
        self.socket.?.write(self.loop, &self.completion, .{ .slice = buf }, Self, self, write_callback5);
    }
    inline fn close(self: *Self) xev.CallbackAction {
        self.state = .close;
        self.socket.?.close(self.loop, &self.completion, Self, self, close_callback5);
        return .disarm;
    }

    fn read_callback5(sc: ?*Self, loop: *xev.Loop, comp: *xev.Completion, _: xev.TCP, rb: xev.ReadBuffer, rl: xev.ReadError!usize) xev.CallbackAction {
        const read_len = rl catch |err| {
            log.warn("Read Error: {any}", .{err});
            return sc.?.close();
        };
        // TODO: Handle partial header/reqs
        sc.?.request.parse(rb.slice[0..read_len]) catch |err| {
            log.err("Invalid request: {any}", .{err});
            return sc.?.close();
        };
        sc.?.state = .write;

        const handler = sc.?.server.getHandler(sc.?.request.target);
        if (handler == null) {
            // TODO: Get static 404 content that is defined else where
            sc.?.request.keep_alive = false;
            const slice404 = std.fmt.bufPrint(&sc.?.io_buf, "HTTP/1.1 404\r\nConnection: close\r\n\r\n", .{}) catch |err| {
                log.warn("Failed to write to io_buf: {any}", .{err});
                return sc.?.close();
            };

            defer sc.?.socket.?.write(loop, comp, .{ .slice = slice404 }, Self, sc, write_callback5);
            return .disarm;
        }

        var resp = Response{
            .connection = sc.?.getConnection(),
        };
        // Default headers supplied
        resp.headers.connection = if (sc.?.request.keep_alive) "keep-alive" else "close";
        resp.headers.date = &sc.?.server.gmt_date;

        handler.?.callback(&sc.?.request, &resp) catch |err| {
            log.err("Failed to execute handler callback: {any}", .{err});
            return sc.?.close();
        };

        // This means user didn't call finish() for their response sub X len buffer content, so we'll do it for them
        if (resp.state != .finished) resp.finish() catch |err| {
            log.err("Failed to write finish to Response: {any}", .{err});
            return sc.?.close();
        };

        return .disarm;
    }

    fn write_callback5(sc: ?*Self, loop: *xev.Loop, comp: *xev.Completion, _: xev.TCP, _: xev.WriteBuffer, written: xev.TCP.WriteError!usize) xev.CallbackAction {
        _ = written catch |err| {
            log.warn("Write Error: {any}", .{err});
            return sc.?.close();
        };

        if (!sc.?.request.keep_alive) return sc.?.close();

        sc.?.state = .read;
        sc.?.request.reset(); // ensure request is clean for next read
        defer sc.?.socket.?.read(loop, comp, .{ .slice = &sc.?.io_buf }, Self, sc, read_callback5);

        return .disarm;
    }

    fn close_callback5(sc: ?*Self, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.TCP.ShutdownError!void) xev.CallbackAction {
        sc.?.state = .dead;

        return .disarm;
    }

    pub inline fn getConnection(self: *Self) Connection {
        return .{
            .context = @ptrCast(self),
            .readFn = typeErasedReadFn,
            .writeFn = typeErasedWriteFn,
        };
    }
    fn typeErasedReadFn(context: *anyopaque) void {
        const ptr: *Self = @alignCast(@ptrCast(context));
        return read(ptr);
    }

    fn typeErasedWriteFn(context: *anyopaque, buf: []const u8) void {
        const ptr: *Self = @alignCast(@ptrCast(context));
        return write(ptr, buf);
    }
};

const ServerConnectionState = enum(u8) {
    none = 0,
    accepted,
    read,
    write,
    close,
    dead,
    awaiting,
};
