// Taken from zig.std lib v0.12
// changed to use header struct vs hashmap and to work with libxev tcp

const std = @import("std");

const Connection = @import("connection.zig").Connection;
const header = @import("header.zig");

const Self = @This();

connection: Connection,

version: std.http.Version = .@"HTTP/1.1",
status: std.http.Status = .ok,
reason: ?[]const u8 = null,

headers: header.ResponseHeaders = .{},

state: State = .first,

// TODO: Configurable o_buf size and possible ArrayList due to keep lifetime of buffer up while it is needed. Could have things freed up as callbacks happen?
o_buf: [4096]u8 = undefined,

current_stream: ?std.io.FixedBufferStream([]u8) = null,
// o_len: usize,

const State = enum {
    first,
    responded,
    finished,
};

pub fn deinit(_: *Self) void {}

pub const ResetState = enum { reset, closing };

/// Reset this response to its initial state. This must be called before handling a second request on the same connection.
pub fn reset(_: *Self) void {}

/// Send the response headers.
pub fn do(res: *Self) !void {
    switch (res.state) {
        .waited => res.state = .responded,
        .first, .start, .responded, .finished => unreachable,
    }

    var buffered = std.io.bufferedWriter(res.connection.writer());
    const w = buffered.writer();

    try w.writeAll(@tagName(res.version));
    try w.writeByte(' ');
    try w.print("{d}", .{@intFromEnum(res.status)});
    try w.writeByte(' ');
    if (res.reason) |reason| {
        try w.writeAll(reason);
    } else if (res.status.phrase()) |phrase| {
        try w.writeAll(phrase);
    }
    try w.writeAll("\r\n");

    if (res.status == .@"continue") {
        res.state = .waited; // we still need to send another request after this
    } else {
        if (!res.headers.contains("server")) {
            try w.writeAll("Server: zig (std.http)\r\n");
        }

        if (!res.headers.contains("connection")) {
            const req_connection = res.request.headers.getFirstValue("connection");
            const req_keepalive = req_connection != null and !std.ascii.eqlIgnoreCase("close", req_connection.?);

            if (req_keepalive) {
                try w.writeAll("Connection: keep-alive\r\n");
            } else {
                try w.writeAll("Connection: close\r\n");
            }
        }

        const has_transfer_encoding = res.headers.contains("transfer-encoding");
        const has_content_length = res.headers.contains("content-length");

        if (!has_transfer_encoding and !has_content_length) {
            switch (res.transfer_encoding) {
                .chunked => try w.writeAll("Transfer-Encoding: chunked\r\n"),
                .content_length => |content_length| try w.print("Content-Length: {d}\r\n", .{content_length}),
                .none => {},
            }
        } else {
            if (has_content_length) {
                const content_length = std.fmt.parseInt(u64, res.headers.getFirstValue("content-length").?, 10) catch return error.InvalidContentLength;

                res.transfer_encoding = .{ .content_length = content_length };
            } else if (has_transfer_encoding) {
                const transfer_encoding = res.headers.getFirstValue("transfer-encoding").?;
                if (std.mem.eql(u8, transfer_encoding, "chunked")) {
                    res.transfer_encoding = .chunked;
                } else {
                    return error.UnsupportedTransferEncoding;
                }
            } else {
                res.transfer_encoding = .none;
            }
        }

        try w.print("{}", .{res.headers});
    }

    if (res.request.method == .HEAD) {
        res.transfer_encoding = .none;
    }

    try w.writeAll("\r\n");

    try buffered.flush();
}
pub const WriteError = error{ NotWriteable, MessageTooLong };

pub const Writer = std.io.Writer(*Self, anyerror, write);

pub fn writer(self: *Self) Writer {
    return .{ .context = self };
}

// TODO: Handle double buffer scenario to send a buffer in flight while writing locally
/// Write `bytes` to the server. The `transfer_encoding` request header determines how data will be sent.
pub fn write(self: *Self, buf: []const u8) anyerror!usize {
    if (self.current_stream == null) self.current_stream = std.io.fixedBufferStream(&self.o_buf);
    return self.current_stream.?.write(buf);
    //return buf.len;
    // switch (res.state) {
    //     .responded => {},
    //     .first, .waited, .start, .finished => unreachable,
    // }

    // switch (res.transfer_encoding) {
    //     .chunked => {
    //         try res.connection.writer().print("{x}\r\n", .{bytes.len});
    //         try res.connection.writeAll(bytes);
    //         try res.connection.writeAll("\r\n");

    //         return bytes.len;
    //     },
    //     .content_length => |*len| {
    //         if (len.* < bytes.len) return error.MessageTooLong;

    //         const amt = try res.connection.write(bytes);
    //         len.* -= amt;
    //         return amt;
    //     },
    //     .none => return error.NotWriteable,
    // }
}

pub const FinishError = WriteError || error{MessageNotCompleted} || std.fmt.ParseIntError || error{NoSpaceLeft};

/// Finish the body of a request. This notifies the server that you have no more data to send.
pub fn finish(self: *Self) FinishError!void {
    // Means we are done figuring out all of the content needed for the response, write buffer to socket
    if (self.state == .first) {

        // Ensure Content-Length header provided is correct
        // If it were manually set, create for the user
        // TODO: Check for chunked header
        if (self.headers.content_length) |content_length| {
            const cl = try std.fmt.parseInt(usize, content_length, 10);
            if ((self.current_stream == null and cl != 0) or
                (self.current_stream != null and cl != self.current_stream.?.pos))
            {
                return error.MessageNotCompleted;
            }
        }

        // TODO: Prepend buffer ArrayList with a frame to render Header
        var header_buf: [4096]u8 = undefined;
        var resp_stream = std.io.fixedBufferStream(&header_buf);
        const w = resp_stream.writer();

        try w.writeAll(@tagName(self.version));
        try w.writeByte(' ');
        try w.print("{d}", .{@intFromEnum(self.status)});
        try w.writeByte(' ');
        try w.writeAll("\r\n");

        if (self.headers.content_length == null) {
            try w.print("Content-Length: {d}\r\n", .{if (self.current_stream) |s| s.pos else 0});
        }

        try self.headers.bufWrite(&resp_stream);

        // TODO: Split responses if headers ate up enough of the buffer to not send in one go
        if (self.current_stream) |stream| try w.writeAll(stream.getWritten());

        self.connection.write(resp_stream.getWritten());
    }
}
