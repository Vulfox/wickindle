const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const xev = @import("xev");

const time = @import("time.zig");

const App = struct {
    const Self = @This();

    allocator: Allocator,
    socket: ?xev.TCP = null,

    // loop: *xev.Loop,
    // worker_loop: *xev.Loop,
    accept_comp: xev.Completion,
    connections: std.ArrayList(*ServerConnection),

    connection_responder: xev.Async,
    connection_closer: xev.Async,

    gmt_date: [25]u8 = undefined,

    // respond: *const fn (
    //     userdata: ?*anyopaque,
    //     loop: *xev.Loop,
    //     completion: *xev.Completion,
    //     result: xev.Result,
    // ) xev.CallbackAction, //xev.Callback,

    //http_simple_ctrls_router: HttpSimpleControllersRouter,

    pub fn init(allocator: Allocator) !Self {
        //http_simple_ctrls_router = HttpSimpleControllersRouter.init();
        return Self{
            .allocator = allocator,
            // .loop = loop,
            // .worker_loop = worker_loop,
            .connections = std.ArrayList(*ServerConnection).init(allocator),
            .connection_responder = try xev.Async.init(),
            .connection_closer = try xev.Async.init(),
            .accept_comp = xev.Completion{},
            // .respond = respond,
        };
    }

    pub fn deinit(self: *Self) void {
        self.connections.deinit();
        self.connection_responder.deinit();
        self.connection_closer.deinit();
    }

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

        // std.debug.print("server port: {d}\n", .{addr.getPort()});
        var sock_len = addr.getOsSockLen();
        //const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(self.socket.?.fd)) else self.socket.?.fd;
        try std.os.getsockname(fd, &addr.any, &sock_len);
        std.debug.print("server port: {d}\n", .{addr.getPort()});
    }

    pub fn generateGMTDate(self: *Self) !void {
        const now = time.DateTime.now();

        //Wed, 21 Oct 2015 07:28:00 GMT
        const format = "ddd, DD MMM YYYY HH:mm:ss";
        var stream = std.io.fixedBufferStream(&self.gmt_date);
        const w = stream.writer();
        try now.format(format, .{}, w);
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

const ServerConnection = struct {
    const Self = @This();
    //allocator: Allocator,
    app: *const App,
    state: ServerConnectionState = .none,
    completion: xev.Completion = undefined,
    socket: ?xev.TCP = null,
    request: Request,
    respond: *const fn (?*anyopaque, *xev.Loop, *xev.Completion, xev.Result) xev.CallbackAction = sc_respond,
    recv_buf: [8192]u8 = undefined,

    read_cb: *const fn (?*Self, *xev.Loop, *xev.Completion, xev.TCP, xev.ReadBuffer, xev.ReadError!usize) xev.CallbackAction = read_callback5,
    write_cb: *const fn (?*Self, *xev.Loop, *xev.Completion, xev.TCP, xev.WriteBuffer, written: xev.TCP.WriteError!usize) xev.CallbackAction = write_callback5,
    close_cb: *const fn (?*Self, *xev.Loop, *xev.Completion, xev.TCP, xev.TCP.ShutdownError!void) xev.CallbackAction = close_callback5,

    pub fn deinit(_: *Self) void {
        //if (self.request != null) self.request.?.headers.deinit();
    }

    // respond: *const fn (
    //     userdata: ?*anyopaque,
    //     loop: *xev.Loop,
    //     completion: *xev.Completion,
    //     result: xev.Result,
    // ) xev.CallbackAction = sc_respond,

    pub fn read(self: *Self, loop: *xev.Loop) void {
        self.socket.?.read(loop, &self.completion, .{ .slice = &self.recv_buf }, Self, self, read_callback5);
    }

    fn read_callback5(sc: ?*ServerConnection, loop: *xev.Loop, comp: *xev.Completion, _: xev.TCP, _: xev.ReadBuffer, rl: xev.ReadError!usize) xev.CallbackAction {
        //var recv_buf: [8192]u8 = undefined;
        _ = rl catch |err| {
            std.debug.print("Read Error: {any}\n", .{err});
            sc.?.state = .close;
            defer sc.?.socket.?.close(loop, comp, ServerConnection, sc, close_callback5);
            return .disarm;
        };
        // Read Request when I start caring
        // if (rb.slice.len == 0) {
        //     //sc.?.state = .write;
        //     std.debug.print("rearm read\n", .{});
        //     return .rearm;
        // }
        sc.?.state = .write;

        //const write_buf = "HTTP/1.1 200 \r\nConnection: keep-alive\r\nContent-Type: text/plain\r\nDate: " ++ sc.?.app.gmt_date ++ " GMT\r\nLast-Modifed: " ++ sc.?.app.gmt_date ++ " GMT\r\nContent-Length: 17\r\n\r\nHello from ZAP!!!\n";
        const write_buf = "HTTP/1.1 200 \r\nConnection: keep-alive\r\nContent-Type: text/plain\r\nContent-Length: 17\r\n\r\nHello from ZAP!!!\n";

        defer sc.?.socket.?.write(loop, comp, .{ .slice = write_buf }, ServerConnection, sc, write_callback5);
        return .disarm;
    }

    fn write_callback5(sc: ?*ServerConnection, loop: *xev.Loop, comp: *xev.Completion, _: xev.TCP, _: xev.WriteBuffer, written: xev.TCP.WriteError!usize) xev.CallbackAction {
        _ = written catch |err| {
            std.debug.print("Write Error: {any}\n", .{err});
            sc.?.state = .close;
            defer sc.?.socket.?.close(loop, comp, ServerConnection, sc, close_callback5);
            return .disarm;
        };

        // TODO: KeepAlive after checking cascade perf
        // std.debug.print("keep-alive to read\n", .{});
        // sc.?.state = .read;

        // sc.?.state = .close;
        // defer sc.?.socket.?.close(loop, comp, ServerConnection, sc, close_callback5);
        sc.?.state = .read;
        //sc.?.read(loop);
        defer sc.?.socket.?.read(loop, comp, .{ .slice = &sc.?.recv_buf }, ServerConnection, sc, read_callback5);

        return .disarm;
    }

    fn close_callback5(sc: ?*ServerConnection, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.TCP.ShutdownError!void) xev.CallbackAction {
        sc.?.state = .dead;

        return .disarm;
    }

    pub fn sc_respond(self: ?*anyopaque, loop: *xev.Loop, comp: *xev.Completion, _: xev.Result) xev.CallbackAction {
        const server_conn = @as(*ServerConnection, @ptrCast(@alignCast(self.?)));

        // 8KB header read
        var recv_buf: [8192]u8 = undefined;
        server_conn.socket.?.read(loop, comp, .{ .slice = &recv_buf }, ServerConnection, server_conn, read_callback);
        return .disarm;
    }

    // pub fn sc_close(server_conn: *ServerConnection, loop: *xev.Loop) void {
    //     //std.debug.print("Closing: {any}\n", .{server_conn.completion.state()});
    //     // server_conn.completion.state = .active;
    //     // server_conn.socket.?.close(loop, &server_conn.completion, ServerConnection, server_conn, (struct {
    //     //     fn callback(
    //     //         ud1: ?*ServerConnection,
    //     //         _: *xev.Loop,
    //     //         _: *xev.Completion,
    //     //         _: xev.TCP,
    //     //         r1: xev.CloseError!void,
    //     //     ) xev.CallbackAction {
    //     //         _ = r1 catch unreachable;
    //     //         ud1.?.*.state = .closed;
    //     //         ud1.?.*.socket = null;
    //     //         return .disarm;
    //     //     }
    //     // }).callback);

    //     server_conn.completion = .{
    //         .op = .{
    //             .close = .{
    //                 .fd = server_conn.socket.?.fd,
    //             },
    //         },

    //         .userdata = server_conn,
    //         .callback = (struct {
    //             fn callback(ud: ?*anyopaque, l: *xev.Loop, c: *xev.Completion, r: xev.Result) xev.CallbackAction {
    //                 _ = l;
    //                 _ = c;
    //                 _ = r.close catch unreachable;
    //                 const ptr = @as(*std.os.socket_t, @ptrCast(@alignCast(ud.?)));
    //                 ptr.* = 0;
    //                 return .disarm;
    //             }
    //         }).callback,
    //     };

    //     loop.add(server_conn.completion);
    // }
};

const Receiver = struct {
    loop: *xev.Loop,
    conn: *ServerConnection,
    completion: xev.Completion = .{},
    buf: [4096]u8 = undefined,
    bytes_read: usize = 0,

    pub fn read(receiver: *@This()) void {
        if (receiver.bytes_read == receiver.buf.len) return;

        var read_buf = xev.ReadBuffer{
            .slice = receiver.buf[receiver.bytes_read..],
        };
        receiver.conn.socket.?.read(receiver.loop, &receiver.completion, read_buf, @This(), receiver, readCb);
    }

    pub fn readCb(
        receiver_opt: ?*@This(),
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.TCP,
        _: xev.ReadBuffer,
        r: xev.TCP.ReadError!usize,
    ) xev.CallbackAction {
        var receiver = receiver_opt.?;
        var n_bytes = r catch unreachable;

        receiver.bytes_read += n_bytes;
        if (receiver.bytes_read < 4096) {
            receiver.read();
        }

        return .disarm;
    }
};

fn writeResponse(write_buf: []u8) !void {
    const response_content = "Hello, World!";

    var stream = std.io.fixedBufferStream(write_buf);
    const w = stream.writer();

    const version: std.http.Version = .@"HTTP/1.1";
    const status: std.http.Status = .ok;

    try w.writeAll(@tagName(version));
    try w.writeByte(' ');
    try w.print("{d}", .{@intFromEnum(status)});
    try w.writeByte(' ');
    // if (res.reason) |reason| {
    //     try w.writeAll(reason);
    // } else if (res.status.phrase()) |phrase| {
    //     try w.writeAll(phrase);
    // }
    try w.writeAll("\r\n");

    try w.print("Content-Length: {d}\r\n", .{response_content.len});

    // if (res.status == .@"continue") {
    //     res.state = .waited; // we still need to send another request after this
    // } else {
    //     if (!res.headers.contains("server")) {
    //         try w.writeAll("Server: zig (std.http)\r\n");
    //     }

    //     if (!res.headers.contains("connection")) {
    //         const req_connection = res.request.headers.getFirstValue("connection");
    //         const req_keepalive = req_connection != null and !std.ascii.eqlIgnoreCase("close", req_connection.?);

    //         if (req_keepalive) {
    //             try w.writeAll("Connection: keep-alive\r\n");
    //         } else {
    //             try w.writeAll("Connection: close\r\n");
    //         }
    //     }

    //     const has_transfer_encoding = res.headers.contains("transfer-encoding");
    //     const has_content_length = res.headers.contains("content-length");

    //     if (!has_transfer_encoding and !has_content_length) {
    //         switch (res.transfer_encoding) {
    //             .chunked => try w.writeAll("Transfer-Encoding: chunked\r\n"),
    //             .content_length => |content_length| try w.print("Content-Length: {d}\r\n", .{content_length}),
    //             .none => {},
    //         }
    //     } else {
    //         if (has_content_length) {
    //             const content_length = std.fmt.parseInt(u64, res.headers.getFirstValue("content-length").?, 10) catch return error.InvalidContentLength;

    //             res.transfer_encoding = .{ .content_length = content_length };
    //         } else if (has_transfer_encoding) {
    //             const transfer_encoding = res.headers.getFirstValue("transfer-encoding").?;
    //             if (std.mem.eql(u8, transfer_encoding, "chunked")) {
    //                 res.transfer_encoding = .chunked;
    //             } else {
    //                 return error.UnsupportedTransferEncoding;
    //             }
    //         } else {
    //             res.transfer_encoding = .none;
    //         }
    //     }

    //     try w.print("{}", .{res.headers});
    // }

    // if (res.request.method == .HEAD) {
    //     res.transfer_encoding = .none;
    // }

    try w.writeAll("\r\n");
    try w.writeAll(response_content);
}

fn read_callback(
    server_connection: ?*ServerConnection,
    loop: *xev.Loop,
    comp: *xev.Completion,
    _: xev.TCP,
    _: xev.ReadBuffer,
    _: xev.ReadError!usize,
) xev.CallbackAction {
    // server_connection.?.*.request = Request{
    //     .method = undefined,
    //     .target = undefined,
    //     .version = undefined,
    //     // .headers = .{ .allocator = server_connection.?.*.allocator, .owned = true },
    //     // .parser = std.http.protocol.HeadersParser.initDynamic(8192),
    // };
    // server_connection.?.*.request.parse(rb.slice) catch |err| {
    //     std.debug.print("failed to parse req: {any}\n", .{err});
    //     defer server_connection.?.*.deinit();
    // };
    // std.debug.print("read socket\n", .{});
    // std.debug.print("read socket: {any}\n", .{rb.slice});
    // std.debug.print("read socket req: {s}\n", .{server_connection.?.*.request.target});

    // generate response
    // var write_buf: [8192]u8 = undefined;

    // writeResponse(&write_buf) catch |err| {
    //     std.debug.print("failed to create response: {any}\n", .{err});
    // };
    const write_buf = "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 14\r\nConnection: keep-alive\r\n\r\nHello, World!\n";

    var sent_unqueued: usize = 0;
    defer server_connection.?.socket.?.write(loop, comp, .{ .slice = write_buf }, usize, &sent_unqueued, (struct {
        fn callback(
            sent_unqueued_inner: ?*usize,
            l1: *xev.Loop,
            c1: *xev.Completion,
            tcp: xev.TCP,
            _: xev.WriteBuffer,
            r: xev.TCP.WriteError!usize,
        ) xev.CallbackAction {
            sent_unqueued_inner.?.* = r catch unreachable;
            // _ = l1;
            // _ = c1;
            // _ = tcp;
            defer tcp.close(l1, c1, void, null, (struct {
                fn callback(
                    _: ?*void,
                    _: *xev.Loop,
                    _: *xev.Completion,
                    _: xev.TCP,
                    _: xev.TCP.ShutdownError!void,
                ) xev.CallbackAction {
                    // std.debug.print("close\n", .{});
                    return .disarm;
                }
            }).callback);

            return .disarm;
        }
    }).callback);

    return .disarm;
}

// const RequestHeader = struct {
//     noHTTP11: bool,
//     connectionClose: bool,
//     noDefaultContentType: bool,
//     disableSpecialHeader: bool,
// };
const Compression = union(enum) {
    none: void,
};

const Request = struct {
    pub const ParseError = Allocator.Error || error{
        UnknownHttpMethod,
        HttpHeadersInvalid,
        HttpHeaderContinuationsUnsupported,
        HttpTransferEncodingUnsupported,
        HttpConnectionHeaderUnsupported,
        InvalidContentLength,
        CompressionNotSupported,
    };

    pub fn parse(req: *Request, bytes: []const u8) ParseError!void {
        var it = std.mem.tokenizeAny(u8, bytes[0 .. bytes.len - 4], "\r\n");

        const first_line = it.next() orelse return error.HttpHeadersInvalid;
        if (first_line.len < 10)
            return error.HttpHeadersInvalid;

        const method_end = std.mem.indexOfScalar(u8, first_line, ' ') orelse return error.HttpHeadersInvalid;
        if (method_end > 24) return error.HttpHeadersInvalid;

        const method_str = first_line[0..method_end];
        const method: std.http.Method = @enumFromInt(std.http.Method.parse(method_str));

        const version_start = std.mem.lastIndexOfScalar(u8, first_line, ' ') orelse return error.HttpHeadersInvalid;
        if (version_start == method_end) return error.HttpHeadersInvalid;

        const version_str = first_line[version_start + 1 ..];
        if (version_str.len != 8) return error.HttpHeadersInvalid;
        const version: std.http.Version = switch (int64(version_str[0..8])) {
            int64("HTTP/1.0") => .@"HTTP/1.0",
            int64("HTTP/1.1") => .@"HTTP/1.1",
            else => return error.HttpHeadersInvalid,
        };

        const target = first_line[method_end + 1 .. version_start];

        req.method = method;
        req.target = target;
        req.version = version;

        // while (it.next()) |line| {
        //     if (line.len == 0) return error.HttpHeadersInvalid;
        //     switch (line[0]) {
        //         ' ', '\t' => return error.HttpHeaderContinuationsUnsupported,
        //         else => {},
        //     }

        //     var line_it = mem.tokenizeAny(u8, line, ": ");
        //     const header_name = line_it.next() orelse return error.HttpHeadersInvalid;
        //     const header_value = line_it.rest();

        //     try req.headers.append(header_name, header_value);

        //     if (std.ascii.eqlIgnoreCase(header_name, "content-length")) {
        //         if (req.content_length != null) return error.HttpHeadersInvalid;
        //         req.content_length = std.fmt.parseInt(u64, header_value, 10) catch return error.InvalidContentLength;
        //     } else if (std.ascii.eqlIgnoreCase(header_name, "transfer-encoding")) {
        //         // Transfer-Encoding: second, first
        //         // Transfer-Encoding: deflate, chunked
        //         var iter = mem.splitBackwardsScalar(u8, header_value, ',');

        //         if (iter.next()) |first| {
        //             const trimmed = mem.trim(u8, first, " ");

        //             if (std.meta.stringToEnum(http.TransferEncoding, trimmed)) |te| {
        //                 if (req.transfer_encoding != null) return error.HttpHeadersInvalid;
        //                 req.transfer_encoding = te;
        //             } else if (std.meta.stringToEnum(http.ContentEncoding, trimmed)) |ce| {
        //                 if (req.transfer_compression != null) return error.HttpHeadersInvalid;
        //                 req.transfer_compression = ce;
        //             } else {
        //                 return error.HttpTransferEncodingUnsupported;
        //             }
        //         }

        //         if (iter.next()) |second| {
        //             if (req.transfer_compression != null) return error.HttpTransferEncodingUnsupported;

        //             const trimmed = mem.trim(u8, second, " ");

        //             if (std.meta.stringToEnum(http.ContentEncoding, trimmed)) |ce| {
        //                 req.transfer_compression = ce;
        //             } else {
        //                 return error.HttpTransferEncodingUnsupported;
        //             }
        //         }

        //         if (iter.next()) |_| return error.HttpTransferEncodingUnsupported;
        //     } else if (std.ascii.eqlIgnoreCase(header_name, "content-encoding")) {
        //         if (req.transfer_compression != null) return error.HttpHeadersInvalid;

        //         const trimmed = mem.trim(u8, header_value, " ");

        //         if (std.meta.stringToEnum(http.ContentEncoding, trimmed)) |ce| {
        //             req.transfer_compression = ce;
        //         } else {
        //             return error.HttpTransferEncodingUnsupported;
        //         }
        //     }
        // }
    }

    inline fn int64(array: *const [8]u8) u64 {
        return @as(u64, @bitCast(array.*));
    }

    method: std.http.Method,
    target: []const u8,
    version: std.http.Version,

    content_length: ?u64 = null,
    transfer_encoding: ?std.http.TransferEncoding = null,
    transfer_compression: ?std.http.ContentEncoding = null,

    // headers: http.Headers,
    // parser: proto.HeadersParser,
    compression: Compression = .none,
};

fn runAsyncLoop(app: *App, loop: *xev.Loop) !void {
    // var connection_accepter = try xev.Async.init();
    // defer connection_accepter.deinit();

    std.debug.print("app pointer: {*}\n", .{app});

    while (true) {
        // if (app.connections.items.len < 4) { // TODO: Dynamic connections size
        // std.debug.print("Added Connection\n", .{});
        //ud.?.connections.append(ServerConnection{}) catch unreachable;
        //std.debug.print("loop\n", .{});

        //var accepter_wait: xev.Completion = undefined;

        // const server_conn = try app.connections.allocator.create(ServerConnection);
        // errdefer app.connections.allocator.destroy(server_conn);
        // while (true) {
        // try app.connections.append(ServerConnection{ .allocator = app.allocator, .request = Request{
        //     .method = undefined,
        //     .target = undefined,
        //     .version = undefined,
        // } });
        // var server_conn = app.connections.items[app.connections.items.len - 1];
        var server_conn = ServerConnection{ .allocator = app.allocator, .request = Request{
            .method = undefined,
            .target = undefined,
            .version = undefined,
        } };
        app.socket.?.accept(loop, &server_conn.completion, ServerConnection, &server_conn, (struct {
            fn callback(
                connection: ?*ServerConnection,
                l: *xev.Loop,
                comp: *xev.Completion,
                r1: xev.AcceptError!xev.TCP,
            ) xev.CallbackAction {

                // ud1.?.*.socket = r1 catch unreachable;
                //std.debug.print("Accept: {any}\n", .{r1});
                //ud.?.*.connections.append(ServerConnection{ .state = .accepted, .socket = r1 catch unreachable }) catch unreachable;
                //std.debug.print("Accept List Len: {d}\n", .{ud.?.*.connections.items.len});
                //ud1.?.state = .accepted;
                connection.?.socket = r1 catch |err| {
                    std.debug.print("Failed to Appect: {any}\n", .{err});
                    switch (err) {
                        error.Unexpected => @panic("Unexpected Error"),
                        else => return .disarm,
                    }
                    // if (err == .Unexpected) ;

                };
                //std.debug.print("accept: {any}\n", .{connection.?.socket.?});
                connection.?.state = .accepted;

                //

                // defer _ = connection.?.sc_respond(loop, comp);
                // TODO Async read and send instead of zig std stuff

                // maybe this works??

                // 8KB header read
                var recv_buf: [8192]u8 = undefined;
                defer connection.?.socket.?.read(l, comp, .{ .slice = &recv_buf }, ServerConnection, connection.?, read_callback);

                // var receiver = Receiver{
                //     .loop = loop,
                //     .conn = connection.?,
                // };
                // receiver.read();
                // server_connection.?.*.request.?.parse(receiver.slice) catch |err| {
                //     std.debug.print("failed to parse req: {any}\n", .{err});
                // };

                return .disarm;
            }
        }).callback);

        try loop.run(.once);
    }
}

fn runAsyncLoop2(app: *App, loop: *xev.Loop) !void {
    while (true) {
        var server_conn = ServerConnection{ .allocator = app.allocator, .request = Request{
            .method = undefined,
            .target = undefined,
            .version = undefined,
        } };

        //var accept_comp: xev.Completion = undefined;

        app.socket.?.accept(loop, &server_conn.completion, ServerConnection, &server_conn, (struct {
            fn callback(
                connection: ?*ServerConnection,
                _: *xev.Loop,
                _: *xev.Completion,
                r1: xev.AcceptError!xev.TCP,
            ) xev.CallbackAction {
                connection.?.socket = r1 catch |err| {
                    std.debug.print("Failed to Appect: {any}\n", .{err});
                    switch (err) {
                        error.Unexpected => @panic("Unexpected Error"),
                        else => return .disarm,
                    }
                };
                //std.debug.print("accept: {any}\n", .{connection.?.socket.?});
                connection.?.state = .accepted;

                return .disarm;
            }
        }).callback);

        try loop.run(.until_done);

        var recv_buf: [8192]u8 = undefined;
        server_conn.socket.?.read(loop, &server_conn.completion, .{ .slice = &recv_buf }, ServerConnection, &server_conn, (struct {
            fn callback(
                _: ?*ServerConnection,
                _: *xev.Loop,
                _: *xev.Completion,
                _: xev.TCP,
                _: xev.ReadBuffer,
                _: xev.ReadError!usize,
            ) xev.CallbackAction {
                // Read Request when I start caring
                return .disarm;
            }
        }).callback);

        try loop.run(.until_done);

        const write_buf = "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 14\r\nConnection: keep-alive\r\n\r\nHello, World!\n";
        var sent_unqueued: usize = 0;
        server_conn.socket.?.write(loop, &server_conn.completion, .{ .slice = write_buf }, usize, &sent_unqueued, (struct {
            fn callback(
                sent_unqueued_inner: ?*usize,
                _: *xev.Loop,
                _: *xev.Completion,
                _: xev.TCP,
                _: xev.WriteBuffer,
                r: xev.TCP.WriteError!usize,
            ) xev.CallbackAction {
                sent_unqueued_inner.?.* = r catch unreachable;
                // _ = l1;
                // _ = c1;
                // _ = tcp;

                return .disarm;
            }
        }).callback);

        try loop.run(.until_done);

        server_conn.socket.?.close(loop, &server_conn.completion, void, null, (struct {
            fn callback(
                _: ?*void,
                _: *xev.Loop,
                _: *xev.Completion,
                _: xev.TCP,
                _: xev.TCP.ShutdownError!void,
            ) xev.CallbackAction {
                // std.debug.print("close\n", .{});
                return .disarm;
            }
        }).callback);

        try loop.run(.until_done);
    }
}

fn runAsyncLoop3(app: *App, loop: *xev.Loop) !void {
    const log: bool = false;

    while (true) {
        if (app.accept_comp.state() == .dead) {
            var new_server_conn = try app.allocator.create(ServerConnection);
            new_server_conn.completion = xev.Completion{};
            new_server_conn.state = .none;
            new_server_conn.request = Request{
                .method = undefined,
                .target = undefined,
                .version = undefined,
            };

            try app.connections.append(new_server_conn);

            app.socket.?.accept(loop, &app.accept_comp, ServerConnection, new_server_conn, (struct {
                fn callback(
                    connection: ?*ServerConnection,
                    _: *xev.Loop,
                    _: *xev.Completion,
                    r1: xev.AcceptError!xev.TCP,
                ) xev.CallbackAction {
                    connection.?.socket = r1 catch |err| {
                        std.debug.print("Failed to Appect: {any}\n", .{err});
                        switch (err) {
                            error.Unexpected => @panic("Unexpected Error"),
                            else => return .disarm,
                        }
                    };
                    connection.?.state = .accepted;

                    return .disarm;
                }
            }).callback);
        }

        var i: usize = 0;
        while (i < app.connections.items.len) {
            var conn = app.connections.items[i];
            var remove = false;
            switch (conn.state) {
                .accepted, .read => {
                    if (log) std.debug.print("Reading connection: {d}...\n", .{i});
                    conn.state = .awaiting;
                    var recv_buf: [8192]u8 = undefined;
                    conn.socket.?.read(loop, &conn.completion, .{ .slice = &recv_buf }, ServerConnection, conn, (struct {
                        fn callback(
                            sc: ?*ServerConnection,
                            _: *xev.Loop,
                            _: *xev.Completion,
                            _: xev.TCP,
                            _: xev.ReadBuffer,
                            _: xev.ReadError!usize,
                        ) xev.CallbackAction {
                            // Read Request when I start caring
                            sc.?.state = .write;
                            return .disarm;
                        }
                    }).callback);
                },
                .write => {
                    if (log) std.debug.print("Writing connection: {d}...\n", .{i});
                    conn.state = .awaiting;
                    const write_buf = "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 14\r\nConnection: close\r\n\r\nHello, World!\n";
                    conn.socket.?.write(loop, &conn.completion, .{ .slice = write_buf }, ServerConnection, conn, (struct {
                        fn callback(
                            sc: ?*ServerConnection,
                            _: *xev.Loop,
                            _: *xev.Completion,
                            _: xev.TCP,
                            _: xev.WriteBuffer,
                            _: xev.TCP.WriteError!usize,
                        ) xev.CallbackAction {
                            sc.?.state = .close;

                            return .disarm;
                        }
                    }).callback);
                },
                .close => {
                    if (log) std.debug.print("Closing connection: {d}...\n", .{i});
                    conn.state = .awaiting;
                    conn.socket.?.close(loop, &conn.completion, ServerConnection, conn, (struct {
                        fn callback(
                            sc: ?*ServerConnection,
                            _: *xev.Loop,
                            _: *xev.Completion,
                            _: xev.TCP,
                            _: xev.TCP.ShutdownError!void,
                        ) xev.CallbackAction {
                            sc.?.state = .dead;

                            return .disarm;
                        }
                    }).callback);
                },
                .dead => {
                    remove = true;
                },
                else => {},
            }

            if (remove) {
                if (log) std.debug.print("Removing connection: {d}...\n", .{i});
                var sc = app.connections.orderedRemove(i);
                defer app.allocator.destroy(sc);
            } else {
                i += 1;
            }
        }

        // need to learn batching
        try loop.run(.once);
    }
}

fn runAsyncLoop4(app: *App, loop: *xev.Loop) !void {
    const log: bool = false;

    while (true) {
        const now = time.DateTime.now();

        var date: [25]u8 = undefined;
        //Wed, 21 Oct 2015 07:28:00 GMT
        const format = "ddd, DD MMM YYYY HH:mm:ss";
        var stream = std.io.fixedBufferStream(&date);
        const w = stream.writer();
        try now.format(format, .{}, w);

        if (app.accept_comp.state() == .dead) {
            var new_server_conn = try app.allocator.create(ServerConnection);
            new_server_conn.completion = xev.Completion{};
            new_server_conn.state = .none;
            new_server_conn.request = Request{
                .method = undefined,
                .target = undefined,
                .version = undefined,
            };

            try app.connections.append(new_server_conn);

            app.socket.?.accept(loop, &app.accept_comp, ServerConnection, new_server_conn, (struct {
                fn callback(
                    connection: ?*ServerConnection,
                    _: *xev.Loop,
                    _: *xev.Completion,
                    r1: xev.AcceptError!xev.TCP,
                ) xev.CallbackAction {
                    connection.?.socket = r1 catch |err| {
                        std.debug.print("Failed to Appect: {any}\n", .{err});
                        switch (err) {
                            error.Unexpected => @panic("Unexpected Error"),
                            else => return .disarm,
                        }
                    };
                    connection.?.state = .accepted;

                    return .disarm;
                }
            }).callback);
        }

        var i: usize = 0;
        while (i < app.connections.items.len) {
            var conn = app.connections.items[i];
            var remove = false;
            switch (conn.state) {
                .accepted, .read => {
                    if (log) std.debug.print("Reading connection: {d}...\n", .{i});
                    conn.state = .awaiting;
                    var recv_buf: [8192]u8 = undefined;
                    conn.socket.?.read(loop, &conn.completion, .{ .slice = &recv_buf }, ServerConnection, conn, (struct {
                        fn callback(
                            sc: ?*ServerConnection,
                            _: *xev.Loop,
                            _: *xev.Completion,
                            _: xev.TCP,
                            _: xev.ReadBuffer,
                            rl: xev.ReadError!usize,
                        ) xev.CallbackAction {
                            _ = rl catch |err| {
                                if (log) std.debug.print("Read Error: {any}\n", .{err});
                                sc.?.state = .close;
                                return .disarm;
                            };
                            // Read Request when I start caring
                            // if (rb.slice.len == 0) {
                            //     //sc.?.state = .write;
                            //     std.debug.print("rearm read\n", .{});
                            //     return .rearm;
                            // }
                            sc.?.state = .write;
                            return .disarm;
                        }
                    }).callback);
                },
                .write => {
                    if (log) std.debug.print("Writing connection: {d}...\n", .{i});
                    conn.state = .awaiting;

                    const write_buf = "HTTP/1.1 200 \r\nConnection: keep-alive\r\nContent-Type: text/plain\r\nDate: " ++ date ++ " GMT\r\nLast-Modifed: " ++ date ++ " GMT\r\nContent-Length: 17\r\n\r\nHello from ZAP!!!\n";
                    conn.socket.?.write(loop, &conn.completion, .{ .slice = write_buf }, ServerConnection, conn, (struct {
                        fn callback(
                            sc: ?*ServerConnection,
                            _: *xev.Loop,
                            _: *xev.Completion,
                            _: xev.TCP,
                            _: xev.WriteBuffer,
                            written: xev.TCP.WriteError!usize,
                        ) xev.CallbackAction {
                            _ = written catch |err| {
                                if (log) std.debug.print("Write Error: {any}\n", .{err});
                                sc.?.state = .close;
                                return .disarm;
                            };

                            // std.debug.print("keep-alive to read\n", .{});
                            sc.?.state = .read;

                            return .disarm;
                        }
                    }).callback);
                },
                .close => {
                    std.debug.print("Closing connection: {d}...\n", .{i});
                    conn.state = .awaiting;
                    conn.socket.?.close(loop, &conn.completion, ServerConnection, conn, (struct {
                        fn callback(
                            sc: ?*ServerConnection,
                            _: *xev.Loop,
                            _: *xev.Completion,
                            _: xev.TCP,
                            _: xev.TCP.ShutdownError!void,
                        ) xev.CallbackAction {
                            sc.?.state = .dead;

                            return .disarm;
                        }
                    }).callback);
                },
                .dead => {
                    remove = true;
                },
                else => {},
            }

            if (remove) {
                if (log) std.debug.print("Removing connection: {d}...\n", .{i});
                var sc = app.connections.orderedRemove(i);
                defer app.allocator.destroy(sc);
            } else {
                i += 1;
            }
        }

        // need to learn batching
        try loop.run(.once);
    }
}

fn runAsyncLoop5(app: *App, loop: *xev.Loop) !void {
    const log: bool = false;

    while (true) {
        try app.generateGMTDate();

        if (app.accept_comp.state() == .dead) {
            var new_server_conn = try app.allocator.create(ServerConnection);
            new_server_conn.completion = xev.Completion{};
            new_server_conn.app = app;
            new_server_conn.state = .none;
            new_server_conn.request = Request{
                .method = undefined,
                .target = undefined,
                .version = undefined,
            };

            try app.connections.append(new_server_conn);

            app.socket.?.accept(loop, &app.accept_comp, ServerConnection, new_server_conn, (struct {
                fn callback(
                    connection: ?*ServerConnection,
                    loop1: *xev.Loop,
                    _: *xev.Completion,
                    r1: xev.AcceptError!xev.TCP,
                ) xev.CallbackAction {
                    connection.?.socket = r1 catch |err| {
                        std.debug.print("Failed to Appect: {any}\n", .{err});
                        switch (err) {
                            error.Unexpected => @panic("Unexpected Error"),
                            else => return .disarm,
                        }
                    };
                    connection.?.state = .accepted;
                    //defer connection.?.socket.?.read(loop1, &connection.?.completion, .{ .slice = &connection.?.recv_buf }, ServerConnection, connection, connection.?.*.read_cb);
                    defer connection.?.read(loop1);

                    return .disarm;
                }
            }).callback);
        }

        var i: usize = 0;
        while (i < app.connections.items.len) {
            var conn = app.connections.items[i];
            var remove = false;
            switch (conn.state) {
                // .accepted, .read => {
                //     if (log) std.debug.print("Reading connection: {d}...\n", .{i});
                //     conn.state = .awaiting;
                //     var recv_buf: [8192]u8 = undefined;
                //     conn.socket.?.read(loop, &conn.completion, .{ .slice = &recv_buf }, ServerConnection, conn, (struct {
                //         fn callback(
                //             sc: ?*ServerConnection,
                //             _: *xev.Loop,
                //             _: *xev.Completion,
                //             _: xev.TCP,
                //             _: xev.ReadBuffer,
                //             rl: xev.ReadError!usize,
                //         ) xev.CallbackAction {
                //             _ = rl catch |err| {
                //                 if (log) std.debug.print("Read Error: {any}\n", .{err});
                //                 sc.?.state = .close;
                //                 return .disarm;
                //             };
                //             // Read Request when I start caring
                //             // if (rb.slice.len == 0) {
                //             //     //sc.?.state = .write;
                //             //     std.debug.print("rearm read\n", .{});
                //             //     return .rearm;
                //             // }
                //             sc.?.state = .write;
                //             return .disarm;
                //         }
                //     }).callback);
                // },
                // .write => {
                //     if (log) std.debug.print("Writing connection: {d}...\n", .{i});
                //     conn.state = .awaiting;

                //     const write_buf = "HTTP/1.1 200 \r\nConnection: keep-alive\r\nContent-Type: text/plain\r\nDate: " ++ conn.app.gmt_date ++ " GMT\r\nLast-Modifed: " ++ conn.app.gmt_date ++ " GMT\r\nContent-Length: 17\r\n\r\nHello from ZAP!!!\n";
                //     conn.socket.?.write(loop, &conn.completion, .{ .slice = write_buf }, ServerConnection, conn, (struct {
                //         fn callback(
                //             sc: ?*ServerConnection,
                //             _: *xev.Loop,
                //             _: *xev.Completion,
                //             _: xev.TCP,
                //             _: xev.WriteBuffer,
                //             written: xev.TCP.WriteError!usize,
                //         ) xev.CallbackAction {
                //             _ = written catch |err| {
                //                 if (log) std.debug.print("Write Error: {any}\n", .{err});
                //                 sc.?.state = .close;
                //                 return .disarm;
                //             };

                //             // std.debug.print("keep-alive to read\n", .{});
                //             sc.?.state = .read;

                //             return .disarm;
                //         }
                //     }).callback);
                // },
                // .close => {
                //     std.debug.print("Closing connection: {d}...\n", .{i});
                //     conn.state = .awaiting;
                //     conn.socket.?.close(loop, &conn.completion, ServerConnection, conn, (struct {
                //         fn callback(
                //             sc: ?*ServerConnection,
                //             _: *xev.Loop,
                //             _: *xev.Completion,
                //             _: xev.TCP,
                //             _: xev.TCP.ShutdownError!void,
                //         ) xev.CallbackAction {
                //             sc.?.state = .dead;

                //             return .disarm;
                //         }
                //     }).callback);
                // },
                .dead => {
                    remove = true;
                },
                else => {},
            }

            if (remove) {
                if (log) std.debug.print("Removing connection: {d}...\n", .{i});
                var sc = app.connections.orderedRemove(i);
                defer app.allocator.destroy(sc);
            } else {
                i += 1;
            }
        }

        // need to learn batching
        try loop.run(.once);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("LEAK!!!");
    }

    var loop = try xev.Loop.init(.{});
    defer loop.deinit();
    var loop2 = try xev.Loop.init(.{});
    defer loop2.deinit();

    // var worker_loop = try xev.Loop.init(.{});
    // defer worker_loop.deinit();

    var app = try App.init(allocator);
    defer app.deinit();
    try app.listen("0.0.0.0", 3000);

    // const thread = try std.Thread.spawn(.{}, runAsyncLoop, .{ &app, &loop });
    // const thread2 = try std.Thread.spawn(.{}, runAsyncLoop, .{ &app, &loop2 });
    // defer thread.join();
    // defer thread2.join();

    // const tp = xev.ThreadPool.init(.{});

    // tp.register(thread);
    // tp.register(thread2);

    // while (true) {}

    try runAsyncLoop5(&app, &loop);
}

test {
    _ = @import("HttpAppFramework.zig");
}
