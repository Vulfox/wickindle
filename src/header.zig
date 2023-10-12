// TODO: Possibly use CompHeadersTable to comptime a bunch of the header stuff
//       maybe even do a check on header usage to dynamically determine a struct needed for a given request?

const std = @import("std");

const HeaderCtx = enum {
    Request,
    Response,
    Both,
};
// Name, HeaderCtx,
const CompHeadersTable = .{
    .{ "Cache-Control", .Both },
    .{ "Connection", .Both },
    .{ "Content-Encoding", .Both },
    .{ "Content-Length", .Both },
    .{ "Content-Type", .Both },
    .{ "Date", .Both },
    .{ "Pragma", .Both },
    .{ "Trailer", .Both },
    .{ "Transfer-Encoding", .Both },
    .{ "Upgrade", .Both },
    .{ "Via", .Both },

    .{ "A-IM", .Request },
    .{ "Accept", .Request },
    .{ "Accept-Charset", .Request },
    .{ "Accept_Datetime", .Request },
    .{ "Accept-Encoding", .Request },
    .{ "Aaccept-Language", .Request },
    .{ "Access-Control-Request-Method", .Request },
    .{ "Access-Control-Request-Headers", .Request },
    .{ "Authorization", .Request },
    .{ "Cookie", .Request },
    .{ "Expect", .Request },
    .{ "Forwarded", .Request },
    .{ "From", .Request },
    .{ "Host", .Request },
    .{ "If-Match", .Request },
    .{ "If-Modified-Since", .Request },
    .{ "If-None-Match", .Request },
    .{ "If-Range", .Request },
    .{ "If-Unmodified-Since", .Request },
    .{ "Max-Forwards", .Request },
    .{ "Origin", .Request },
    .{ "Prefer", .Request },
    .{ "Proxy-Authorization", .Request },
    .{ "Range", .Request },
    .{ "Referer", .Request },
    .{ "TE", .Request },
    .{ "User-Agent", .Request },

    .{ "X-Correlation-Id", .Request },
};

pub const RequestHeaders = struct {
    content_length: ?[]const u8 = null,
    host: ?[]const u8 = null,
    connection: ?[]const u8 = null,
    accept: ?[]const u8 = null,
    user_agent: ?[]const u8 = null,

    pub inline fn setHeader(self: *RequestHeaders, header_name: []const u8, header_value: []const u8) Header {
        // const header_en: Header = .host;
        // _ = self;
        // _ = header_name;
        // _ = header_value;

        const header_en = fromName(header_name);

        switch (header_en) {
            .content_length => if (self.content_length == null) {
                self.content_length = header_value;
            },
            .host => if (self.host == null) {
                self.host = header_value;
            },
            .connection => if (self.connection == null) {
                self.connection = header_value;
            },
            .accept => if (self.accept == null) {
                self.accept = header_value;
            },
            .user_agent => if (self.user_agent == null) {
                self.user_agent = header_value;
            },
            else => {},
        }

        return header_en;
    }
};

pub const ResponseHeaders = struct {
    content_length: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
    connection: ?[]const u8 = null,
    date: ?[]const u8 = null,
    last_modified: ?[]const u8 = null,

    pub inline fn setHeader(self: *RequestHeaders, header_name: []const u8, header_value: []const u8) Header {
        const header_en = fromName(header_name);

        switch (header_en) {
            .content_length => if (self.content_length == null) {
                self.content_length = header_value;
            },
            .content_type => if (self.content_type == null) {
                self.content_type = header_value;
            },
            .connection => if (self.connection == null) {
                self.connection = header_value;
            },
            .date => if (self.date == null) {
                self.date = header_value;
            },
            .last_modified => if (self.last_modified == null) {
                self.last_modified = header_value;
            },
            else => {},
        }

        return header_en;
    }

    pub fn bufWrite(self: *ResponseHeaders, stream: *std.io.FixedBufferStream([]u8)) !void {
        inline for (std.meta.fields(ResponseHeaders)) |field| {
            @setEvalBranchQuota(10000);
            if (@field(self, field.name) != null) {
                _ = try stream.write(std.meta.stringToEnum(Header, field.name).?.name());
                _ = try stream.write(": ");
                _ = try stream.write(@field(self, field.name).?);
                _ = try stream.write("\r\n");
            }
        }

        _ = try stream.write("\r\n");
    }
};

// Headers based on non obsolete https://en.wikipedia.org/wiki/List_of_HTTP_header_fields
pub const Header = enum {
    // Common Request/Response Standard
    cache_control,
    connection,
    content_encoding,
    content_length,
    content_type,
    date,
    pragma,
    trailer,
    transfer_encoding,
    upgrade,
    via,

    // Request Standard
    a_aim,
    accept,
    accept_charset,
    accept_datetime,
    accept_encoding,
    accept_language,
    access_control_request_method,
    access_control_request_headers,
    authorization,
    cookie,
    expect,
    forwarded,
    from,
    host,
    if_match,
    if_modified_since,
    if_none_match,
    if_range,
    if_unmodified_since,
    max_forwards,
    origin,
    prefer,
    proxy_authorization,
    range,
    referer,
    te,
    user_agent,

    // Common Request/Response Non-Standard
    x_correlation_id,

    // // Response Standard
    accept_ch,
    access_control_allow_origin,
    access_control_allow_credentials,
    access_control_expose_headers,
    access_control_max_age,
    access_control_allow_methods,
    access_control_allow_headers,
    accept_patch,
    accept_ranges,
    age,
    allow,
    alt_svc,
    content_disposition,
    content_language,
    content_location,
    content_range,
    delta_base,
    etag,
    expires,
    im,
    last_modified,
    link,
    location,
    p3p,
    preference_applied,
    proxy_authenticate,
    public_key_pins,
    retry_after,
    server,
    set_cookie,
    strict_transport_security,
    tk,
    vary,
    www_authenticate,

    // Request Non-Standard
    upgrade_insecure_requests,
    x_requested_with,
    dnt,
    x_forwarded_for,
    x_forwarded_host,
    x_forwarded_post,
    front_end_https,
    x_http_method_override,
    x_att_deviceid,
    x_wap_profile,
    proxy_connection,
    x_uidh,
    x_csrf_token,
    x_request_id,
    correlation_id,
    save_data,
    sec_gpc,

    // // Response Non-Standard
    // content_security_policy,
    // x_content_security_policy,
    // x_webkit_csp,
    // expect_ct,
    // nel,
    // permissions_policy,
    // refresh,
    // report_to,
    // status,
    // timing_allow_origin,
    // x_content_duration,
    // x_content_type_options,
    // x_powered_by,
    // x_redirect_by,
    // x_request_hd,
    // x_ua_compatible,
    // x_xss_protection,

    // converts _ to - for header name compliance
    const HeaderNameTable = init_hnt: {
        @setEvalBranchQuota(10000);
        var header_names: [@typeInfo(Header).Enum.fields.len][]const u8 = undefined;
        inline for (0..@typeInfo(Header).Enum.fields.len) |i| {
            var header_name: [@typeInfo(Header).Enum.fields[i].name.len]u8 = undefined;
            _ = std.mem.replace(u8, @typeInfo(Header).Enum.fields[i].name, "_", "-", &header_name);
            header_names[i] = &header_name;
        }
        break :init_hnt header_names;
    };

    pub inline fn name(self: *const Header) []const u8 {
        return HeaderNameTable[@intFromEnum(self.*)];
    }
};

// case insensitive
// TODO: possibly make this a std.StringHashMap search that was generated from comptime
pub inline fn fromName(name: []const u8) Header {
    if (std.ascii.eqlIgnoreCase(name, Header.content_length.name())) {
        return Header.content_length;
    } else if (std.ascii.eqlIgnoreCase(name, Header.host.name())) {
        return Header.host;
    } else if (std.ascii.eqlIgnoreCase(name, Header.connection.name())) {
        return Header.connection;
    } else if (std.ascii.eqlIgnoreCase(name, Header.accept.name())) {
        return Header.accept;
    } else if (std.ascii.eqlIgnoreCase(name, Header.user_agent.name())) {
        return Header.user_agent;
    }

    return Header.te;
}
