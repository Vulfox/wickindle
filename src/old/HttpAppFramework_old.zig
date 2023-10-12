const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const xev = @import("xev");

//const HttpSimpleControllersRouter = @import("HttpSimpleControllersRouter.zig");

const Self = @This();

allocator: Allocator,
socket: ?xev.TCP = null,

loop: *xev.Loop,
worker_loop: *xev.Loop,
connections: std.ArrayList(ServerConnection),

connection_responder: xev.Async,
connection_closer: xev.Async,

respond: *const fn (
    userdata: ?*anyopaque,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Result,
) xev.CallbackAction, //xev.Callback,

//http_simple_ctrls_router: HttpSimpleControllersRouter,

pub fn init(allocator: Allocator, loop: *xev.Loop, worker_loop: *xev.Loop) !Self {
    //http_simple_ctrls_router = HttpSimpleControllersRouter.init();
    return Self{
        .allocator = allocator,
        .loop = loop,
        .worker_loop = worker_loop,
        .connections = std.ArrayList(ServerConnection).init(allocator),
        .connection_responder = try xev.Async.init(),
        .connection_closer = try xev.Async.init(),
        .respond = respond,
    };
}

pub fn deinit(self: *Self) void {
    self.connections.deinit();
    self.connection_responder.deinit();
    self.connection_closer.deinit();
}

pub fn run() void {}

pub const ListenError = std.os.SocketError || std.os.BindError || std.os.ListenError || std.os.SetSockOptError || std.os.GetSockNameError;

pub fn listen(self: *Self, ip: []const u8, port: u16) !void {
    //self.app_ptr = c.HttpAppFramework_addListener(self.app_ptr, @as([*c]const u8, @ptrCast(ip)), port).?;
    // try server.socket.listen(address);?
    var addr = try std.net.Address.parseIp4(ip, port);
    self.socket = try xev.TCP.init(addr);

    // Bind and listen
    try self.socket.?.bind(addr);

    try self.socket.?.listen(3);

    const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(self.socket.?.fd)) else self.socket.?.fd;
    // var something: [256]u8 = undefined;
    // _ = try std.os.windows.WSAIoctl(fd, 1, null, &something, null, null);

    std.debug.print("server port: {d}\n", .{addr.getPort()});
    var sock_len = addr.getOsSockLen();
    //const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(self.socket.?.fd)) else self.socket.?.fd;
    try std.os.getsockname(fd, &addr.any, &sock_len);
    std.debug.print("server port: {d}\n", .{addr.getPort()});
}

pub fn accept(_: *Self) !void {

    // return std.http.Server.Response{
    //     .allocator = self.allocator,
    //     .address = in.address,
    //     .connection = .{
    //         .stream = in.stream,
    //         .protocol = .plain,
    //     },
    //     .headers = .{ .allocator = self.allocator },
    //     .request = .{
    //         .version = undefined,
    //         .method = undefined,
    //         .target = undefined,
    //         .headers = .{ .allocator = self.allocator, .owned = false },
    //         // .parser = switch (options.header_strategy) {
    //         //     .dynamic => |max| proto.HeadersParser.initDynamic(max),
    //         //     .static => |buf| proto.HeadersParser.initStatic(buf),
    //         // },
    //         .parser = std.http.proto.HeadersParser.initDynamic(8192),
    //     },
    // };
}

// Handle an individual request.
fn handleRequest(response: *std.http.Server.Response, allocator: std.mem.Allocator) !void {
    // Log the request details.
    //std.debug.print("{s} {s} {s}\n", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    // Read the request body.
    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    // Set "connection" header to "keep-alive" if present in request headers.
    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "keep-alive");
    }

    // Check if the request target starts with "/get".
    if (std.mem.startsWith(u8, response.request.target, "/get")) {
        // Check if the request target contains "?chunked".
        if (std.mem.indexOf(u8, response.request.target, "?chunked") != null) {
            response.transfer_encoding = .chunked;
        } else {
            response.transfer_encoding = .{ .content_length = 10 };
        }

        // Set "content-type" header to "text/plain".
        try response.headers.append("content-type", "text/plain");

        // Write the response body.
        try response.do();
        if (response.request.method != .HEAD) {
            try response.writeAll("Zig ");
            try response.writeAll("Bits!\n");
            try response.finish();
        }
    } else {
        // Set the response status to 404 (not found).
        response.status = .not_found;
        try response.do();
    }
}

test "asdfasdf" {
    // var tp = xev.ThreadPool.init(.{ .max_threads = 4 });
    // var loop = try xev.Loop.init(.{ .thread_pool = &tp });
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    var worker_loop = try xev.Loop.init(.{});
    defer worker_loop.deinit();

    var app = try Self.init(testing.allocator, &loop, &worker_loop);
    defer app.deinit();
    try app.listen("127.0.0.1", 3000);

    //try runBasicLoop(&app);
    try runAsyncLoop(&app);
}
// pub const log_level: std.log.Level = .info;

const ServerConnectionState = enum(u8) {
    none = 0,
    accepted,
    responded,
    closed,
};

const ServerConnection = struct {
    state: ServerConnectionState = .none,
    completion: xev.Completion = undefined,
    socket: ?xev.TCP = null,

    // respond: *const fn (
    //     userdata: ?*anyopaque,
    //     loop: *xev.Loop,
    //     completion: *xev.Completion,
    //     result: xev.Result,
    // ) xev.CallbackAction = sc_respond,

    pub fn sc_respond(server_conn: *ServerConnection, _: *xev.Loop, _: *xev.Completion) xev.CallbackAction {
        //var app: *Self = @as(*Self, @ptrCast(ud.?));
        //const server_conn = @as(*ServerConnection, @ptrCast(@alignCast(ud.?)));

        // std.debug.print("respond pointer: {*}\n", .{app});
        // std.debug.print("Responding List Len: {d}\n", .{app.connections.items.len});
        // for (app.connections.items) |connection| {
        //     if (connection.state == .accepted and connection.socket != null) {
        // std.debug.print("Responding: {any}\n", .{server_conn});
        var addr: std.net.Address = undefined;
        // var sock_len: std.os.socklen_t = @sizeOf(std.net.Address);
        const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(server_conn.socket.?.fd)) else server_conn.socket.?.fd;
        // try std.os.getsockname(fd, &addr.any, &sock_len);
        var response = std.http.Server.Response{
            .allocator = testing.allocator, //ud.?.allocator,
            .address = addr,
            .connection = .{
                .stream = std.net.Stream{ .handle = fd }, //fd, //in.stream,
                .protocol = .plain,
            },
            .headers = .{ .allocator = testing.allocator },
            .request = .{
                .version = undefined,
                .method = undefined,
                .target = undefined,
                .headers = .{ .allocator = testing.allocator, .owned = false },
                // .parser = switch (options.header_strategy) {
                //     .dynamic => |max| proto.HeadersParser.initDynamic(max),
                //     .static => |buf| proto.HeadersParser.initStatic(buf),
                // },
                .parser = std.http.protocol.HeadersParser.initDynamic(8192),
            },
        };
        defer response.deinit();

        // TODO: handler bad http header
        while (response.reset() != .closing) {
            // Handle errors during request processing.
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => break, //continue :outer,
                error.EndOfStream => continue,
                else => unreachable,
            };

            // Process the request.
            handleRequest(&response, testing.allocator) catch |err| {
                std.debug.print("failed to handle request: {any}\n", .{err});
            };
            //ud.?.connection_closer.notify() catch unreachable;

        }
        //     }
        // }
        // ud.?.connections.items[i].state = .responded;
        // defer server_conn.sc_close(loop);

        return .disarm;
    }

    pub fn sc_close(server_conn: *ServerConnection, loop: *xev.Loop) void {
        //std.debug.print("Closing: {any}\n", .{server_conn.completion.state()});
        // server_conn.completion.state = .active;
        // server_conn.socket.?.close(loop, &server_conn.completion, ServerConnection, server_conn, (struct {
        //     fn callback(
        //         ud1: ?*ServerConnection,
        //         _: *xev.Loop,
        //         _: *xev.Completion,
        //         _: xev.TCP,
        //         r1: xev.CloseError!void,
        //     ) xev.CallbackAction {
        //         _ = r1 catch unreachable;
        //         ud1.?.*.state = .closed;
        //         ud1.?.*.socket = null;
        //         return .disarm;
        //     }
        // }).callback);

        server_conn.completion = .{
            .op = .{
                .close = .{
                    .fd = server_conn.socket.?.fd,
                },
            },

            .userdata = server_conn,
            .callback = (struct {
                fn callback(ud: ?*anyopaque, l: *xev.Loop, c: *xev.Completion, r: xev.Result) xev.CallbackAction {
                    _ = l;
                    _ = c;
                    _ = r.close catch unreachable;
                    const ptr = @as(*std.os.socket_t, @ptrCast(@alignCast(ud.?)));
                    ptr.* = 0;
                    return .disarm;
                }
            }).callback,
        };

        loop.add(server_conn.completion);
    }
};

fn respond(ud: ?*anyopaque, _: *xev.Loop, _: *xev.Completion, _: xev.Result) xev.CallbackAction {
    //var app: *Self = @as(*Self, @ptrCast(ud.?));
    const app = @as(*Self, @ptrCast(@alignCast(ud.?)));

    std.debug.print("respond pointer: {*}\n", .{app});
    std.debug.print("Responding List Len: {d}\n", .{app.connections.items.len});
    for (app.connections.items) |connection| {
        if (connection.state == .accepted and connection.socket != null) {
            std.debug.print("Responding: {any}\n", .{connection});
            var addr: std.net.Address = undefined;
            // var sock_len: std.os.socklen_t = @sizeOf(std.net.Address);
            const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(connection.socket.?.fd)) else connection.socket.?.fd;
            // try std.os.getsockname(fd, &addr.any, &sock_len);
            var response = std.http.Server.Response{
                .allocator = app.allocator, //ud.?.allocator,
                .address = addr,
                .connection = .{
                    .stream = std.net.Stream{ .handle = fd }, //fd, //in.stream,
                    .protocol = .plain,
                },
                .headers = .{ .allocator = app.allocator },
                .request = .{
                    .version = undefined,
                    .method = undefined,
                    .target = undefined,
                    .headers = .{ .allocator = app.allocator, .owned = false },
                    // .parser = switch (options.header_strategy) {
                    //     .dynamic => |max| proto.HeadersParser.initDynamic(max),
                    //     .static => |buf| proto.HeadersParser.initStatic(buf),
                    // },
                    .parser = std.http.protocol.HeadersParser.initDynamic(8192),
                },
            };
            defer response.deinit();

            // TODO: handler bad http header
            while (response.reset() != .closing) {
                // Handle errors during request processing.
                response.wait() catch |err| switch (err) {
                    error.HttpHeadersInvalid => break, //continue :outer,
                    error.EndOfStream => continue,
                    else => unreachable,
                };

                // Process the request.
                handleRequest(&response, app.allocator) catch |err| {
                    std.debug.print("failed to handle request: {any}\n", .{err});
                };
                //ud.?.connection_closer.notify() catch unreachable;

            }
        }
    }
    // ud.?.connections.items[i].state = .responded;

    return .disarm;
}

fn runAsyncLoop(app: *Self) !void {
    var connection_accepter = try xev.Async.init();
    defer connection_accepter.deinit();

    //var :[4]ServerConnection = undefined;
    // var

    var closer_wait: xev.Completion = undefined;
    // var connection_closer = try xev.Async.init();
    // defer connection_closer.deinit();
    app.connection_closer.wait(app.loop, &closer_wait, Self, app, (struct {
        fn callback(
            ud: ?*Self,
            loop: *xev.Loop,
            _: *xev.Completion,
            r: xev.Async.WaitError!void,
        ) xev.CallbackAction {
            _ = r catch unreachable;
            // std.debug.print("Closing\n", .{});
            for (ud.?.connections.items, 0..) |connection, i| {
                if (connection.state == .responded and connection.socket != null) {
                    std.debug.print("Closing: {any}\n", .{connection.socket});
                    // var sock_len: std.os.socklen_t = @sizeOf(std.net.Address);
                    //const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(connection.socket.?.fd)) else connection.socket.?.fd;
                    var comp: xev.Completion = undefined;
                    ud.?.connections.items[i].socket.?.close(loop, &comp, ServerConnection, &ud.?.connections.items[i], (struct {
                        fn callback(
                            ud1: ?*ServerConnection,
                            _: *xev.Loop,
                            _: *xev.Completion,
                            _: xev.TCP,
                            r1: xev.CloseError!void,
                        ) xev.CallbackAction {
                            _ = r1 catch unreachable;
                            ud1.?.*.state = .closed;
                            // ud1.?.*.socket = null;
                            return .disarm;
                        }
                    }).callback);
                }
            }

            return .disarm;
        }
    }).callback);

    var responder_wait: xev.Completion = undefined;
    app.connection_responder.wait(app.loop, &responder_wait, Self, app, (struct {
        fn callback(
            ud: ?*Self,
            _: *xev.Loop,
            _: *xev.Completion,
            r: xev.Async.WaitError!void,
        ) xev.CallbackAction {
            _ = r catch |err| {
                std.debug.print("Waiting Error for Responder: {any}\n", .{err});
            };
            std.debug.print("Responding List {any}\n", .{ud.?.connections});
            for (ud.?.connections.items, 0..) |connection, i| {
                if (connection.state == .accepted and connection.socket != null) {
                    std.debug.print("Responding: {any}\n", .{connection});
                    var addr: std.net.Address = undefined;
                    // var sock_len: std.os.socklen_t = @sizeOf(std.net.Address);
                    const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(connection.socket.?.fd)) else connection.socket.?.fd;
                    // try std.os.getsockname(fd, &addr.any, &sock_len);
                    var response = std.http.Server.Response{
                        .allocator = ud.?.allocator,
                        .address = addr,
                        .connection = .{
                            .stream = std.net.Stream{ .handle = fd }, //fd, //in.stream,
                            .protocol = .plain,
                        },
                        .headers = .{ .allocator = ud.?.allocator },
                        .request = .{
                            .version = undefined,
                            .method = undefined,
                            .target = undefined,
                            .headers = .{ .allocator = ud.?.allocator, .owned = false },
                            // .parser = switch (options.header_strategy) {
                            //     .dynamic => |max| proto.HeadersParser.initDynamic(max),
                            //     .static => |buf| proto.HeadersParser.initStatic(buf),
                            // },
                            .parser = std.http.protocol.HeadersParser.initDynamic(8192),
                        },
                    };
                    defer response.deinit();

                    // TODO: handler bad http header
                    while (response.reset() != .closing) {
                        // Handle errors during request processing.
                        response.wait() catch |err| switch (err) {
                            error.HttpHeadersInvalid => continue, //continue :outer,
                            error.EndOfStream => continue,
                            else => {
                                std.debug.print("failed to handle req: {any}\n", .{err});
                            },
                        };

                        // Process the request.
                        handleRequest(&response, ud.?.allocator) catch |err| {
                            std.debug.print("failed to handle req: {any}\n", .{err});
                        };
                    }
                    ud.?.connections.items[i].state = .responded;
                    ud.?.connection_closer.notify() catch |err| {
                        std.debug.print("failed to notify conn_closer: {any}\n", .{err});
                    };

                    // std.debug.print("Closing: {any}\n", .{connection.socket});
                    // // var sock_len: std.os.socklen_t = @sizeOf(std.net.Address);
                    // //const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(connection.socket.?.fd)) else connection.socket.?.fd;
                    // var closer_comp: xev.Completion = undefined;
                    // ud.?.connections.items[i].socket.?.shutdown(loop, &closer_comp, ServerConnection, &ud.?.connections.items[i], (struct {
                    //     fn callback(
                    //         ud1: ?*ServerConnection,
                    //         _: *xev.Loop,
                    //         _: *xev.Completion,
                    //         rt: xev.TCP,
                    //         r1: xev.TCP.ShutdownError!void,
                    //     ) xev.CallbackAction {
                    //         _ = r1 catch |err| {
                    //             std.debug.print("Failed to Close: {any}: {any}\n", .{ rt, err });
                    //         };

                    //         std.debug.print("Closed: {any}\n", .{rt});
                    //         ud1.?.*.state = .closed;
                    //         // ud1.?.*.socket = null;
                    //         return .disarm;
                    //     }
                    // }).callback);
                }
            }

            return .disarm;
        }
    }).callback);

    // connection_accepter.wait(app.loop, &accepter_wait, Self, app, (struct {
    //     fn callback(
    //         ud: ?*Self,
    //         loop: *xev.Loop,
    //         _: *xev.Completion,
    //         r: xev.Async.WaitError!void,
    //     ) xev.CallbackAction {
    //         _ = r catch unreachable;

    //         if (ud.?.connections.items.len < 4) { // TODO: Dynamic connections size
    //             std.debug.print("Added Connection\n", .{});
    //             ud.?.connections.append(ServerConnection{}) catch unreachable;
    //         }
    //         for (ud.?.connections.items, 0..) |connection, i| {
    //             if (connection.state == .none) {
    //                 ud.?.socket.?.accept(loop, &ud.?.connections.items[i].completion, ServerConnection, &ud.?.connections.items[i], (struct {
    //                     fn callback(
    //                         ud1: ?*ServerConnection,
    //                         _: *xev.Loop,
    //                         _: *xev.Completion,
    //                         r1: xev.AcceptError!xev.TCP,
    //                     ) xev.CallbackAction {
    //                         ud1.?.*.socket = r1 catch unreachable;
    //                         std.debug.print("Accept: {any}\n", .{ud1});
    //                         ud1.?.state = .accepted;

    //                         return .disarm;
    //                     }
    //                 }).callback);
    //             }
    //         }

    //         return .disarm;
    //     }
    // }).callback);
    // try connection_accepter.notify();

    std.debug.print("app pointer: {*}\n", .{app});

    // while (true) {
    // if (app.connections.items.len < 4) { // TODO: Dynamic connections size
    // std.debug.print("Added Connection\n", .{});
    //ud.?.connections.append(ServerConnection{}) catch unreachable;
    //std.debug.print("loop\n", .{});

    //var accepter_wait: xev.Completion = undefined;

    // const server_conn = try app.connections.allocator.create(ServerConnection);
    // errdefer app.connections.allocator.destroy(server_conn);
    try app.connections.append(ServerConnection{});
    var server_conn = app.connections.items[app.connections.items.len - 1];
    app.socket.?.accept(app.loop, &server_conn.completion, ServerConnection, &server_conn, (struct {
        fn callback(
            connection: ?*ServerConnection,
            loop: *xev.Loop,
            comp: *xev.Completion,
            r1: xev.AcceptError!xev.TCP,
        ) xev.CallbackAction {
            // ud1.?.*.socket = r1 catch unreachable;
            //std.debug.print("Accept: {any}\n", .{r1});
            //ud.?.*.connections.append(ServerConnection{ .state = .accepted, .socket = r1 catch unreachable }) catch unreachable;
            //std.debug.print("Accept List Len: {d}\n", .{ud.?.*.connections.items.len});
            //ud1.?.state = .accepted;
            connection.?.state = .accepted;
            connection.?.socket = r1 catch unreachable;

            // defer _ = connection.?.sc_respond(loop, comp);
            // TODO Async read and send instead of zig std stuff

            // maybe this works??

            var recv_buf: [256]u8 = undefined;
            //var recv_len: usize = 0;
            defer connection.?.socket.?.read(loop, comp, .{ .slice = &recv_buf }, ServerConnection, connection.?, (struct {
                fn callback(
                    _: ?*ServerConnection,
                    _: *xev.Loop,
                    _: *xev.Completion,
                    _: xev.TCP,
                    rb: xev.ReadBuffer,
                    _: xev.ReadError!usize,
                ) xev.CallbackAction {
                    std.debug.print("read socket: {s}\n", .{rb.slice});
                    return .disarm;
                }
            }).callback);

            // comp.callback = connection.?.respond;
            // loop.add(comp);
            // loop.submit() catch unreachable;

            // ud.?.*.connection_responder.notify() catch unreachable;

            return .rearm;
        }
    }).callback);
    // try app.loop.run(.until_done);
    // try app.connection_responder.notify();
    // accepter_wait.callback = app.respond;
    // }

    // try app.loop.run(.until_done);

    // var connection_responder = try xev.Async.init();
    // defer connection_responder.deinit();

    // try connection_responder.notify();

    // app.socket.?.close(app.loop, &closer_wait, Self, app, (struct {
    //     fn callback(
    //         ud: ?*Self,
    //         _: *xev.Loop,
    //         _: *xev.Completion,
    //         closing_socket: xev.TCP,
    //         r1: xev.CloseError!void,
    //     ) xev.CallbackAction {
    //         _ = r1 catch |err| {
    //             std.debug.print("Close: Unreachable: {any}\n", .{err});
    //         };
    //         std.debug.print("Close: {any}\n", .{closing_socket});
    //         for (ud.?.*.connections.items, 0..) |connection, i| {
    //             if (connection.state == .responded and connection.socket.?.fd == closing_socket.fd) {
    //                 ud.?.*.connections.items[i].state = .closed;
    //                 break;
    //             }
    //         }
    //         // ud.?.*.state = .closed;
    //         return .rearm;
    //     }
    // }).callback);

    // try connection_closer.notify();

    try app.loop.run(.until_done);
    // try app.worker_loop.run(.once);
    // }
}

fn runBasicLoop(app: *Self) !void {
    outer: while (true) {
        var c_accept: xev.Completion = undefined;
        var server_conn: ?xev.TCP = null;
        app.socket.?.accept(app.loop, &c_accept, ?xev.TCP, &server_conn, (struct {
            fn callback(
                ud: ?*?xev.TCP,
                _: *xev.Loop,
                _: *xev.Completion,
                r: xev.AcceptError!xev.TCP,
            ) xev.CallbackAction {
                ud.?.* = r catch unreachable;
                std.debug.print("TCP: {any}\n", .{ud});

                std.debug.print("asdfasdf\n", .{});

                return .disarm;
            }
        }).callback);

        try app.loop.run(.until_done);

        // TODO: need to verify content is not null, etc

        var addr: std.net.Address = undefined;
        // var sock_len: std.os.socklen_t = @sizeOf(std.net.Address);
        const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(server_conn.?.fd)) else server_conn.?.fd;
        // try std.os.getsockname(fd, &addr.any, &sock_len);
        var response = std.http.Server.Response{
            .allocator = testing.allocator,
            .address = addr,
            .connection = .{
                .stream = std.net.Stream{ .handle = fd }, //fd, //in.stream,
                .protocol = .plain,
            },
            .headers = .{ .allocator = testing.allocator },
            .request = .{
                .version = undefined,
                .method = undefined,
                .target = undefined,
                .headers = .{ .allocator = testing.allocator, .owned = false },
                // .parser = switch (options.header_strategy) {
                //     .dynamic => |max| proto.HeadersParser.initDynamic(max),
                //     .static => |buf| proto.HeadersParser.initStatic(buf),
                // },
                .parser = std.http.protocol.HeadersParser.initDynamic(8192),
            },
        };

        while (response.reset() != .closing) {
            // Handle errors during request processing.
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.EndOfStream => continue,
                else => return err,
            };

            // Process the request.
            try handleRequest(&response, testing.allocator);
        }

        // var conn_closed = false;
        server_conn.?.close(app.loop, &c_accept, ?xev.TCP, &server_conn, (struct {
            fn callback(
                ud: ?*?xev.TCP,
                _: *xev.Loop,
                _: *xev.Completion,
                _: xev.TCP,
                r: xev.CloseError!void,
            ) xev.CallbackAction {
                _ = r catch unreachable;
                ud.?.* = null;
                return .disarm;
            }
        }).callback);

        std.debug.print("asdfasdfasdf\n", .{});
        try app.loop.run(.until_done);
    }
}

fn serveStaticPage(app: *Self) !void {
    var c_accept: xev.Completion = undefined;
    var server_conn: ?xev.TCP = null;
    app.socket.?.accept(app.loop, &c_accept, ?xev.TCP, &server_conn, (struct {
        fn callback(
            ud: ?*?xev.TCP,
            _: *xev.Loop,
            _: *xev.Completion,
            r: xev.AcceptError!xev.TCP,
        ) xev.CallbackAction {
            ud.?.* = r catch unreachable;
            std.debug.print("TCP: {any}\n", .{ud});

            std.debug.print("asdfasdf\n", .{});

            return .disarm;
        }
    }).callback);

    try app.loop.run(.until_done);

    // TODO: need to verify content is not null, etc

    var addr: std.net.Address = undefined;
    // var sock_len: std.os.socklen_t = @sizeOf(std.net.Address);
    const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(server_conn.?.fd)) else server_conn.?.fd;
    // try std.os.getsockname(fd, &addr.any, &sock_len);
    var response = std.http.Server.Response{
        .allocator = testing.allocator,
        .address = addr,
        .connection = .{
            .stream = std.net.Stream{ .handle = fd }, //fd, //in.stream,
            .protocol = .plain,
        },
        .headers = .{ .allocator = testing.allocator },
        .request = .{
            .version = undefined,
            .method = undefined,
            .target = undefined,
            .headers = .{ .allocator = testing.allocator, .owned = false },
            // .parser = switch (options.header_strategy) {
            //     .dynamic => |max| proto.HeadersParser.initDynamic(max),
            //     .static => |buf| proto.HeadersParser.initStatic(buf),
            // },
            .parser = std.http.protocol.HeadersParser.initDynamic(8192),
        },
    };

    // TODO: handler bad http header
    while (response.reset() != .closing) {
        // Handle errors during request processing.
        response.wait() catch |err| switch (err) {
            error.HttpHeadersInvalid => break, //continue :outer,
            error.EndOfStream => continue,
            else => return err,
        };

        // Process the request.
        try handleRequest(&response, testing.allocator);
    }

    // var conn_closed = false;
    server_conn.?.close(app.loop, &c_accept, ?xev.TCP, &server_conn, (struct {
        fn callback(
            ud: ?*?xev.TCP,
            _: *xev.Loop,
            _: *xev.Completion,
            _: xev.TCP,
            r: xev.CloseError!void,
        ) xev.CallbackAction {
            _ = r catch unreachable;
            ud.?.* = null;
            return .disarm;
        }
    }).callback);

    std.debug.print("asdfasdfasdf\n", .{});
    try app.loop.run(.until_done);
}
// fn timerCallback(
//     userdata: ?*void,
//     loop: *xev.Loop,
//     c: *xev.Completion,
//     result: xev.Timer.RunError!void,
// ) xev.CallbackAction {
//     _ = userdata;
//     _ = loop;
//     _ = c;
//     _ = result catch unreachable;
//     return .disarm;
// }
