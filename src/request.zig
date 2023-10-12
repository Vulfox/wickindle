// Taken from zig.std lib v0.12
// Using a memory intensive approach for headers as an alternative to avoiding allocing every request

const std = @import("std");
const mem = std.mem;

const header = @import("header.zig");

const Self = @This();

method: std.http.Method,
target: []const u8,
version: std.http.Version,

content_length: ?u64 = null,
transfer_encoding: ?std.http.TransferEncoding = null,
transfer_compression: ?std.http.ContentEncoding = null,
keep_alive: bool = true,
headers: header.RequestHeaders = .{},

pub fn parse(self: *Self, bytes: []const u8) std.http.Server.Request.ParseError!void {
    var it = mem.tokenizeAny(u8, bytes[0 .. bytes.len - 4], "\r\n");

    const first_line = it.next() orelse return error.HttpHeadersInvalid;
    if (first_line.len < 10)
        return error.HttpHeadersInvalid;

    const method_end = mem.indexOfScalar(u8, first_line, ' ') orelse return error.HttpHeadersInvalid;
    if (method_end > 24) return error.HttpHeadersInvalid;

    const method_str = first_line[0..method_end];
    const method: std.http.Method = @enumFromInt(std.http.Method.parse(method_str));

    const version_start = mem.lastIndexOfScalar(u8, first_line, ' ') orelse return error.HttpHeadersInvalid;
    if (version_start == method_end) return error.HttpHeadersInvalid;

    const version_str = first_line[version_start + 1 ..];
    if (version_str.len != 8) return error.HttpHeadersInvalid;
    const version: std.http.Version = switch (int64(version_str[0..8])) {
        int64("HTTP/1.0") => .@"HTTP/1.0",
        int64("HTTP/1.1") => .@"HTTP/1.1",
        else => return error.HttpHeadersInvalid,
    };

    const target = first_line[method_end + 1 .. version_start];

    self.method = method;
    self.target = target;
    self.version = version;

    while (it.next()) |line| {
        if (line.len == 0) return error.HttpHeadersInvalid;
        switch (line[0]) {
            ' ', '\t' => return error.HttpHeaderContinuationsUnsupported,
            else => {},
        }

        var line_it = mem.tokenizeAny(u8, line, ": ");
        const header_name = line_it.next() orelse return error.HttpHeadersInvalid;
        const header_value = line_it.rest();

        const header_en = self.headers.setHeader(header_name, header_value);

        switch (header_en) {
            .content_length => {
                if (self.content_length != null) return error.HttpHeadersInvalid;
                self.content_length = std.fmt.parseInt(u64, header_value, 10) catch return error.InvalidContentLength;
            },
            .transfer_encoding => {
                // Transfer-Encoding: second, first
                // Transfer-Encoding: deflate, chunked
                var iter = mem.splitBackwardsScalar(u8, header_value, ',');

                if (iter.next()) |first| {
                    const trimmed = mem.trim(u8, first, " ");

                    if (std.meta.stringToEnum(std.http.TransferEncoding, trimmed)) |te| {
                        if (self.transfer_encoding != null) return error.HttpHeadersInvalid;
                        self.transfer_encoding = te;
                    } else if (std.meta.stringToEnum(std.http.ContentEncoding, trimmed)) |ce| {
                        if (self.transfer_compression != null) return error.HttpHeadersInvalid;
                        self.transfer_compression = ce;
                    } else {
                        return error.HttpTransferEncodingUnsupported;
                    }
                }

                if (iter.next()) |second| {
                    if (self.transfer_compression != null) return error.HttpTransferEncodingUnsupported;

                    const trimmed = mem.trim(u8, second, " ");

                    if (std.meta.stringToEnum(std.http.ContentEncoding, trimmed)) |ce| {
                        self.transfer_compression = ce;
                    } else {
                        return error.HttpTransferEncodingUnsupported;
                    }
                }

                if (iter.next()) |_| return error.HttpTransferEncodingUnsupported;
            },
            .content_encoding => {
                if (self.transfer_compression != null) return error.HttpHeadersInvalid;

                const trimmed = mem.trim(u8, header_value, " ");

                if (std.meta.stringToEnum(std.http.ContentEncoding, trimmed)) |ce| {
                    self.transfer_compression = ce;
                } else {
                    return error.HttpTransferEncodingUnsupported;
                }
            },
            .connection => {
                const trimmed = mem.trim(u8, header_value, " ");
                if (std.ascii.eqlIgnoreCase("close", trimmed)) {
                    self.keep_alive = false;
                }
            },
            else => {},
        }
    }
}

pub fn reset(self: *Self) void {
    self.headers = .{};
    self.content_length = null;
    self.transfer_compression = null;
    self.transfer_encoding = null;
}

inline fn int64(array: *const [8]u8) u64 {
    return @as(u64, @bitCast(array.*));
}
