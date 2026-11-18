const builtin = @import("builtin");
const std = @import("std");
const fiscus = @import("fiscus");
const assets = @import("web_assets");

const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    journal_path: []const u8,
};

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    journal_path: []const u8,
    requested_port: u16,
    open_browser: bool,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const address = std.Io.net.IpAddress.parse("127.0.0.1", requested_port) catch unreachable;
    var server = address.listen(io, .{ .reuse_address = true }) catch |err| {
        try stderr.print("fis: cannot start web server: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer server.deinit(io);

    const port = server.socket.address.getPort();
    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/", .{port});
    defer allocator.free(url);

    try stdout.print("Fiscus web viewer: {s}\nJournal: {s}\nPress Ctrl-C to stop.\n", .{ url, journal_path });
    try stdout.flush();

    if (open_browser) {
        openBrowser(io, url) catch |err| {
            try stderr.print("fis: could not open browser: {s}\n", .{@errorName(err)});
            try stderr.flush();
        };
    }

    const context = Context{
        .allocator = allocator,
        .io = io,
        .journal_path = journal_path,
    };

    while (true) {
        const stream = server.accept(io) catch |err| {
            try stderr.print("fis: web server accept failed: {s}\n", .{@errorName(err)});
            try stderr.flush();
            continue;
        };
        serveConnection(stream, &context) catch |err| {
            try stderr.print("fis: web request failed: {s}\n", .{@errorName(err)});
            try stderr.flush();
        };
    }
}

fn serveConnection(stream: std.Io.net.Stream, context: *const Context) !void {
    defer stream.close(context.io);

    var receive_buffer: [8192]u8 = undefined;
    var send_buffer: [8192]u8 = undefined;
    var connection_reader = stream.reader(context.io, &receive_buffer);
    var connection_writer = stream.writer(context.io, &send_buffer);
    var server = std.http.Server.init(&connection_reader.interface, &connection_writer.interface);

    var request = server.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return,
        else => return err,
    };
    try serveRequest(&request, context);
}

fn serveRequest(request: *std.http.Server.Request, context: *const Context) !void {
    if (request.head.method != .GET and request.head.method != .HEAD) {
        return respond(request, "Method not allowed\n", "text/plain; charset=utf-8", .method_not_allowed);
    }

    const target = if (std.mem.findScalar(u8, request.head.target, '?')) |query_start|
        request.head.target[0..query_start]
    else
        request.head.target;

    if (std.mem.eql(u8, target, "/") or std.mem.eql(u8, target, "/index.html")) {
        return respond(request, assets.index_html, "text/html; charset=utf-8", .ok);
    }
    if (std.mem.eql(u8, target, "/app.js")) {
        return respond(request, assets.app_js, "text/javascript; charset=utf-8", .ok);
    }
    if (std.mem.eql(u8, target, "/conversion.js")) {
        return respond(request, assets.conversion_js, "text/javascript; charset=utf-8", .ok);
    }
    if (std.mem.eql(u8, target, "/styles.css")) {
        return respond(request, assets.styles_css, "text/css; charset=utf-8", .ok);
    }
    if (std.mem.eql(u8, target, "/api/journal")) {
        const payload = journalPayload(context) catch |err| {
            var message_buffer: [256]u8 = undefined;
            const message = std.fmt.bufPrint(
                &message_buffer,
                "Could not load '{s}': {s}\n",
                .{ context.journal_path, @errorName(err) },
            ) catch "Could not load journal\n";
            return respond(request, message, "text/plain; charset=utf-8", .internal_server_error);
        };
        defer context.allocator.free(payload);
        return respond(request, payload, "application/json; charset=utf-8", .ok);
    }

    return respond(request, "Not found\n", "text/plain; charset=utf-8", .not_found);
}

fn journalPayload(context: *const Context) ![]u8 {
    var application = try fiscus.application.Application.load(
        context.allocator,
        context.io,
        std.Io.Dir.cwd(),
        context.journal_path,
    );
    defer application.deinit();

    var output = std.Io.Writer.Allocating.init(context.allocator);
    defer output.deinit();

    try std.json.Stringify.value(.{
        .files = application.loaded_workspace.sources.files.items,
    }, .{}, &output.writer);

    return context.allocator.dupe(u8, output.written());
}

fn respond(
    request: *std.http.Server.Request,
    content: []const u8,
    content_type: []const u8,
    status: std.http.Status,
) !void {
    try request.respond(content, .{
        .status = status,
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "content-type", .value = content_type },
            .{ .name = "cache-control", .value = "no-store" },
            .{ .name = "x-content-type-options", .value = "nosniff" },
        },
    });
}

fn openBrowser(io: std.Io, url: []const u8) !void {
    const future = try io.concurrent(openBrowserTask, .{ io, url });
    _ = future;
}

fn openBrowserTask(io: std.Io, url: []const u8) !void {
    const executable = switch (builtin.os.tag) {
        .windows => "explorer",
        .macos => "open",
        else => "xdg-open",
    };
    var child = try std.process.spawn(io, .{
        .argv = &.{ executable, url },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    _ = try child.wait(io);
}
