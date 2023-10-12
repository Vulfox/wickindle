const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.HttpServer);

const xev = @import("xev");

const Request = @import("Request.zig");
const Response = @import("Response.zig");
const ServerConnection = @import("Connection.zig");
const time = @import("time.zig");

const Self = @This();

allocator: Allocator,
options: HttpServerOptions,

routes: std.StringHashMap(Handler),
serving_sockets: std.ArrayList(ServingSocket),

loop: xev.Loop,
connections: std.ArrayList(*ServerConnection),

gmt_date: [25]u8 = undefined,

pub const HttpServerOptions = struct {
    max_connections: usize = 1024,
};

pub fn init(allocator: Allocator, options: HttpServerOptions) !Self {
    return Self{
        .allocator = allocator,
        .options = options,
        .loop = try xev.Loop.init(.{}),
        .connections = try std.ArrayList(*ServerConnection).initCapacity(
            allocator,
            options.max_connections,
        ),
        .serving_sockets = std.ArrayList(ServingSocket).init(allocator),
        .routes = std.StringHashMap(Handler).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.connections.items) |*conn| {
        self.connections.allocator.destroy(conn);
    }
    self.connections.deinit();

    for (self.serving_sockets.items) |*serv_socket| {
        //var comp: xev.Completion = undefined;
        serv_socket.close(&self.loop);
    }
    self.serving_sockets.deinit();

    self.loop.deinit();

    self.routes.deinit();
}

pub fn listen(self: *Self, ip: []const u8, port: u16) !void {
    var addr = try std.net.Address.parseIp4(ip, port);
    //self.socket = try xev.TCP.init(addr);
    try self.serving_sockets.append(ServingSocket{ .socket = try xev.TCP.init(addr) });
    var new_socket = self.serving_sockets.getLast().socket;

    // Bind and listen
    try new_socket.bind(addr);

    try new_socket.listen(3);

    const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(new_socket.fd)) else new_socket.fd;

    var sock_len = addr.getOsSockLen();
    try std.os.getsockname(fd, &addr.any, &sock_len);
    //std.debug.print("server port: {d}\n", .{addr.getPort()});
    log.info("Port: {d}", .{addr.getPort()});
}

// Trims extra '/'
pub inline fn getHandler(self: *const Self, path: []const u8) ?*Handler {
    const k = if (std.mem.endsWith(u8, path, "/")) path[0 .. path.len - 1] else path;
    return self.routes.getPtr(k);
}

// TODO: comptime prevent overlap on complex paths like params other than basic noclobber
//ref: https://github.com/julienschmidt/httprouter
pub fn registerHandler(self: *Self, path: []const u8, handler: Handler) !void {
    try self.routes.putNoClobber(path, handler);
}

// Wed, 21 Oct 2015 07:28:00 GMT
fn generateGMTDate(self: *Self) !void {
    const now = time.DateTime.now();

    const format = "ddd, DD MMM YYYY HH:mm:ss";
    var stream = std.io.fixedBufferStream(&self.gmt_date);
    const w = stream.writer();
    try now.format(format, .{}, w);
}

// TODO: Make this multithreaded + safe
pub fn run(self: *Self) !void {
    while (true) {
        try self.generateGMTDate();

        for (self.serving_sockets.items) |*serv_socket| {
            if (serv_socket.completion.state() == .dead and self.connections.items.len < self.connections.capacity) {
                var new_server_conn = try self.connections.allocator.create(ServerConnection);
                new_server_conn.loop = &self.loop;
                new_server_conn.completion = xev.Completion{};
                new_server_conn.server = self;
                new_server_conn.state = .none;
                new_server_conn.request = Request{
                    .method = undefined,
                    .target = undefined,
                    .version = undefined,
                };

                self.connections.appendAssumeCapacity(new_server_conn);

                serv_socket.socket.accept(&self.loop, &serv_socket.completion, ServerConnection, new_server_conn, (struct {
                    fn callback(
                        connection: ?*ServerConnection,
                        _: *xev.Loop,
                        _: *xev.Completion,
                        r1: xev.AcceptError!xev.TCP,
                    ) xev.CallbackAction {
                        connection.?.socket = r1 catch |err| {
                            log.warn("Failed to accept: {any}", .{err});
                            return .disarm;
                        };
                        connection.?.state = .accepted;
                        defer connection.?.read();

                        return .disarm;
                    }
                }).callback);
            }
        }

        var i: usize = 0;
        while (i < self.connections.items.len) {
            var conn = self.connections.items[i];
            var remove = false;
            switch (conn.state) {
                .dead => {
                    remove = true;
                },
                else => {},
            }

            if (remove) {
                log.debug("Removing connection: {d}...", .{i});
                var sc = self.connections.orderedRemove(i);
                defer self.connections.allocator.destroy(sc);
            } else {
                i += 1;
            }
        }

        try self.loop.run(.once);
    }
}

const ServingSocket = struct {
    socket: xev.TCP,
    completion: xev.Completion = undefined,

    pub fn close(self: *ServingSocket, loop: *xev.Loop) void {
        self.socket.close(loop, &self.completion, void, null, (struct {
            fn callback(_: ?*void, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.TCP.ShutdownError!void) xev.CallbackAction {
                return .disarm;
            }
        }).callback);

        loop.run(.until_done) catch |err| {
            log.warn("failed to run loop for server socket deinit: {any}", .{err});
        };
    }
};

const Handler = struct {
    methods: []const std.http.Method,
    callback: *const fn (*const Request, *Response) anyerror!void,
};
