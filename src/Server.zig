//! Debugger Adapter server
//! - runs in its own thread
//! - communicates with the debuggee using spsc queues
//! - communicates with debugger over TCP

const std = @import("std");
const builtin = @import("builtin");
const ProtocolMessage = @import("ProtocolMessage.zig");
const SpscQueue = @import("spsc_queue.zig").SpscQueue;

pub const Stream = enum { in };

/// Holds queue to send Requests and Receives response to and from the debuggee
pub const Transport = struct {
    /// Queue that will be consumed by the debuggee, should contain only requests
    /// We use a whole message rather than just the Request because the debuggee has to know about the seq number
    to: SpscQueue(ProtocolMessage),
    /// Queue that will be consumed by the DA, should contain only responses
    /// We use a whole message rather than just the Response because the debuggee has to know about the seq number
    from: SpscQueue(ProtocolMessage),
};

const Server = @This();

/// Io
io: std.Io,
/// Allocator
allocator: std.mem.Allocator,
/// Server listening for incoming connection
tcp_server: std.Io.net.Server,
/// Currently connected client
client: ?std.Io.net.Stream = null,
/// Queues to communicate with debuggee
transport: *Transport,

/// Start a new Server in its dedicated thread
/// Server will block while waiting for the client to connect and then start the debuggee program
pub fn spawn(
    io: std.Io,
    allocator: std.mem.Allocator,
    address: std.Io.net.IpAddress,
    transport: *Transport,
) std.Thread.SpawnError!std.Thread {
    return try std.Thread.spawn(
        .{},
        start,
        .{
            io,
            allocator,
            address,
            transport,
        },
    );
}

fn start(
    io: std.Io,
    allocator: std.mem.Allocator,
    address: std.Io.net.IpAddress,
    transport: *Transport,
) !void {
    var self = Server{
        .io = io,
        .allocator = allocator,
        .transport = transport,
        .tcp_server = try address.listen(
            io,
            .{
                .reuse_address = true,
            },
        ),
    };

    std.log.info(
        "Debugger awaiting connection on {f}",
        .{
            address,
        },
    );

    // FIXME: add a timeout
    while (true) {
        self.client = self.tcp_server.accept(io) catch |err| {
            switch (err) {
                error.WouldBlock => {
                    io.sleep(.fromMilliseconds(10), .awake) catch {};
                    continue;
                },
                else => return err,
            }
        };

        std.log.info(
            "Debugger accepted connection from {f}",
            .{
                self.client.?.socket.address,
            },
        );

        break;
    }

    var client_stream_buffer: [1024]u8 = undefined;

    while (true) {
        // Is there responses to send
        if (self.transport.from.front()) |response| {
            // Pop once we're finished using it
            defer self.transport.from.pop();

            // Write it as json in a buffer
            var response_buffer_writer = std.Io.Writer.Allocating.init(
                allocator,
            );
            defer response_buffer_writer.deinit();

            try std.json.Stringify.value(
                response,
                .{
                    .whitespace = if (builtin.mode == .Debug)
                        .indent_2
                    else
                        .minified,
                    .emit_null_optional_fields = false,
                },
                &response_buffer_writer.writer,
            );

            // Now write it on the client's stream
            var buffer: [1024]u8 = undefined;
            var stream_writer = self.client.?.writer(io, buffer[0..]);
            var writer = &stream_writer.interface;

            try writer.print(
                "{f}{s}",
                .{
                    BaseProtocolHeader{
                        .content_length = response_buffer_writer.written().len,
                    },
                    response_buffer_writer.written(),
                },
            );

            std.log.debug(
                "Responding with:\n{s}",
                .{
                    response_buffer_writer.written(),
                },
            );

            switch (response.type) {
                .response => std.log.info(
                    "Responsed to message #{}, success {}",
                    .{
                        response.body.response.request_seq,
                        response.body.response.success,
                    },
                ),
                .event => std.log.info(
                    "Emitted event {s}",
                    .{
                        @tagName(response.body.event.event),
                    },
                ),
                else => {},
            }

            // If successful response to `disconnect` request, stop the server
            if (response.type == .response and response.body.response.command == .disconnect) {
                std.log.info("Client disconnected, server stopped", .{});
                return;
            }
        }

        // Is there something on the client stream
        var client_stream_reader = self.client.?.reader(io, client_stream_buffer[0..]);
        const reader = &client_stream_reader.interface;

        const raw_message = readJsonMessage(reader, allocator) catch |err| {
            switch (err) {
                error.ReadFailed => {
                    // Nothing to read?
                    continue;
                },
                else => return err,
            }
        };

        std.log.debug("Received raw message: `{s}`", .{raw_message});

        // FIXME: can't free it then, it's in the queue
        // defer allocator.free(raw_message);

        const json_message = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            raw_message,
            .{},
        );
        // defer json_message.deinit();

        const message = try std.json.parseFromValue(
            ProtocolMessage,
            allocator,
            json_message.value,
            .{
                .ignore_unknown_fields = true,
            },
        );

        self.transport.to.push(message.value);

        // Don't butcher the CPU
        self.io.sleep(.fromMilliseconds(10), .awake) catch {};
    }
}

pub fn readJsonMessage(
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
) (std.Io.Reader.Error || std.mem.Allocator.Error || BaseProtocolHeader.ParseError)![]u8 {
    const header: BaseProtocolHeader = try .parse(reader);
    return try reader.readAlloc(allocator, header.content_length);
}

pub fn deinit(self: *Server) void {
    if (self.client) |*client| client.close(self.io);
    self.tcp_server.deinit(self.io);
    self.transport.to.deinit(self.allocator);
    self.transport.from.deinit(self.allocator);
}

/// Copied from lsp-kit
pub const BaseProtocolHeader = struct {
    content_length: usize,

    pub const minimum_reader_buffer_size: usize = 128;

    pub const ParseError = error{
        EndOfStream,
        /// The message is longer than `std.math.maxInt(usize)`.
        OversizedMessage,
        /// The header field is longer than buffer size of the `std.Io.Reader` which is at least `minimum_reader_buffer_size`.
        OversizedHeaderField,
        /// The header is missing the mandatory `Content-Length` field.
        MissingContentLength,
        /// The header field `Content-Length` has been specified multiple times.
        DuplicateContentLength,
        /// The header field value of `Content-Length` is not a valid unsigned integer.
        InvalidContentLength,
        /// The header is ill-formed.
        InvalidHeaderField,
    };

    /// The maximum parsable header field length is controlled by `reader.buffer.len`.
    /// Asserts that `reader.buffer.len >= minimum_reader_buffer_size`.
    pub fn parse(reader: *std.Io.Reader) (std.Io.Reader.Error || ParseError)!BaseProtocolHeader {
        std.debug.assert(@import("builtin").is_test or reader.buffer.len >= minimum_reader_buffer_size);
        var content_length: ?usize = null;

        while (true) {
            var header = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
                error.StreamTooLong => return error.OversizedHeaderField,
                else => |e| return e,
            };
            if (!std.mem.endsWith(u8, header, "\r\n")) return error.InvalidHeaderField;
            header.len -= "\r\n".len;

            if (header.len == 0) break;

            const colon_index = std.mem.indexOf(u8, header, ": ") orelse return error.InvalidHeaderField;

            const header_name = header[0..colon_index];
            const header_value = header[colon_index + 2 ..];

            if (!std.ascii.eqlIgnoreCase(header_name, "content-length")) continue;
            if (content_length != null) return error.DuplicateContentLength;

            content_length = std.fmt.parseUnsigned(usize, header_value, 10) catch |err| switch (err) {
                error.Overflow => return error.OversizedMessage,
                error.InvalidCharacter => return error.InvalidContentLength,
            };
        }

        return .{
            .content_length = content_length orelse return error.MissingContentLength,
        };
    }

    test parse {
        try expectParseError("", error.EndOfStream);
        try expectParseError("\n", error.InvalidHeaderField);
        try expectParseError("\n\r", error.InvalidHeaderField);
        try expectParseError("\r", error.EndOfStream);
        try expectParseError("\r\n", error.MissingContentLength);
        try expectParseError("\r\n\r\n", error.MissingContentLength);

        try expectParseError("content-length: 32\r\n", error.EndOfStream);
        try expectParseError("content-length: \r\n\r\n", error.InvalidContentLength);
        try expectParseError("content-length 32\r\n\r\n", error.InvalidHeaderField);
        try expectParseError("content-length:32\r\n\r\n", error.InvalidHeaderField);
        try expectParseError("contentLength: 32\r\n\r\n", error.MissingContentLength);
        try expectParseError("content-length: 32\r\ncontent-length: 32\r\n\r\n", error.DuplicateContentLength);
        try expectParseError("content-length: abababababab\r\n\r\n", error.InvalidContentLength);
        try expectParseError("content-length: : 32\r\n\r\n", error.InvalidContentLength);
        try expectParseError("content-length: 9999999999999999999999999999999999\r\n\r\n", error.OversizedMessage);

        try expectParse("content-length: 32\r\n\r\n", .{ .content_length = 32 });
        try expectParse("Content-Length: 32\r\n\r\n", .{ .content_length = 32 });

        try expectParse("content-type: whatever\r\nContent-Length: 666\r\n\r\n", .{ .content_length = 666 });
        try expectParse("Content-Type: impostor\r\ncontent-length: 42\r\n\r\n", .{ .content_length = 42 });
    }

    test "parse with oversized header field" {
        const stream = struct {
            fn stream(_: *std.Io.Reader, _: *std.Io.Writer, _: std.Io.Limit) std.Io.Reader.StreamError!usize {
                return error.EndOfStream;
            }
        }.stream;

        var buffer: [128]u8 = @splat(0);
        var reader: std.Io.Reader = .{
            .vtable = &.{
                .stream = &stream,
                .discard = undefined,
            },
            .buffer = &buffer,
            .end = buffer.len,
            .seek = 0,
        };
        try std.testing.expectError(error.OversizedHeaderField, parse(&reader));
    }

    pub fn format(header: BaseProtocolHeader, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("Content-Length: {d}\r\n\r\n", .{header.content_length});
    }

    test format {
        try std.testing.expectFmt("Content-Length: 0\r\n\r\n", "{f}", .{BaseProtocolHeader{ .content_length = 0 }});
        try std.testing.expectFmt("Content-Length: 42\r\n\r\n", "{f}", .{BaseProtocolHeader{ .content_length = 42 }});
        try std.testing.expectFmt("Content-Length: 4294967295\r\n\r\n", "{f}", .{BaseProtocolHeader{ .content_length = std.math.maxInt(u32) }});
        if (@sizeOf(usize) == @sizeOf(u64)) {
            try std.testing.expectFmt("Content-Length: 18446744073709551615\r\n\r\n", "{f}", .{BaseProtocolHeader{ .content_length = std.math.maxInt(usize) }});
        }
    }

    fn expectParse(input: []const u8, expected_header: BaseProtocolHeader) !void {
        var reader: std.Io.Reader = .fixed(input);
        const actual_header = try parse(&reader);
        try std.testing.expectEqual(expected_header.content_length, actual_header.content_length);
    }

    fn expectParseError(input: []const u8, expected_error: ParseError) !void {
        var buffer: [128]u8 = undefined;
        var reader: std.Io.Reader = .fixed(&buffer);
        reader.end = input.len;
        @memcpy(buffer[0..input.len], input);

        try std.testing.expectError(expected_error, parse(&reader));
    }
};
