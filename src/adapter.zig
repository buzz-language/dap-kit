//! Handles debugger requests by calling callbacks on a Handler implemented by the debuggee

const std = @import("std");
const builtin = @import("builtin");
const SpscQueue = @import("spsc_queue.zig").SpscQueue;
const ProtocolMessage = @import("ProtocolMessage.zig");
const Server = @import("Server.zig");

const log = std.log.scoped(.dap_adapter);

pub fn Arguments(comptime command: ProtocolMessage.CommandTag) type {
    for (@typeInfo(ProtocolMessage.RequestArguments).@"union".fields) |union_field| {
        if (std.mem.eql(u8, union_field.name, @tagName(command))) {
            return union_field.type;
        }
    }

    unreachable;
}

pub fn Response(comptime command: ProtocolMessage.CommandTag) type {
    for (@typeInfo(ProtocolMessage.ResponseBody).@"union".fields) |union_field| {
        if (std.mem.eql(u8, union_field.name, @tagName(command))) {
            return union_field.type;
        }
    }

    unreachable;
}

pub fn Adapter(comptime Handler: type) type {
    return struct {
        const Self = @This();

        handler: *Handler,
        transport: *Server.Transport,
        seq: usize = 0,

        pub fn emitEvent(self: *Self, event: ProtocolMessage.Event) void {
            self.seq += 1;
            self.transport.from.push(
                .{
                    .seq = 1,
                    .type = .event,
                    .body = .{
                        .event = event,
                    },
                },
            );
        }

        /// Pop next message on the queue and handles it
        pub fn handleRequest(self: *Self) ?ProtocolMessage.CommandTag {
            if (self.transport.to.front()) |request| {
                // Pop once we're done with it
                self.transport.to.pop();

                log.info(
                    "Received request #{} with command `{s}`",
                    .{
                        request.seq,
                        @tagName(request.body.request.command),
                    },
                );

                switch (request.body.request.arguments) {
                    inline else => |args, tag| {
                        const command = @tagName(tag);
                        const has_callback = @hasField(Handler, command) or @hasDecl(Handler, command);

                        if (!has_callback) {
                            log.warn("Missing callback to handle `{s}` requests", .{command});

                            self.transport.from.push(
                                .{
                                    .seq = self.seq,
                                    .type = .response,
                                    .body = .{
                                        .response = .{
                                            .command = tag,
                                            .request_seq = request.seq,
                                            .success = false,
                                            .body = .{
                                                .@"error" = "Unsupported request",
                                            },
                                        },
                                    },
                                },
                            );
                        } else {
                            const callback = @field(Handler, command);

                            const response = @call(
                                .auto,
                                callback,
                                .{
                                    self.handler,
                                    args,
                                },
                            );

                            self.transport.from.push(
                                .{
                                    .seq = self.seq,
                                    .type = .response,
                                    .body = .{
                                        .response = .{
                                            .command = tag,
                                            .request_seq = request.seq,
                                            .success = if (response) |_| true else |_| false,
                                            .body = if (response) |resp| @unionInit(
                                                ProtocolMessage.ResponseBody,
                                                command,
                                                resp,
                                            ) else |err| .{
                                                .@"error" = @errorName(err),
                                            },
                                        },
                                    },
                                },
                            );
                        }

                        self.seq += 1;
                    },
                }

                return request.body.request.command;
            }

            return null;
        }
    };
}
