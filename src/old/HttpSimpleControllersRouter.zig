const std = @import("std");

const Self = @This();

pub const PathFiltersMethods = struct {
    path: []const u8,
    filters: ?[][:0]const u8 = null,
    methods: ?[]const HttpMethod = null,
};

pub fn HttpSimpleController(comptime T: type) type {
    return struct {
        pub const paths: []const PathFiltersMethods = T.paths;

        pub fn asyncHandleHttpRequest(comptime callback: fn (req: HttpRequest, resp: HttpResponse) void) !void {
            return T.asyncHandleHttpRequest(callback);
        }
    };
}

pub fn init() Self {
    return Self{};
}

pub fn registerHttpSimpleController(self: *Self, comptime T: type) void {
    _ = HttpSimpleController(T);
    // const ctrl_name = @as([*c]const u8, @ptrCast(@typeName(T)));

    // self.registerClass(ctrl_name, ctrl.asyncHandleHttpRequest);
    // for (ctrl.paths) |path| {
    //     _ = c.HttpAppFramework_registerHttpSimpleController(
    //         self.app_ptr,
    //         @as([*c]const u8, @ptrCast(path.path)),
    //         ctrl_name,
    //         if (path.methods == null) null else @as([*]const u8, @ptrCast(path.methods.?.ptr)),
    //         if (path.methods == null) 0 else path.methods.?.len,
    //         if (path.filters == null) null else @as([*c][*c]const u8, @ptrCast(path.filters.?.ptr)),
    //         if (path.filters == null) 0 else path.filters.?.len,
    //     );
    // }
    // return self;
}
