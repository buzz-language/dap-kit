//! See https://microsoft.github.io/debug-adapter-protocol/debugAdapterProtocol.json
//! See https://microsoft.github.io/debug-adapter-protocol/specification

const std = @import("std");

const ProtocolMessage = @This();

/// Sequence number of the message (also known as message ID). The `seq` for the first message sent by a client or debug adapter is
/// 1, and for each subsequent message is 1 greater than the previous message sent by that actor. `seq` can be used to order requests,
/// responses, and events, and to associate requests with their corresponding responses. For protocol messages of type `request` the
/// sequence number can be used to cancel the request.
seq: u64,
/// Message type.
type: MessageTag,
/// Message body
body: Body,

pub fn jsonParseFromValue(
    allocator: std.mem.Allocator,
    source: std.json.Value,
    options: std.json.ParseOptions,
) std.json.ParseFromValueError!@This() {
    if (source != .object) {
        return error.UnexpectedToken;
    }

    const message_type_name = (source.object.get("type") orelse return error.MissingField).string;

    const message_type = std.meta.stringToEnum(
        MessageTag,
        message_type_name,
    ) orelse return error.InvalidEnumTag;

    return .{
        .seq = @intCast((source.object.get("seq") orelse return error.MissingField).integer),
        .type = message_type,
        .body = try std.json.parseFromValueLeaky(
            Body,
            allocator,
            source,
            options,
        ),
    };
}

pub fn jsonStringify(
    self: *const @This(),
    out_stream: anytype,
) @TypeOf(out_stream.*).Error!void {
    try out_stream.beginObject();

    try out_stream.objectField("seq");
    try out_stream.write(self.seq);

    try out_stream.objectField("type");
    try out_stream.write(@tagName(self.type));

    switch (self.body) {
        inline else => |body| {
            const body_type = @TypeOf(body);

            inline for (std.meta.fields(body_type)) |field| {
                try out_stream.objectField(field.name);
                try out_stream.write(@field(body, field.name));
            }
        },
    }

    try out_stream.endObject();
}

pub const MessageTag = enum {
    request,
    response,
    event,
};

pub const Body = union(MessageTag) {
    request: Request,
    response: Response,
    event: Event,

    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) std.json.ParseFromValueError!@This() {
        if (source != .object) {
            return error.UnexpectedToken;
        }

        const tag_name = source.object.get("type") orelse return error.MissingField;
        if (tag_name != .string) return error.UnexpectedToken;

        inline for (std.meta.fields(@This())) |field| {
            if (std.mem.eql(u8, tag_name.string, field.name)) {
                return @unionInit(
                    @This(),
                    field.name,
                    try std.json.parseFromValueLeaky(
                        field.type,
                        allocator,
                        source,
                        options,
                    ),
                );
            }
        }

        return error.UnexpectedToken;
    }
};

/// A client or debug adapter initiated request
pub const Request = struct {
    /// The command to execute
    command: CommandTag,
    /// Object containing arguments for the command
    arguments: RequestArguments,

    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) std.json.ParseFromValueError!@This() {
        if (source != .object) {
            return error.UnexpectedToken;
        }

        const command_name = (source.object.get("command") orelse return error.MissingField).string;

        const command = std.meta.stringToEnum(
            CommandTag,
            command_name,
        ) orelse return error.InvalidEnumTag;

        return .{
            .command = command,
            .arguments = try std.json.parseFromValueLeaky(
                RequestArguments,
                allocator,
                source,
                options,
            ),
        };
    }
};

pub const CommandTag = enum {
    /// The `cancel` request is used by the client in two situations:
    /// - to indicate that it is no longer interested in the result produced by a specific request issued earlier
    /// - to cancel a progress sequence.
    /// Clients should only call this request if the corresponding capability `supportsCancelRequest` is true.
    /// This request has a hint characteristic: a debug adapter can only be expected to make a 'best effort' in honoring this
    /// request but there are no guarantees.
    /// The `cancel` request may return an error if it could not cancel an operation but a client should refrain from presenting
    /// this error to end users.
    /// The request that got cancelled still needs to send a response back. This can either be a normal result (`success` attribute
    /// true) or an error response (`success` attribute false and the `message` set to `cancelled`).
    /// Returning partial results from a cancelled request is possible but please note that a client has no generic way for
    /// detecting that a response is partial or not.
    /// The progress that got cancelled still needs to send a `progressEnd` event back.
    /// A client should not assume that progress just got cancelled after sending the `cancel` request.
    cancel,
    /// The `initialize` request is sent as the first request from the client to the debug adapter in order to configure it with
    /// client capabilities and to retrieve capabilities from the debug adapter.
    /// Until the debug adapter has responded with an `initialize` response, the client must not send any additional requests or
    /// events to the debug adapter.
    /// In addition the debug adapter is not allowed to send any requests or events to the client until it has responded with an
    /// `initialize` response.
    /// The `initialize` request may only be sent once.
    initialize,
    /// This request indicates that the client has finished initialization of the debug adapter.
    /// So it is the last request in the sequence of configuration requests (which was started by the `initialized` event).
    /// Clients should only call this request if the corresponding capability `supportsConfigurationDoneRequest` is true.
    configurationDone,
    /// This launch request is sent from the client to the debug adapter to start the debuggee with or without debugging (if
    /// `noDebug` is true).
    /// Since launching is debugger/runtime specific, the arguments for this request are not part of this specification.
    launch,
    /// The `attach` request is sent from the client to the debug adapter to attach to a debuggee that is already running.
    /// Since attaching is debugger/runtime specific, the arguments for this request are not part of this specification.
    attach,
    /// Restarts a debug session. Clients should only call this request if the corresponding capability `supportsRestartRequest`
    /// is true.
    /// If the capability is missing or has the value false, a typical client emulates `restart` by terminating the debug adapter
    /// first and then launching it anew.
    restart,
    /// The `disconnect` request asks the debug adapter to disconnect from the debuggee (thus ending the debug session) and then to
    /// shut down itself (the debug adapter).
    /// In addition, the debug adapter must terminate the debuggee if it was started with the `launch` request. If an `attach`
    /// request was used to connect to the debuggee, then the debug adapter must not terminate the debuggee.
    /// This implicit behavior of when to terminate the debuggee can be overridden with the `terminateDebuggee` argument (which is
    /// only supported by a debug adapter if the corresponding capability `supportTerminateDebuggee` is true).
    disconnect,
    /// The `terminate` request is sent from the client to the debug adapter in order to shut down the debuggee gracefully. Clients
    /// should only call this request if the capability `supportsTerminateRequest` is true.
    /// Typically a debug adapter implements `terminate` by sending a software signal which the debuggee intercepts in order to
    /// clean things up properly before terminating itself.
    /// Please note that this request does not directly affect the state of the debug session: if the debuggee decides to veto the
    /// graceful shutdown for any reason by not terminating itself, then the debug session just continues.
    /// Clients can surface the `terminate` request as an explicit command or they can integrate it into a two stage Stop command
    /// that first sends `terminate` to request a graceful shutdown, and if that fails uses `disconnect` for a forceful shutdown.
    terminate,
    /// The `breakpointLocations` request returns all possible locations for source breakpoints in a given range.
    /// Clients should only call this request if the corresponding capability `supportsBreakpointLocationsRequest` is true.
    breakpointLocations,
    /// Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
    /// To clear all breakpoint for a source, specify an empty array.
    /// When a breakpoint is hit, a `stopped` event (with reason `breakpoint`) is generated.
    setBreakpoints,
    /// Replaces all existing function breakpoints with new function breakpoints.
    /// To clear all function breakpoints, specify an empty array.
    /// When a function breakpoint is hit, a `stopped` event (with reason `function breakpoint`) is generated.
    /// Clients should only call this request if the corresponding capability `supportsFunctionBreakpoints` is true.
    setFunctionBreakpoints,
    /// The request configures the debugger's response to thrown exceptions. Each of the `filters`, `filterOptions`, and
    /// `exceptionOptions` in the request are independent configurations to a debug adapter indicating a kind of exception to catch.
    /// An exception thrown in a program should result in a `stopped` event from the debug adapter (with reason `exception`) if
    /// any of the configured filters match.
    /// Clients should only call this request if the corresponding capability `exceptionBreakpointFilters` returns one or more filters.
    setExceptionBreakpoints,
    /// Obtains information on a possible data breakpoint that could be set on an expression or variable.
    /// Clients should only call this request if the corresponding capability `supportsDataBreakpoints` is true.
    dataBreakpointInfo,
    /// Replaces all existing data breakpoints with new data breakpoints.
    /// To clear all data breakpoints, specify an empty array.
    /// When a data breakpoint is hit, a `stopped` event (with reason `data breakpoint`) is generated.
    /// Clients should only call this request if the corresponding capability `supportsDataBreakpoints` is true.
    setDataBreakpoints,
    /// Replaces all existing instruction breakpoints. Typically, instruction breakpoints would be set from a disassembly window.
    /// To clear all instruction breakpoints, specify an empty array.
    /// When an instruction breakpoint is hit, a `stopped` event (with reason `instruction breakpoint`) is generated.
    /// Clients should only call this request if the corresponding capability `supportsInstructionBreakpoints` is true.
    setInstructionBreakpoints,
    /// The request resumes execution of all threads. If the debug adapter supports single thread execution (see capability
    /// `supportsSingleThreadExecutionRequests`), setting the `singleThread` argument to true resumes only the specified thread. If
    /// not all threads were resumed, the `allThreadsContinued` attribute of the response should be set to false.
    @"continue",
    /// The request executes one step (in the given granularity) for the specified thread and allows all other threads to run freely
    /// by resuming them.
    /// If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting the
    /// `singleThread` argument to true prevents other suspended threads from resuming.
    /// The debug adapter first sends the response and then a `stopped` event (with reason `step`) after the step has completed.
    next,
    /// The request resumes the given thread to step into a function/method and allows all other threads to run freely by resuming them.
    /// If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting
    /// the `singleThread` argument to true prevents other suspended threads from resuming.
    /// If the request cannot step into a target, `stepIn` behaves like the `next` request.
    /// The debug adapter first sends the response and then a `stopped` event (with reason `step`) after the step has completed.    /// If there are multiple function/method calls (or other targets) on the source line,
    /// the argument `targetId` can be used to control into which target the `stepIn` should occur.
    /// The list of possible targets for a given source line can be retrieved via the `stepInTargets` request.
    stepIn,
    /// The request resumes the given thread to step out (return) from a function/method and allows all other threads to run
    /// freely by resuming them.
    /// If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting
    /// the `singleThread` argument to true prevents other suspended threads from resuming.
    /// The debug adapter first sends the response and then a `stopped` event (with reason `step`) after the step has completed.
    stepOut,
    /// The request executes one backward step (in the given granularity) for the specified thread and allows all other threads
    /// to run backward freely by resuming them.
    /// If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting
    /// the `singleThread` argument to true prevents other suspended threads from resuming.
    /// The debug adapter first sends the response and then a `stopped` event (with reason `step`) after the step has completed.
    /// Clients should only call this request if the corresponding capability `supportsStepBack` is true.
    stepBack,
    /// The request resumes backward execution of all threads. If the debug adapter supports single thread execution (see
    /// capability `supportsSingleThreadExecutionRequests`), setting the `singleThread` argument to true resumes only the
    /// specified thread. If not all threads were resumed, the `allThreadsContinued` attribute of the response should be set to false.
    /// Clients should only call this request if the corresponding capability `supportsStepBack` is true.
    reverseContinue,
    /// The request restarts execution of the specified stack frame.
    /// The debug adapter first sends the response and then a `stopped` event (with reason `restart`) after the restart has completed.
    /// Clients should only call this request if the corresponding capability `supportsRestartFrame` is true.
    restartFrame,
    /// The request sets the location where the debuggee will continue to run.
    /// This makes it possible to skip the execution of code or to execute code again.
    /// The code between the current location and the goto target is not executed but skipped.
    /// The debug adapter first sends the response and then a `stopped` event with reason `goto`.
    /// Clients should only call this request if the corresponding capability `supportsGotoTargetsRequest` is true (because
    /// only then goto targets exist that can be passed as arguments).
    goto,
    /// The request suspends the debuggee.
    /// The debug adapter first sends the response and then a `stopped` event (with reason `pause`) after the thread has been
    /// paused successfully.
    pause,
    /// The request returns a stacktrace from the current execution state of a given thread.
    /// A client can request all stack frames by omitting the startFrame and levels arguments. For performance-conscious clients
    /// and if the corresponding capability `supportsDelayedStackTraceLoading` is true, stack frames can be retrieved in a
    /// piecemeal way with the `startFrame` and `levels` arguments. The response of the `stackTrace` request may contain a    /// `totalFrames` property that hints at the total number of frames in the stack. If a client needs this total number upfront,
    /// it can issue a request for a single (first) frame and depending on the value of `totalFrames` decide how to proceed. In
    /// any case a client should be prepared to receive fewer frames than requested, which is an indication that the end of the
    /// stack has been reached.
    stackTrace,
    /// The request returns the variable scopes for a given stack frame ID.
    scopes,
    /// The request retrieves the source code for a given source reference.
    source,
    /// Retrieves all child variables for the given variable reference.
    /// A filter can be used to limit the fetched children to either named or indexed children.
    variables,
    /// Set the variable with the given name in the variable container to a new value. Clients should only call this request if
    /// the corresponding capability `supportsSetVariable` is true.
    /// If a debug adapter implements both `setVariable` and
    /// `setExpression`, a client will only use `setExpression` if the variable has an `evaluateName` property.
    setVariable,
    /// The request retrieves a list of all threads.
    threads,
    /// The request terminates the threads with the given ids.
    /// Clients should only call this request if the corresponding capability `supportsTerminateThreadsRequest` is true.
    terminateThreads,
    /// Modules can be retrieved from the debug adapter with this request which can either return all modules or a range of
    /// modules to support paging.
    /// Clients should only call this request if the corresponding capability `supportsModulesRequest` is true.
    modules,
    /// Retrieves the set of all sources currently loaded by the debugged process.
    /// Clients should only call this request if the corresponding capability `supportsLoadedSourcesRequest` is true.
    loadedSources,
    /// Evaluates the given expression in the context of a stack frame.
    /// The expression has access to any variables and arguments that are in scope.
    evaluate,
    /// Evaluates the given `value` expression and assigns it to the `expression` which must be a modifiable l-value.
    /// The expressions have access to any variables and arguments that are in scope of the specified frame.
    /// Clients should only call this request if the corresponding capability `supportsSetExpression` is true.
    /// If a debug adapter implements both `setExpression` and `setVariable`, a client uses `setExpression` if the variable
    /// has an `evaluateName` property.
    setExpression,
    /// This request retrieves the possible step-in targets for the specified stack frame.
    /// These targets can be used in the `stepIn` request.
    /// Clients should only call this request if the corresponding capability `supportsStepInTargetsRequest` is true.
    stepInTargets,
    /// This request retrieves the possible goto targets for the specified source location.
    /// These targets can be used in the `goto` request.
    /// Clients should only call this request if the corresponding capability `supportsGotoTargetsRequest` is true.
    gotoTargets,
    /// Returns a list of possible completions for a given caret position and text.
    /// Clients should only call this request if the corresponding capability `supportsCompletionsRequest` is true.
    completions,
    /// Retrieves the details of the exception that caused this event to be raised.
    /// Clients should only call this request if the corresponding capability `supportsExceptionInfoRequest` is true.
    exceptionInfo,
    /// Reads bytes from memory at the provided location.
    /// Clients should only call this request if the corresponding capability `supportsReadMemoryRequest` is true.
    readMemory,
    /// Writes bytes to memory at the provided location.
    /// Clients should only call this request if the corresponding capability `supportsWriteMemoryRequest` is true.
    writeMemory,
    /// Disassembles code stored at the provided location.
    /// Clients should only call this request if the corresponding capability `supportsDisassembleRequest` is true.
    disassemble,
    /// Not part of the protocol, used to send error details
    @"error",
};

pub const RequestArguments = union(CommandTag) {
    cancel: CancelArguments,
    initialize: InitializeArguments,
    configurationDone: void,
    launch: LaunchArguments,
    attach: AttachArguments,
    restart: RestartArguments,
    disconnect: DisconnectArguments,
    terminate: TerminateArguments,
    breakpointLocations: BreakpointLocationsArguments,
    setBreakpoints: SetBreakpointsArguments,
    setFunctionBreakpoints: SetFunctionBreakpointsArguments,
    setExceptionBreakpoints: SetExceptionBreakpointsArguments,
    dataBreakpointInfo: DataBreakpointInfoArguments,
    setDataBreakpoints: SetDataBreakpointsArguments,
    setInstructionBreakpoints: SetInstructionBreakpointsArguments,
    @"continue": ContinueArguments,
    next: NextArguments,
    stepIn: StepInArguments,
    stepOut: StepOutArguments,
    stepBack: StepBackArguments,
    reverseContinue: ReverseContinueArguments,
    restartFrame: RestartFrameArguments,
    goto: GotoArguments,
    pause: PauseArguments,
    stackTrace: StackTraceArguments,
    scopes: ScopesArguments,
    source: SourceArguments,
    variables: VariablesArguments,
    setVariable: SetVariableArguments,
    threads: void,
    terminateThreads: TerminateThreadsArguments,
    modules: ModulesArguments,
    loadedSources: void,
    evaluate: EvaluateArguments,
    setExpression: SetExpressionArguments,
    stepInTargets: StepInTargetsArguments,
    gotoTargets: GotoTargetsArguments,
    completions: CompletionsArguments,
    exceptionInfo: ExceptionInfoArguments,
    readMemory: ReadMemoryArguments,
    writeMemory: WriteMemoryArguments,
    disassemble: DisassembleArguments,
    @"error": void,

    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) std.json.ParseFromValueError!@This() {
        if (source != .object) {
            return error.UnexpectedToken;
        }

        const tag_name = source.object.get("command") orelse return error.MissingField;
        if (tag_name != .string) return error.UnexpectedToken;

        inline for (std.meta.fields(@This())) |field| {
            if (std.mem.eql(u8, tag_name.string, field.name)) {
                return @unionInit(
                    @This(),
                    field.name,
                    if (field.type == void)
                        void{}
                    else
                        try std.json.parseFromValueLeaky(
                            field.type,
                            allocator,
                            source.object.get("arguments") orelse return error.MissingField,
                            options,
                        ),
                );
            }
        }

        return error.UnexpectedToken;
    }
};

/// Response to `disassemble` request.
pub const DisassembleResponseBody = struct {
    /// The list of disassembled instructions.
    instructions: []const DisassembledInstruction,
};

/// Represents a single disassembled instruction.
pub const DisassembledInstruction = struct {
    /// The address of the instruction. Treated as a hex value if prefixed with `0x`, or as a decimal value otherwise.
    address: []const u8,
    /// Raw bytes representing the instruction and its operands, in an implementation-defined format.
    instructionBytes: ?[]const u8 = null,
    /// Text representing the instruction and its operands, in an implementation-defined format.
    instruction: []const u8,
    /// Name of the symbol that corresponds with the location of this instruction, if any.
    symbol: ?[]const u8 = null,
    /// Source location that corresponds to this instruction, if any.
    /// Should always be set (if available) on the first instruction returned,
    /// but can be omitted afterwards if this instruction maps to the same source file as the previous instruction.
    location: ?Source = null,
    /// The line within the source location that corresponds to this instruction, if any.
    line: ?u64 = null,
    /// The column within the line that corresponds to this instruction, if any.
    column: ?u64 = null,
    /// The end line of the range that corresponds to this instruction, if any.
    endLine: ?u64 = null,
    /// The end column of the range that corresponds to this instruction, if any.
    endColumn: ?u64 = null,
    /// A hint for how to present the instruction in the UI.
    /// A value of `invalid` may be used to indicate this instruction is 'filler' and cannot be reached by the program.
    /// For example, unreadable memory addresses may be presented is 'invalid.
    presentationHint: ?DisassembledInstructionPresentationHint = null,
};

pub const DisassembledInstructionPresentationHint = enum {
    normal,
    invalid,
};

/// Response to `writeMemory` request.
pub const WriteMemoryResponseBody = struct {
    /// Property that should be returned when `allowPartial` is true to indicate the offset of the first byte of data
    /// successfully written. Can be negative.
    offset: u64,
    /// Property that should be returned when `allowPartial` is true to indicate the number of bytes starting from address
    /// that were successfully written.
    bytesWritten: u64,
};

/// Response to `readMemory` request.
pub const ReadMemoryResponseBody = struct {
    /// The address of the first byte of data returned.
    /// Treated as a hex value if prefixed with `0x`, or as a decimal value otherwise.
    address: []const u8,
    /// The number of unreadable bytes encountered after the last successfully read byte.
    /// This can be used to determine the number of bytes that should be skipped before a subsequent `readMemory` request succeeds.
    unreadableBytes: ?u64 = null,
    /// The bytes read from memory, encoded using base64. If the decoded length of `data` is less than the requested `count` in the
    /// original `readMemory` request, and `unreadableBytes` is zero or omitted, then the client should assume it's reached the end
    /// of readable memory.
    data: ?[]const u8,
};

/// Response to `exceptionInfo` request.
pub const ExceptionInfoResponseBody = struct {
    /// ID of the exception that was thrown.
    exceptionId: []const u8,
    /// Descriptive text for the exception.
    description: ?[]const u8 = null,
    /// Mode that caused the exception notification to be raised.
    breakMode: ExceptionBreakMode,
    /// Detailed information about the exception.
    details: ?ExceptionDetails = null,
};

/// Detailed information about an exception that has occurred.
pub const ExceptionDetails = struct {
    /// Message contained in the exception.
    message: []const u8,
    /// Short type name of the exception object.
    typeName: []const u8,
    /// Fully-qualified type name of the exception object.
    fullTypeName: []const u8,
    /// An expression that can be evaluated in the current scope to obtain the exception object.
    evaluateName: []const u8,
    /// Stack trace at the time the exception was thrown.
    stackTrace: []const u8,
    /// Details of the exception contained by this exception, if any.
    innerException: []const ExceptionDetails,
};

/// Response to `completions` request.
pub const CompletionsResponseBody = struct {
    /// Possible completions
    targets: []const CompletionItem,
};

/// `CompletionItems` are the suggestions returned from the `completions` request.
pub const CompletionItem = struct {
    /// The label of this completion item. By default this is also the text that is inserted when selecting this completion.
    label: []const u8,
    /// If text is returned and not an empty string, then it is inserted instead of the label.
    text: ?[]const u8 = null,
    /// A string that should be used when comparing this item with other items. If not returned or an empty string, the `label`
    /// is used instead.
    sortText: ?[]const u8 = null,
    /// A human-readable string with additional information about this item, like type or symbol information.
    details: ?[]const u8 = null,
    /// The item's type. Typically the client uses this information to render the item in the UI with an icon.
    type: ?CompletionItemType = null,
    /// Start position (within the `text` attribute of the `completions` request) where the completion text is added. The position
    /// is measured in UTF-16 code units and the client capability `columnsStartAt1` determines whether it is 0- or 1-based. If
    /// the start position is omitted the text is added at the location specified by the `column` attribute of the `completions`
    /// request.
    start: ?u64 = null,
    /// Length determines how many characters are overwritten by the completion text and it is measured in UTF-16 code units. If
    /// missing the value 0 is assumed which results in the completion text being inserted.
    length: ?u64 = null,
    /// Determines the start of the new selection after the text has been inserted (or replaced). `selectionStart` is measured in
    /// UTF-16 code units and must be in the range 0 and length of the completion text. If omitted the selection starts at the
    /// end of the completion text.
    selectionStart: ?u64 = null,
    /// Determines the length of the new selection after the text has been inserted (or replaced) and it is measured in UTF-16
    /// code units. The selection can not extend beyond the bounds of the completion text. If omitted the length is assumed to be 0.
    selectionLength: ?u64 = null,
};

/// Some predefined types for the CompletionItem. Please note that not all clients have specific icons for all of them.
pub const CompletionItemType = enum {
    method,
    function,
    constructor,
    field,
    variable,
    class,
    interface,
    module,
    property,
    unit,
    value,
    @"enum",
    keyword,
    snippet,
    text,
    color,
    file,
    reference,
    customcolor,
};

/// Response to `gotoTargets` request.
pub const GotoTargetsResponseBody = struct {
    /// The possible goto targets of the specified location.
    targets: []const GotoTarget,
};

/// A `GotoTarget` describes a code location that can be used as a target in the `goto` request.
/// The possible goto targets can be determined via the `gotoTargets` request.
pub const GotoTarget = struct {
    /// Unique identifier for a goto target. This is used in the `goto` request.
    id: u64,
    /// The name of the goto target (shown in the UI).
    label: []const u8,
    /// The line of the goto target.
    line: u64,
    /// The column of the goto target.
    column: ?u64 = null,
    /// The end line of the range covered by the goto target.
    endLine: ?u64 = null,
    /// The end column of the range covered by the goto target.
    endColumn: ?u64 = null,
    /// A memory reference for the instruction pointer value represented by this target.
    instructionPointerReference: ?[]const u8,
};

/// Response to `stepInTargets` request.
pub const StepInTargetsResponseBody = struct {
    /// The possible step-in targets of the specified source location.
    targets: []const StepInTarget,
};

/// A `StepInTarget` can be used in the `stepIn` request and determines into which single target the `stepIn` request should step.
pub const StepInTarget = struct {
    /// Unique identifier for a step-in target.
    id: u64,
    /// The name of the step-in target (shown in the UI).
    label: []const u8,
    /// The line of the step-in target.
    line: ?u64 = null,
    /// Start position of the range covered by the step in target. It is measured in UTF-16 code units and the client capability
    /// `columnsStartAt1` determines whether it is 0- or 1-based.
    column: ?u64 = null,
    /// The end line of the range covered by the step-in target.
    endLine: ?u64 = null,
    /// End position of the range covered by the step in target. It is measured in UTF-16 code units and the client capability
    /// `columnsStartAt1` determines whether it is 0- or 1-based.
    endColumn: ?u64 = null,
};

/// Response to `setExpression` request.
pub const SetExpressionBody = struct {
    /// The new value of the expression.
    value: []const u8,
    /// The type of the value.
    /// This attribute should only be returned by a debug adapter if the corresponding capability `supportsVariableType` is true.
    type: ?[]const u8 = null,
    /// Properties of a value that can be used to determine how to render the result in the UI.
    presentationHint: ?VariablePresentationHint = null,
    /// If `variablesReference` is > 0, the evaluate result is structured and its children can be retrieved by passing
    /// `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object
    /// References' in the Overview section for details.
    variablesReference: ?u64 = null,
    /// The number of named child variables.
    /// The client can use this information to present the variables in a paged UI and fetch them in chunks.
    /// The value should be less than or equal to 2147483647 (2^31-1).
    namedVariables: ?u64 = null,
    /// The number of indexed child variables.
    /// The client can use this information to present the variables in a paged UI and fetch them in chunks.
    /// The value should be less than or equal to 2147483647 (2^31-1).
    indexedVariables: ?u64 = null,
    /// A memory reference to a location appropriate for this result.
    /// For pointer type eval results, this is generally a reference to the memory address contained in the pointer.
    /// This attribute may be returned by a debug adapter if corresponding capability `supportsMemoryReferences` is true.
    memoryReference: ?[]const u8 = null,
    /// A reference that allows the client to request the location where the new value is declared. For example, if the new
    /// value is function pointer, the adapter may be able to look up the function's location. This should be present only if
    /// the adapter is likely to be able to resolve the location.
    /// This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview
    /// section for details.
    valueLocationReference: ?u64 = null,
};

/// Response to `evaluate` request.
pub const EvaluateResponseBody = struct {
    /// The result of the evaluate request.
    result: []const u8,
    /// The type of the evaluate result.
    /// This attribute should only be returned by a debug adapter if the corresponding capability `supportsVariableType` is true.
    type: ?[]const u8 = null,
    /// Properties of an evaluate result that can be used to determine how to render the result in the UI.
    presentationHint: ?VariablePresentationHint = null,
    /// If `variablesReference` is > 0, the evaluate result is structured and its children can be retrieved by passing
    /// `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object
    /// References' in the Overview section for details.
    variablesReference: u64,
    /// The number of named child variables.
    /// The client can use this information to present the variables in a paged UI and fetch them in chunks.
    /// The value should be less than or equal to 2147483647 (2^31-1).
    namedVariables: ?u64 = null,
    /// The number of indexed child variables.
    /// The client can use this information to present the variables in a paged UI and fetch them in chunks.
    /// The value should be less than or equal to 2147483647 (2^31-1).
    indexedVariables: ?u64 = null,
    /// A memory reference to a location appropriate for this result.
    /// For pointer type eval results, this is generally a reference to the memory address contained in the pointer.
    /// This attribute may be returned by a debug adapter if corresponding capability `supportsMemoryReferences` is true.
    memoryReference: ?[]const u8 = null,
    /// A reference that allows the client to request the location where the returned value is declared. For example, if a
    /// function pointer is returned, the adapter may be able to look up the function's location. This should be present
    /// only if the adapter is likely to be able to resolve the location.
    /// This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the
    /// Overview section for details.
    valueLocationReference: ?u64 = null,
};

/// Response to `loadedSources` request.
pub const LoadedSourcesResponseBody = struct {
    /// Set of loaded sources.
    sources: []const Source,
};

/// Response to `modules` request.
pub const ModulesResponseBody = struct {
    /// All modules or range of modules.
    modules: []const Module,
    /// The total number of modules available.
    totalModules: ?u64 = null,
};

/// Response to `threads` request.
pub const ThreadsResponseBody = struct {
    /// All threads
    threads: []const Thread,
};

pub const Thread = struct {
    /// Unique identifier for the thread.
    id: u64,
    /// The name of the thread.
    name: []const u8,
};

/// Response to `setVariable` request.
pub const SetVariableResponseBody = struct {
    /// The new value of the variable.
    value: []const u8,
    /// The type of the new value. Typically shown in the UI when hovering over the value.
    type: ?[]const u8 = null,
    /// If `variablesReference` is > 0, the new value is structured and its children can be retrieved by passing
    /// `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object
    /// References' in the Overview section for details.
    /// If this property is included in the response, any
    /// `variablesReference` previously associated with the updated variable, and those of its children, are no longer valid.
    variablesReference: ?u64 = null,
    /// The number of named child variables.
    /// The client can use this information to present the variables in a paged UI and
    /// fetch them in chunks.
    /// The value should be less than or equal to 2147483647 (2^31-1).
    namedVariables: ?u64 = null,
    /// The number of indexed child variables.
    /// The client can use this information to present the variables in a paged UI
    /// and fetch them in chunks.
    /// The value should be less than or equal to 2147483647 (2^31-1).
    indexedVariables: ?u64 = null,
    /// A memory reference to a location appropriate for this result.
    /// For pointer type eval results, this is generally a
    /// reference to the memory address contained in the pointer.
    /// This attribute may be returned by a debug adapter if
    /// corresponding capability `supportsMemoryReferences` is true.
    memoryReference: ?[]const u8 = null,
    /// A reference that allows the client to request the location where the new value is declared. For example, if the
    /// new value is function pointer, the adapter may be able to look up the function's location. This should be present
    /// only if the adapter is likely to be able to resolve the location.
    /// This reference shares the same lifetime as the
    /// `variablesReference`. See 'Lifetime of Object References' in the Overview section for details.
    valueLocationReference: ?u64 = null,
};

/// Response to `variables` request.
pub const VariablesResponseBody = struct {
    /// All (or a range) of variables for the given variable reference.
    variables: []const Variable,
};

pub const Variable = struct {
    /// The variable's name.
    name: []const u8,
    /// The variable's value.
    /// This can be a multi-line text, e.g. for a function the body of a function.
    /// For structured variables (which do not have a simple value), it is recommended to provide a one-line representation of
    /// the structured object. This helps to identify the structured object in the collapsed state when its children are not
    /// yet visible.
    /// An empty string can be used if no value should be shown in the UI.
    value: []const u8,
    /// The type of the variable's value. Typically shown in the UI when hovering over the value.
    /// This attribute should only be returned by a debug adapter if the corresponding capability `supportsVariableType` is true.
    type: ?[]const u8 = null,
    /// Properties of a variable that can be used to determine how to render the variable in the UI.
    presentationHint: ?VariablePresentationHint = null,
    /// The evaluatable name of this variable which can be passed to the `evaluate` request to fetch the variable's value.
    evaluateName: ?[]const u8 = null,
    /// If `variablesReference` is > 0, the variable is structured and its children can be retrieved by passing
    /// `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object
    /// References' in the Overview section for details.
    variablesReference: u64,
    /// The number of named child variables.
    /// The client can use this information to present the children in a paged UI and fetch them in chunks.
    namedVariables: ?u64 = null,
    /// The number of indexed child variables.
    /// The client can use this information to present the children in a paged UI and fetch them in chunks.
    indexedVariables: ?u64 = null,
    /// A memory reference associated with this variable.
    /// For pointer type variables, this is generally a reference to the memory address contained in the pointer.
    /// For executable data, this reference may later be used in a `disassemble` request.
    /// This attribute may be returned by a debug adapter if corresponding capability `supportsMemoryReferences` is true.
    memoryReference: ?[]const u8 = null,
    /// A reference that allows the client to request the location where the variable is declared. This should be present only if
    /// the adapter is likely to be able to resolve the location.
    /// This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview
    /// section for details.
    declarationLocationReference: ?u64 = null,
    /// A reference that allows the client to request the location where the variable's value is declared. For example, if the
    /// variable contains a function pointer, the adapter may be able to look up the function's location. This should be present
    /// only if the adapter is likely to be able to resolve the location.
    /// This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview
    /// section for details.
    valueLocationReference: ?u64 = null,
};

/// Properties of a variable that can be used to determine how to render the variable in the UI.
pub const VariablePresentationHint = struct {
    /// The kind of variable. Before introducing additional values, try to use the listed values.
    kind: VariablePresentationHintKind,
    /// Set of attributes represented as an array of strings. Before introducing additional values, try to use the listed values.
    attributes: []const VariableAttribute,
    /// Visibility of variable. Before introducing additional values, try to use the listed values.
    visibility: VariableVisibility,
    /// If true, clients can present the variable with a UI that supports a specific gesture to trigger its evaluation.
    /// This mechanism can be used for properties that require executing code when retrieving their value and where the code
    /// execution can be expensive and/or produce side-effects. A typical example are properties based on a getter function.
    /// Please note that in addition to the `lazy` flag, the variable's `variablesReference` is expected to refer to a variable
    /// that will provide the value through another `variable` request.
    lazy: bool,
};

pub const VariableVisibility = enum {
    public,
    private,
    protected,
    internal,
    final,
};

pub const VariableAttribute = enum {
    /// Indicates that the object is static."
    static,
    /// Indicates that the object is a constant."
    constant,
    /// Indicates that the object is read only."
    readOnly,
    /// Indicates that the object is a raw string."
    rawString,
    /// Indicates that the object can have an Object ID created for it. This is a vestigial attribute that is used by some
    /// clients; 'Object ID's are not specified in the protocol."
    hasObjectId,
    /// Indicates that the object has an Object ID associated with it. This is a vestigial attribute that is used by some
    /// clients; 'Object ID's are not specified in the protocol."
    canHaveObjectId,
    /// Indicates that the evaluation had side effects."
    hasSideEffects,
    /// Indicates that the object has its value tracked by a data breakpoint.
    hasDataBreakpoint,
};

pub const VariablePresentationHintKind = enum {
    /// Indicates that the object is a property."
    property,
    /// Indicates that the object is a method."
    method,
    /// Indicates that the object is a class."
    class,
    /// Indicates that the object is data."
    data,
    /// Indicates that the object is an event."
    event,
    /// Indicates that the object is a base class."
    baseClass,
    /// Indicates that the object is an inner class."
    innerClass,
    /// Indicates that the object is an interface."
    interface,
    /// Indicates that the object is the most derived class."
    mostDerivedClass,

    /// Indicates that the object is virtual, that means it is a synthetic object introduced by the adapter for rendering purposes,    /// e.g. an index range for large arrays."
    virtual,
    /// Deprecated: Indicates that a data breakpoint is registered for the object. The `hasDataBreakpoint` attribute should
    /// generally be used instead.
    dataBreakpoint,
};

/// Response to `source` request.
pub const SourceResponseBody = struct {
    /// Content of the source reference.
    content: []const u8,
    /// Content type (MIME type) of the source.
    mimeType: ?[]const u8 = null,
};

/// Response to `scopes` request.
pub const ScopesResponseBody = struct {
    /// The scopes of the stack frame. If the array has length zero, there are no scopes available.
    scopes: []const Scope,
};

pub const Scope = struct {
    /// Name of the scope such as 'Arguments', 'Locals', or 'Registers'. This string is shown in the UI as is and can be translated.
    name: []const u8,
    /// A hint for how to present this scope in the UI. If this attribute is missing, the scope is shown with a generic UI.
    presentationHint: ?ScopePresentationHint = null,
    /// The variables of this scope can be retrieved by passing the value of `variablesReference` to the `variables` request as
    /// long as execution remains suspended. See 'Lifetime of Object References' in the Overview section for details.
    variablesReference: u64,
    /// The number of named variables in this scope.
    /// The client can use this information to present the variables in a paged UI and fetch them in chunks.
    namedVariables: ?u64 = null,
    /// The number of indexed variables in this scope.
    /// The client can use this information to present the variables in a paged UI and fetch them in chunks.
    indexedVariables: ?u64 = null,
    /// If true, the number of variables in this scope is large or expensive to retrieve.
    expensive: bool,
    /// The source for this scope.
    source: ?Source = null,
    /// The start line of the range covered by this scope.
    line: ?u64 = null,
    /// Start position of the range covered by the scope. It is measured in UTF-16 code units and the client capability
    /// `columnsStartAt1` determines whether it is 0- or 1-based.
    column: ?u64 = null,
    /// The end line of the range covered by this scope.
    endLine: ?u64 = null,
    /// End position of the range covered by the scope. It is measured in UTF-16 code units and the client capability
    /// `columnsStartAt1` determines whether it is 0- or 1-based.
    endColumn: ?u64 = null,
};

pub const ScopePresentationHint = enum {
    /// Scope contains method arguments.
    arguments,
    /// Scope contains local variables.
    locals,
    /// Scope contains registers. Only a single `registers` scope should be returned from a `scopes` request.
    registers,
    /// Scope contains one or more return values
    returnValue,
};

/// Response to `stackTrace` request.
pub const StackTraceResponseBody = struct {
    /// The frames of the stack frame. If the array has length zero, there are no stack frames available.
    /// This means that there is no location information available.
    stackFrames: []const StackFrame,

    /// The total number of frames available in the stack. If omitted or if `totalFrames` is larger than the available frames,    /// a client is expected to request frames until a request returns less frames than requested (which indicates the end of the stack). Returning monotonically increasing `totalFrames` values for subsequent requests can be used to enforce paging in the client.
    totalFrames: ?u64 = null,
};

pub const StackFrame = struct {
    /// An identifier for the stack frame. It must be unique across all threads.
    /// This id can be used to retrieve the scopes of the frame with the `scopes` request or to restart the execution of a stack frame.
    id: u64,
    /// The name of the stack frame, typically a method name.
    name: []const u8,
    /// The source of the frame.
    source: ?Source = null,
    /// The line within the source of the frame. If the source attribute is missing or doesn't exist, `line` is 0 and should be
    /// ignored by the client.
    line: u64,
    /// Start position of the range covered by the stack frame. It is measured in UTF-16 code units and the client capability
    /// `columnsStartAt1` determines whether it is 0- or 1-based. If attribute `source` is missing or doesn't exist, `column`
    /// is 0 and should be ignored by the client.
    column: u64,
    /// The end line of the range covered by the stack frame.
    endLine: ?u64 = null,
    /// End position of the range covered by the stack frame. It is measured in UTF-16 code units and the client capability
    /// `columnsStartAt1` determines whether it is 0- or 1-based.
    endColumn: ?u64 = null,
    /// Indicates whether this frame can be restarted with the `restartFrame` request. Clients should only use this if the
    /// debug adapter supports the `restart` request and the corresponding capability `supportsRestartFrame` is true. If a
    /// debug adapter has this capability, then `canRestart` defaults to `true` if the property is absent.
    canRestart: ?bool = null,
    /// A memory reference for the current instruction pointer in this frame.
    instructionPointerReference: ?[]const u8 = null,
    /// The module associated with this frame, if any.
    moduleId: ?[]const u8 = null,
    /// A hint for how to present this frame in the UI.
    /// A value of `label` can be used to indicate that the frame is an artificial frame that is used as a visual label or
    /// separator. A value of `subtle` can be used to change the appearance of a frame in a 'subtle' way.
    presentationHint: ?PresentationHint = null,
};

pub const PresentationHint = enum {
    normal,
    label,
    subtle,
};

/// Arguments for `disassemble` request.
pub const DisassembleArguments = struct {
    /// Memory reference to the base location containing the instructions to disassemble.
    memoryReference: []const u8,
    /// Offset (in bytes) to be applied to the reference location before disassembling. Can be negative.
    offset: ?u64 = null,
    /// Offset (in instructions) to be applied after the byte offset (if any) before disassembling. Can be negative.
    instructionOffset: ?u64 = null,
    /// Number of instructions to disassemble starting at the specified location and offset.
    /// An adapter must return exactly this number of instructions - any unavailable instructions should be replaced with an
    /// implementation-defined 'invalid instruction' value.
    instructionCount: u64,
    /// If true, the adapter should attempt to resolve memory addresses and other values to symbolic names.
    resolveSymbols: ?bool = null,
};

/// Arguments for `writeMemory` request.
pub const WriteMemoryArguments = struct {
    /// Memory reference to the base location to which data should be written.
    memoryReference: []const u8,
    /// Offset (in bytes) to be applied to the reference location before writing data. Can be negative.
    offset: ?u64 = null,
    /// Property to control partial writes. If true, the debug adapter should attempt to write memory even if the entire memory
    /// region is not writable. In such a case the debug adapter should stop after hitting the first byte of memory that cannot
    /// be written and return the number of bytes written in the response via the `offset` and `bytesWritten` properties.
    /// If false or missing, a debug adapter should attempt to verify the region is writable before writing, and fail the response
    /// if it is not.
    allowPartial: ?bool = null,
    /// Bytes to write, encoded using base64.
    data: []const u8,
};

/// Arguments for `readMemory` request.
pub const ReadMemoryArguments = struct {
    /// Memory reference to the base location from which data should be read.
    memoryReference: []const u8,
    /// Offset (in bytes) to be applied to the reference location before reading data. Can be negative.
    offset: u64,
    /// Number of bytes to read at the specified location and offset.
    count: u64,
};

/// Arguments for `exceptionInfo` request.
pub const ExceptionInfoArguments = struct {
    /// Thread for which exception information should be retrieved.
    threadId: u64,
};

/// Arguments for `completions` request.
pub const CompletionsArguments = struct {
    /// Returns completions in the scope of this stack frame. If not specified, the completions are returned for the global scope.
    frameId: ?u64 = null,
    /// One or more source lines. Typically this is the text users have typed into the debug console before they asked for completion.
    text: []const u8,
    /// The position within `text` for which to determine the completion proposals. It is measured in UTF-16 code units and the
    /// client capability `columnsStartAt1` determines whether it is 0- or 1-based.
    column: u64,
    /// A line for which to determine the completion proposals. If missing the first line of the text is assumed.
    line: ?u64 = null,
};

/// Arguments for `gotoTargets` request.
pub const GotoTargetsArguments = struct {
    /// The source location for which the goto targets are determined.
    source: Source,
    /// The line location for which the goto targets are determined.
    line: u64,
    /// The position within `line` for which the goto targets are determined. It is measured in UTF-16 code units and the client
    /// capability `columnsStartAt1` determines whether it is 0- or 1-based.
    column: ?u64 = null,
};

/// Arguments for `stepInTargets` request.
pub const StepInTargetsArguments = struct {
    /// The stack frame for which to retrieve the possible step-in targets.
    frameId: u64,
};

/// Arguments for `setExpression` request.
pub const SetExpressionArguments = struct {
    /// Arguments for `setExpression` request."
    expression: []const u8,
    /// The l-value expression to assign to.
    value: []const u8,
    /// The value expression to assign to the l-value expression.
    frameId: ?u64 = null,
    /// Evaluate the expressions in the scope of this stack frame. If not specified, the expressions are evaluated in
    /// the global scope.
    format: ?ValueFormat = null,
};

/// Arguments for `evaluate` request.
pub const EvaluateArguments = struct {
    /// The expression to evaluate.
    expression: []const u8,
    /// Evaluate the expression in the scope of this stack frame. If not specified, the expression is evaluated in the global scope.
    frameId: ?u64 = null,
    /// The contextual line where the expression should be evaluated. In the 'hover' context, this should be set to the start of
    /// the expression being hovered.
    line: ?u64 = null,
    /// The contextual column where the expression should be evaluated. This may be provided if `line` is also provided.
    /// It is measured in UTF-16 code units and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
    column: ?u64 = null,
    /// The contextual source in which the `line` is found. This must be provided if `line` is provided.
    source: ?Source = null,
    /// The context in which the evaluate request is used.
    context: ?EvaluateContext = null,
    /// Specifies details on how to format the result.
    /// The attribute is only honored by a debug adapter if the corresponding capability `supportsValueFormattingOptions` is true
    format: ?ValueFormat = null,
};

pub const EvaluateContext = enum {
    /// evaluate is called from a watch view context."
    watch,
    /// evaluate is called from a REPL context."
    repl,
    /// evaluate is called to generate the debug hover contents.
    /// This value should only be used if the corresponding capability `supportsEvaluateForHovers` is true."
    hover,
    /// evaluate is called to generate clipboard contents.
    /// This value should only be used if the corresponding capability `supportsClipboardContext` is true."
    clipboard,
    /// evaluate is called from a variables view context.
    variables,
};

/// Arguments for `modules` request.
pub const ModulesArguments = struct {
    /// The index of the first module to return; if omitted modules start at 0.
    startModule: u64,
    /// The number of modules to return. If `moduleCount` is not specified or 0, all modules are returned.
    moduleCount: u64,
};

/// Arguments for `terminateThreads` request.
pub const TerminateThreadsArguments = struct {
    /// Ids of threads to be terminated.
    threadIds: []const u64,
};

/// Arguments for `setVariable` request.
pub const SetVariableArguments = struct {
    /// The reference of the variable container. The `variablesReference` must have been obtained in the current suspended state.
    /// See 'Lifetime of Object References' in the Overview section for details.
    variablesReference: u64,
    /// The name of the variable in the container.
    name: []const u8,
    /// The value of the variable.
    value: []const u8,
    /// Specifies details on how to format the response value.
    format: ?ValueFormat = null,
};

pub const VariablesArguments = struct {
    /// The variable for which to retrieve its children. The `variablesReference` must have been obtained in the current suspended
    /// state. See 'Lifetime of Object References' in the Overview section for details.
    variablesReference: u64,
    /// Filter to limit the child variables to either named or indexed. If omitted, both types are fetched.
    filter: ?Filter = null,
    /// The index of the first variable to return; if omitted children start at 0.
    /// The attribute is only honored by a debug adapter if the corresponding capability `supportsVariablePaging` is true.
    start: ?u64 = null,
    /// The number of variables to return. If count is missing or 0, all variables are returned.
    /// The attribute is only honored by a debug adapter if the corresponding capability `supportsVariablePaging` is true.
    count: ?u64 = null,
    /// Specifies details on how to format the Variable values.
    /// The attribute is only honored by a debug adapter if the corresponding capability `supportsValueFormattingOptions` is true.
    format: ?ValueFormat = null,
};

pub const Filter = enum {
    indexed,
    named,
};

pub const ValueFormat = struct {
    hex: bool,
};

pub const SourceArguments = struct {
    /// Specifies the source content to load. Either `source.path` or `source.sourceReference` must be specified.
    source: Source,
    /// The reference to the source. This is the same as `source.sourceReference`.
    /// This is provided for backward compatibility since old clients do not understand the `source` attribute.
    sourceReference: u64,
};

pub const ScopesArguments = struct {
    /// Retrieve the scopes for the stack frame identified by `frameId`. The `frameId` must have been obtained in the current
    /// suspended state. See 'Lifetime of Object References' in the Overview section for details.
    frameId: u64,
};

/// Arguments for `stackTrace` request.
pub const StackTraceArguments = struct {
    /// Retrieve the stacktrace for this thread.
    threadId: u64,
    /// The index of the first frame to return; if omitted frames start at 0.
    startFrame: u64 = 0,
    /// The maximum number of frames to return. If levels is not specified or 0, all frames are returned.
    levels: ?u64 = null,
    /// Specifies details on how to format the returned `StackFrame.name`. The debug adapter may format requested
    /// details in any way that would make sense to a developer.\nThe attribute is only honored by a debug adapter
    /// if the corresponding capability `supportsValueFormattingOptions` is true.
    format: ?StackFrameFormat = null,
};

pub const StackFrameFormat = struct {
    /// Display the value in hex.
    hex: bool,
    /// Displays parameters for the stack frame.
    parameters: bool,
    /// Displays the types of parameters for the stack frame.
    parameterTypes: bool,
    /// Displays the names of parameters for the stack frame.
    parameterNames: bool,
    /// Displays the values of parameters for the stack frame.
    parameterValues: bool,
    /// Displays the line number of the stack frame.
    line: bool,
    /// Displays the module of the stack frame.
    module: bool,
    /// Includes all stack frames, including those the debug adapter might otherwise hide.
    includeAll: bool,
};

/// A debug adapter initiated event
pub const Event = struct {
    /// Type of event
    event: EventTag,
    /// Event-specific information
    body: EventBody,

    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) std.json.ParseFromValueError!@This() {
        if (source != .object) {
            return error.UnexpectedToken;
        }

        const event_name = (source.object.get("event") orelse return error.MissingField).string;

        const event = std.meta.stringToEnum(
            EventTag,
            event_name,
        ) orelse return error.InvalidEnumTag;

        return .{
            .event = event,
            .body = try std.json.parseFromValueLeaky(
                EventBody,
                allocator,
                source,
                options,
            ),
        };
    }
};

pub const EventTag = enum {
    /// This event indicates that the debug adapter is ready to accept configuration requests
    /// (e.g. `setBreakpoints`, `setExceptionBreakpoints`).
    /// A debug adapter is expected to send this event when it is ready to accept configuration requests
    /// (but not before the `initialize` request has finished)
    /// The sequence of events/requests is as follows:
    ///  - adapters sends `initialized` event (after the `initialize` request has returned)
    ///  - client sends zero or more `setBreakpoints` requests
    ///  - client sends one `setFunctionBreakpoints` request (if corresponding capability `supportsFunctionBreakpoints` is true)
    ///  - client sends a `setExceptionBreakpoints` request if one or more `exceptionBreakpointFilters` have been defined (or if `supportsConfigurationDoneRequest` is not true)
    ///  - client sends other future configuration requests
    ///  - client sends one `configurationDone` request to indicate the end of the configuration
    initialized,
    /// The event indicates that the execution of the debuggee has stopped due to some condition
    /// This can be caused by a breakpoint previously set, a stepping request has completed, by executing
    /// a debugger statement etc.
    stopped,
    /// The event indicates that the debuggee has exited and returns its exit code.
    exited,
    /// The event indicates that debugging of the debuggee has terminated. This does **not** mean that the debuggee itself has exited.
    terminated,
    /// The event indicates that a thread has started or exited.
    thread,
    /// The event indicates that the target has produced some output.
    output,
    /// The event indicates that some information about a module has changed.
    module,
    /// This event indicates that some memory range has been updated. It should only be sent if the corresponding capability
    /// `supportsMemoryEvent` is true.
    /// Clients typically react to the event by re-issuing a `readMemory` request if they show the memory identified by the
    /// `memoryReference` and if the updated memory range overlaps the displayed range. Clients should not make assumptions
    /// how individual memory references relate to each other, so they should not assume that they are part of a single
    /// continuous address range and might overlap.
    /// Debug adapters can use this event to indicate that the contents of a memory range has changed due to some other
    /// request like `setVariable` or `setExpression`. Debug adapters are not expected to emit this event for each and
    /// every memory change of a running program, because that information is typically not available from debuggers and it
    /// would flood clients with too many events.
    memory,
    /// The event indicates that the debugger has begun debugging a new process. Either one that it has launched, or one
    /// that it has attached to.
    process,
    /// This event signals that some state in the debug adapter has changed and requires that the client needs to re-render
    /// the data snapshot previously requested.
    /// Debug adapters do not have to emit this event for runtime changes like stopped or thread events because in that case
    /// the client refetches the new state anyway. But the event can be used for example to refresh the UI after rendering
    /// formatting has changed in the debug adapter.
    /// This event should only be sent if the corresponding capability `supportsInvalidatedEvent` is true.
    invalidated,
    /// The event indicates that some source has been added, changed, or removed from the set of all loaded sources.
    loadedSource,
    /// The event indicates that one or more capabilities have changed.
    /// Since the capabilities are dependent on the client and its UI, it might not be possible to change that at random
    /// times (or too late).
    /// Consequently this event has a hint characteristic: a client can only be expected to make a 'best effort' in honoring
    /// individual capabilities but there are no guarantees.
    /// Only changed capabilities need to be included, all other capabilities keep their values.
    capabilities,
    /// The event signals that a long running operation is about to start and provides additional information for the client
    /// to set up a corresponding progress and cancellation UI.
    /// The client is free to delay the showing of the UI in order to reduce flicker.
    /// This event should only be sent if the corresponding capability `supportsProgressReporting` is true.
    progressStart,
    /// The event signals that the progress reporting needs to be updated with a new message and/or percentage.
    /// The client does not have to update the UI immediately, but the clients needs to keep track of the message
    /// and/or percentage values.
    /// This event should only be sent if the corresponding capability `supportsProgressReporting` is true.
    progressUpdate,
    /// The event signals the end of the progress reporting with a final message.
    /// This event should only be sent if
    /// the corresponding capability `supportsProgressReporting` is true.
    progressEnd,
    /// The event indicates that the execution of the debuggee has continued.
    /// Please note: a debug adapter is not expected to send this event in response to a request that implies that execution
    /// continues, e.g. `launch` or `continue`.
    /// It is only necessary to send a `continued` event if there was no previous request that implied this.
    continued,
    /// The event indicates that some information about a breakpoint has changed.
    breakpoint,
};

pub const EventBody = union(EventTag) {
    initialized: void,
    stopped: StoppedEventBody,
    exited: ExitedEventBody,
    terminated: TerminatedEventBody,
    thread: ThreadEventBody,
    output: OutputEventBody,
    module: ModuleEventBody,
    memory: MemoryEventBody,
    process: ProcessEventBody,
    invalidated: InvalidatedEventBody,
    loadedSource: LoadedSourceEventBody,
    capabilities: CapabilitiesEventBody,
    progressStart: ProgressStartEventBody,
    progressUpdate: ProgressUpdateEventBody,
    progressEnd: ProgressEndEventBody,
    continued: ContinuedEventBody,
    breakpoint: BreakpointEventBody,

    pub fn jsonParseFromValue(
        allocator: std.mem.Allocator,
        source: std.json.Value,
        options: std.json.ParseOptions,
    ) std.json.ParseFromValueError!@This() {
        if (source != .object) {
            return error.UnexpectedToken;
        }

        const tag_name = source.object.get("event") orelse return error.MissingField;
        if (tag_name != .string) return error.UnexpectedToken;

        inline for (std.meta.fields(@This())) |field| {
            if (std.mem.eql(u8, tag_name.string, field.name)) {
                return @unionInit(
                    @This(),
                    field.name,
                    if (field.type == void)
                        void{}
                    else
                        try std.json.parseFromValueLeaky(
                            field.type,
                            allocator,
                            source.object.get("body") orelse return error.MissingField,
                            options,
                        ),
                );
            }
        }

        return error.UnexpectedToken;
    }

    pub fn jsonStringify(
        self: *const @This(),
        out_stream: anytype,
    ) @TypeOf(out_stream.*).Error!void {
        switch (self.*) {
            inline else => |event_body| {
                if (@TypeOf(event_body) != void) {
                    try out_stream.write(event_body);
                } else {
                    try out_stream.beginObject();
                    try out_stream.endObject();
                }
            },
        }
    }
};

pub const BreakpointEventBody = struct {
    /// The reason for the event.
    reason: BreakpointEventReason,
    /// The `id` attribute is used to find the target breakpoint, the other attributes are used as the new values.
    breakpoint: Breakpoint,
};

pub const BreakpointEventReason = enum {
    changed,
    new,
    removed,
};

pub const ContinuedEventBody = struct {
    /// The thread which was continued.
    threadId: u64,
    /// If omitted or set to `true`, this event signals to the client that all threads have been resumed. The value
    /// `false` indicates that not all threads were resumed.
    allThreadsContinued: ?bool = null,
};

pub const ProgressEndEventBody = struct {
    /// The ID that was introduced in the initial `ProgressStartEvent`.
    progressId: []const u8,
    /// More detailed progress message. If omitted, the previous message (if any) is used.
    message: ?[]const u8 = null,
};

pub const ProgressUpdateEventBody = struct {
    /// The ID that was introduced in the initial `progressStart` event.
    progressId: []const u8,
    /// More detailed progress message. If omitted, the previous message (if any) is used.
    message: ?[]const u8 = null,
    /// Progress percentage to display (value range: 0 to 100). If omitted no percentage is shown.
    percentage: ?f64 = null,
};

pub const ProgressStartEventBody = struct {
    /// An ID that can be used in subsequent `progressUpdate` and `progressEnd` events to make them refer to the
    /// same progress reporting.
    /// IDs must be unique within a debug session.
    progressId: []const u8,
    /// Short title of the progress reporting. Shown in the UI to describe the long running operation.
    title: []const u8,
    /// The request ID that this progress report is related to. If specified a debug adapter is expected to emit
    /// progress events for the long running request until the request has been either completed or cancelled.
    /// If the request ID is omitted, the progress report is assumed to be related to some general activity of
    /// the debug adapter.
    requestId: ?u64 = null,
    /// If true, the request that reports progress may be cancelled with a `cancel` request.
    /// So this property basically controls whether the client should use UX that supports cancellation.
    /// Clients that don't support cancellation are allowed to ignore the setting.
    cancellable: ?bool = null,
    /// More detailed progress message.
    message: ?[]const u8,
    /// Progress percentage to display (value range: 0 to 100). If omitted no percentage is shown.
    percentage: ?f32,
};

pub const CapabilitiesEventBody = struct {
    capabilities: Capabilities,
};

pub const LoadedSourceEventBody = struct {
    /// The reason for the event.
    reason: LoadedReason,
    /// The new, changed, or removed source.
    source: Source,
};

pub const LoadedReason = enum {
    new,
    changed,
    removed,
};

pub const InvalidatedEventBody = struct {
    /// Set of logical areas that got invalidated. This property has a hint characteristic: a client can only be expected to make
    /// a 'best effort' in honoring the areas but there are no guarantees. If this property is missing, empty, or if values are
    /// not understood, the client should assume a single value `all`.
    areas: ?[]const InvalidatedAreas = null,
    /// If specified, the client only needs to refetch data related to this thread.
    threadId: ?u64 = null,
    /// If specified, the client only needs to refetch data related to this stack frame (and the `threadId` is ignored).
    stackFrameId: ?u64 = null,
};

pub const InvalidatedAreas = enum {
    /// All previously fetched data has become invalid and needs to be refetched."
    all,
    /// Previously fetched stack related data has become invalid and needs to be refetched."
    stacks,
    /// Previously fetched thread related data has become invalid and needs to be refetched."
    threads,
    /// Previously fetched variable data has become invalid and needs to be refetched.
    variables,
};

pub const ProcessEventBody = struct {
    /// The logical name of the process. This is usually the full path to process's executable file.
    /// Example: /home/example/myproj/program.js
    name: []const u8,
    /// The process ID of the debugged process, as assigned by the operating system. This property should be omitted
    /// for logical processes that do not map to operating system processes on the machine
    systemProcessId: ?u64 = null,
    /// If true, the process is running on the same computer as the debug adapter
    isLocalProcess: ?bool = null,
    /// Describes how the debug engine started debugging this process.
    startMethod: ?StartMethod = null,
    /// The size of a pointer or address for this process, in bits. This value may be used by clients when formatting
    /// addresses for display
    pointerSize: ?u64 = null,
};

pub const StartMethod = enum {
    // Process was launched under the debugger."
    launch,

    // Debugger attached to an existing process."
    attach,

    // A project launcher component has launched a new process in a suspended state and then asked the debugger to attach.
    attachForSuspendedLaunch,
};

pub const MemoryEventBody = struct {
    /// Memory reference of a memory range that has been updated.
    memoryReference: []const u8,
    /// Starting offset in bytes where memory has been updated. Can be negative.
    offset: u64,
    /// Number of bytes updated.
    count: u64,
};

pub const ModuleEventBody = struct {
    /// The reason for the event.
    reason: ModuleReason,
    /// The new, changed, or removed module. In case of `removed` only the module id is used.
    module: Module,
};

pub const Module = struct {
    /// Unique identifier for the module.
    id: []const u8,
    /// A name of the module.
    name: []const u8,
    /// Logical full path to the module. The exact definition is implementation defined, but usually this would
    /// be a full path to the on-disk file for the module.
    path: ?[]const u8 = null,
    /// True if the module is optimized.
    isOptimized: ?bool = null,
    /// True if the module is considered 'user code' by a debugger that supports 'Just My Code'.
    isUserCode: ?bool = null,
    /// Version of Module.
    version: ?[]const u8 = null,
    /// User-understandable description of if symbols were found for the module (ex: 'Symbols Loaded', 'Symbols not found', etc.)
    symbolStatus: ?[]const u8 = null,
    /// Logical full path to the symbol file. The exact definition is implementation defined.
    symbolFilePath: ?[]const u8 = null,
    /// Module created or modified, encoded as a RFC 3339 timestamp.
    dateTimeStamp: ?[]const u8 = null,
    /// Address range covered by this module.
    addressRange: ?[]const u8 = null,
};

pub const ModuleReason = enum {
    new,
    changed,
    removed,
};

pub const OutputEventBody = struct {
    /// The output category. If not specified or if the category is not understood by the client, `console` is assumed.
    category: ?OutputCategory = null,
    /// The output to report.
    /// ANSI escape sequences may be used to influence text color and styling if `supportsANSIStyling` is present in both the
    /// adapter's `Capabilities` and the client's `InitializeArguments`. A client may strip any unrecognized ANSI
    /// sequences.
    /// If the `supportsANSIStyling` capabilities are not both true, then the client should display the output literally.
    output: []const u8,
    /// Support for keeping an output log organized by grouping related messages.
    group: ?OutputGroup = null,
    /// If an attribute `variablesReference` exists and its value is > 0, the output contains objects which can be
    /// retrieved by passing `variablesReference` to the `variables` request as long as execution remains suspended.
    /// See 'Lifetime of Object References' in the Overview section for details.
    variablesReference: ?u64 = null,
    /// The source location where the output was produced.
    source: ?Source = null,
    /// The source location's line where the output was produced.
    line: ?u64 = null,
    /// The position in `line` where the output was produced. It is measured in UTF-16 code units and the client capability
    /// `columnsStartAt1` determines whether it is 0- or 1-based.
    column: ?u64 = null,
    /// Additional data to report. For the `telemetry` category the data is sent to telemetry, for the other categories
    /// the data is shown in JSON format.
    data: ?std.json.Value = null,
    /// A reference that allows the client to request the location where the new value is declared. For example, if the
    /// logged value is function pointer, the adapter may be able to look up the function's location. This should be
    /// present only if the adapter is likely to be able to resolve the location.
    /// This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in
    /// the Overview section for details.
    locationReference: ?u64 = null,
};

pub const OutputGroup = enum {
    /// Start a new group in expanded mode. Subsequent output events are members of the group and should be shown indented.
    /// The `output` attribute becomes the name of the group and is not indented."
    start,
    /// Start a new group in collapsed mode. Subsequent output events are members of the group and should be shown indented
    /// (as soon as the group is expanded).
    /// The `output` attribute becomes the name of the group and is not indented."
    startCollapsed,
    /// End the current group and decrease the indentation of subsequent output events.
    /// A non-empty `output` attribute is shown as the unindented end of the group.
    end,
};

pub const OutputCategory = enum {
    /// Show the output in the client's default message UI, e.g. a 'debug console'. This category should only be used
    /// for informational output from the debugger (as opposed to the debuggee).
    console,
    /// A hint for the client to show the output in the client's UI for important and highly visible information,    /// e.g. as a popup notification. This category should only be used for important messages from the debugger
    /// (as opposed to the debuggee). Since this category value is a hint, clients might ignore the hint and assume
    /// the `console` category.
    important,
    /// Show the output as normal program output from the debuggee.
    stdout,
    /// Show the output as error program output from the debuggee.
    stderr,
    /// Send the output to telemetry instead of showing it to the user.
    telemetry,
};

pub const ThreadEventBody = struct {
    /// The reason for the event.
    reason: ThreadEventReason,
    /// The identifier of the thread.
    threadId: u64,
};

pub const ThreadEventReason = enum {
    started,
    exited,
};

pub const TerminatedEventBody = struct {
    /// A debug adapter may set `restart` to true (or to an arbitrary object) to request that the client restarts the session.
    /// The value is not interpreted by the client and passed unmodified as an attribute `__restart` to the `launch` and `attach` requests.
    restart: ?std.json.Value = null,
};

pub const ExitedEventBody = struct {
    /// The exit code returned from the debuggee.
    exitCode: u64,
};

pub const StoppedEventBody = struct {
    /// The reason for the event.
    /// For backward compatibility this string is shown in the UI if the `description` attribute is missing
    /// (but it must not be translated).
    reason: StoppedEventReason,
    /// The full reason for the event, e.g. 'Paused on exception'. This string is shown in the UI as is and can be translated.
    description: ?[]const u8 = null,
    /// The thread which was stopped
    threadId: ?u64 = null,
    /// A value of true hints to the client that this event should not change the focus
    preserveFocusHint: ?bool = null,
    /// Additional information. E.g. if reason is `exception`, text contains the exception name. This string is
    /// shown in the UI
    text: ?[]const u8 = null,
    /// If `allThreadsStopped` is true, a debug adapter can announce that all threads have stopped.
    /// - The client should use this information to enable that all threads can be expanded to access their stacktraces.
    /// - If the attribute is missing or false, only the thread with the given `threadId` can be expanded.
    allThreadsStopped: ?bool = null,
    /// Ids of the breakpoints that triggered the event. In most cases there is only a single breakpoint but here
    /// are some examples for multiple breakpoints:
    /// - Different types of breakpoints map to the same location.
    /// - Multiple source breakpoints get collapsed to the same instruction by the compiler/runtime.
    /// - Multiple function breakpoints with different function names map to the same location.
    hitBreakpointIds: ?[]const u64 = null,
};

pub const StoppedEventReason = enum {
    step,
    breakpoint,
    exception,
    pause,
    entry,
    goto,
    function_breakpoint,
    data_breakpoint,
    instruction_breakpoint,
};

/// Response for a request
pub const Response = struct {
    /// Sequence number of the corresponding request
    request_seq: u64,
    /// Outcome of the request
    /// If true, the request was successful and the `body` attribute may contain the result of the request.
    /// If the value is false, the attribute `message` contains the error in short form and the `body` may contain
    /// additional information (see `ErrorResponse.body.error`)
    success: bool,
    /// The command requested
    command: CommandTag,
    /// Contains the raw error in short form if `success` is false
    /// This raw error might be interpreted by the client and is not shown in the UI.
    /// Some predefined values exist.
    message: ?ResponseErrorTag = null,
    /// Contains request result if success is true and error details if success is false
    body: ?ResponseBody = null,
};

pub const ResponseErrorTag = enum {
    cancelled,
    notStopped,
};

pub const ResponseBody = union(CommandTag) {
    cancel: void,
    initialize: Capabilities,
    configurationDone: void,
    launch: void,
    attach: void,
    restart: void,
    disconnect: void,
    terminate: void,
    breakpointLocations: BreakpointLocationsResponseBody,
    setBreakpoints: SetBreakpointsResponseBody,
    setFunctionBreakpoints: SetFunctionBreakpointsResponseBody,
    setExceptionBreakpoints: SetExceptionBreakpointsResponseBody,
    dataBreakpointInfo: DataBreakpointInfoResponseBody,
    setDataBreakpoints: SetDataBreakpointsResponseBody,
    setInstructionBreakpoints: SetInstructionBreakpointsResponseBody,
    @"continue": ContinueResponseBody,
    next: void,
    stepIn: void,
    stepOut: void,
    stepBack: void,
    reverseContinue: void,
    restartFrame: void,
    goto: void,
    pause: void,
    stackTrace: StackTraceResponseBody,
    scopes: ScopesResponseBody,
    source: SourceResponseBody,
    variables: VariablesResponseBody,
    setVariable: SetVariableResponseBody,
    threads: ThreadsResponseBody,
    terminateThreads: void,
    modules: ModulesResponseBody,
    loadedSources: LoadedSourcesResponseBody,
    evaluate: EvaluateResponseBody,
    setExpression: SetExpressionBody,
    stepInTargets: StepInTargetsResponseBody,
    gotoTargets: GotoTargetsResponseBody,
    completions: CompletionsResponseBody,
    exceptionInfo: ExceptionInfoResponseBody,
    readMemory: ReadMemoryResponseBody,
    writeMemory: WriteMemoryResponseBody,
    disassemble: DisassembleResponseBody,
    // Error message
    @"error": []const u8,

    pub fn jsonStringify(
        self: *const @This(),
        out_stream: anytype,
    ) @TypeOf(out_stream.*).Error!void {
        switch (self.*) {
            inline else => |body| {
                if (@TypeOf(body) != void) {
                    try out_stream.write(body);
                } else {
                    try out_stream.beginObject();
                    try out_stream.endObject();
                }
            },
        }
    }
};

/// Arguments for `cancel` request
pub const CancelArguments = struct {
    /// The ID (attribute `seq`) of the request to cancel. If missing no request is cancelled.
    /// Both a `requestId` and a `progressId` can be specified in one request
    requestId: u64,
    /// The ID (attribute `progressId`) of the progress to cancel. If missing no progress is cancelled.
    /// Both a `requestId` and a `progressId` can be specified in one request
    progressId: []const u8,
};

/// Arguments for `initialize` request.
pub const InitializeArguments = struct {
    /// The ID of the client using this adapter.
    clientID: ?[]const u8 = null,
    /// The human-readable name of the client using this adapter.
    clientName: ?[]const u8 = null,
    /// The ID of the debug adapter.
    adapterID: []const u8,
    /// The ISO-639 locale of the client using this adapter, e.g. en-US or de-CH.
    locale: ?[]const u8 = null,
    /// If true all line numbers are 1-based (default).
    linesStartAt1: ?bool = null,
    /// If true all column numbers are 1-based (default).
    columnsStartAt1: ?bool = null,
    /// Determines in what format paths are specified. The default is `path`, which is the native format.
    pathFormat: ?PathFormat = null,
    /// Client supports the `type` attribute for variables.
    supportsVariableType: ?bool = null,
    /// Client supports the paging of variables.
    supportsVariablePaging: ?bool = null,
    /// Client supports the `runInTerminal` request.
    supportsRunInTerminalRequest: ?bool = null,
    /// Client supports memory references.
    supportsMemoryReferences: ?bool = null,
    /// Client supports progress reporting.
    supportsProgressReporting: ?bool = null,
    /// Client supports the `invalidated` event.
    supportsInvalidatedEvent: ?bool = null,
    /// Client supports the `memory` event.
    supportsMemoryEvent: ?bool = null,
    /// Client supports the `argsCanBeInterpretedByShell` attribute on the `runInTerminal` request.
    supportsArgsCanBeInterpretedByShell: ?bool = null,
    /// Client supports the `startDebugging` request.
    supportsStartDebuggingRequest: ?bool = null,
    /// The client will interpret ANSI escape sequences in output when both client and adapter support it.
    supportsANSIStyling: ?bool = null,
};

pub const PathFormat = enum { path, uri };

/// Information about the capabilities of a debug adapter.
pub const Capabilities = struct {
    /// The debug adapter supports the `configurationDone` request.
    supportsConfigurationDoneRequest: ?bool = null,
    /// The debug adapter supports function breakpoints.
    supportsFunctionBreakpoints: ?bool = null,
    /// The debug adapter supports conditional breakpoints.
    supportsConditionalBreakpoints: ?bool = null,
    /// The debug adapter supports breakpoints that break execution after a specified number of hits.
    supportsHitConditionalBreakpoints: ?bool = null,
    /// The debug adapter supports a (side effect free) `evaluate` request for data hovers.
    supportsEvaluateForHovers: ?bool = null,
    /// Available exception filter options for the `setExceptionBreakpoints` request.
    exceptionBreakpointFilters: ?[]const ExceptionBreakpointsFilter = null,
    /// The debug adapter supports stepping back via the `stepBack` and `reverseContinue` requests.
    supportsStepBack: ?bool = null,
    /// The debug adapter supports setting a variable to a value.
    supportsSetVariable: ?bool = null,
    /// The debug adapter supports restarting a frame.
    supportsRestartFrame: ?bool = null,
    /// The debug adapter supports the `gotoTargets` request.
    supportsGotoTargetsRequest: ?bool = null,
    /// The debug adapter supports the `stepInTargets` request.
    supportsStepInTargetsRequest: ?bool = null,
    /// The debug adapter supports the `completions` request.
    supportsCompletionsRequest: ?bool = null,
    /// The set of characters that should trigger completion in a REPL. If not specified, the UI should assume the `.` character.
    completionTriggerCharacters: ?[]const []const u8 = null,
    /// The debug adapter supports the `modules` request.
    supportsModulesRequest: ?bool = null,
    /// The set of additional module information exposed by the debug adapter.
    additionalModuleColumns: ?[]const ColumnDescriptor = null,
    /// Checksum algorithms supported by the debug adapter.
    supportedChecksumAlgorithms: ?[]const ChecksumAlgorithm = null,
    /// The debug adapter supports the `restart` request. In this case a client should not implement `restart` by terminating and relaunching the adapter but by calling the `restart` request.
    supportsRestartRequest: ?bool = null,
    /// The debug adapter supports `exceptionOptions` on the `setExceptionBreakpoints` request.
    supportsExceptionOptions: ?bool = null,
    /// The debug adapter supports a `format` attribute on the `stackTrace`, `variables`, and `evaluate` requests.
    supportsValueFormattingOptions: ?bool = null,
    /// The debug adapter supports the `exceptionInfo` request.
    supportsExceptionInfoRequest: ?bool = null,
    /// The debug adapter supports the `terminateDebuggee` attribute on the `disconnect` request.
    supportsTerminateDebuggee: ?bool = null,
    /// The debug adapter supports the `suspendDebuggee` attribute on the `disconnect` request.
    supportsSuspendDebuggee: ?bool = null,
    /// The debug adapter supports the delayed loading of parts of the stack, which requires that both the `startFrame` and `levels` arguments and the `totalFrames` result of the `stackTrace` request are supported.
    supportsDelayedStackTraceLoading: ?bool = null,
    /// The debug adapter supports the `loadedSources` request.
    supportsLoadedSourcesRequest: ?bool = null,
    /// The debug adapter supports log points by interpreting the `logMessage` attribute of the `SourceBreakpoint`.
    supportsLogPoints: ?bool = null,
    /// The debug adapter supports the `terminateThreads` request.
    supportsTerminateThreadsRequest: ?bool = null,
    /// The debug adapter supports the `setExpression` request.
    supportsSetExpression: ?bool = null,
    /// The debug adapter supports the `terminate` request.
    supportsTerminateRequest: ?bool = null,
    /// The debug adapter supports data breakpoints.
    supportsDataBreakpoints: ?bool = null,
    /// The debug adapter supports the `readMemory` request.
    supportsReadMemoryRequest: ?bool = null,
    /// The debug adapter supports the `disassemble` request.
    supportsDisassembleRequest: ?bool = null,
    /// The debug adapter supports the `cancel` request.
    supportsCancelRequest: ?bool = null,
    /// The debug adapter supports the `breakpointLocations` request.
    supportsBreakpointLocationsRequest: ?bool = null,
    /// The debug adapter supports the `clipboard` context value in the `evaluate` request.
    supportsClipboardContext: ?bool = null,
    /// The debug adapter supports stepping granularities (argument `granularity`) for the stepping requests.
    supportsSteppingGranularity: ?bool = null,
    /// The debug adapter supports adding breakpoints based on instruction references.
    supportsInstructionBreakpoints: ?bool = null,
    /// The debug adapter supports `filterOptions` as an argument on the `setExceptionBreakpoints` request.
    supportsExceptionFilterOptions: ?bool = null,
    /// The debug adapter supports the `singleThread` property on the execution requests (`continue`, `next`, `stepIn`, `stepOut`, `reverseContinue`, `stepBack`).
    supportsSingleThreadExecutionRequests: ?bool = null,
    /// The debug adapter supports the `asAddress` and `bytes` fields in the `dataBreakpointInfo` request.
    supportsDataBreakpointBytes: ?bool = null,
    /// Modes of breakpoints supported by the debug adapter, such as 'hardware' or 'software'.
    breakpointModes: ?[]const BreakpointMode = null,
    /// The debug adapter supports ANSI escape sequences in styling of `OutputEvent.output` and `Variable.value` fields.
    supportsANSIStyling: ?bool = null,
};

pub const ExceptionBreakpointsFilter = struct {
    filter: []const u8,
    label: []const u8,
    description: ?[]const u8 = null,
    default: ?bool = null,
    supportsCondition: ?bool = null,
    conditionDescription: ?[]const u8 = null,
};

pub const ColumnDescriptor = struct {
    attributeName: []const u8,
    label: []const u8,
    format: ?[]const u8 = null,
    type: ?[]const u8 = null,
    width: ?u64 = null,
};

pub const ChecksumAlgorithm = enum { MD5, SHA1, SHA256, timestamp };

pub const BreakpointModeApplicability = enum { source, exception, data, instruction };

pub const BreakpointMode = struct {
    mode: []const u8,
    label: []const u8,
    description: ?[]const u8 = null,
    appliesTo: []const BreakpointModeApplicability,
};

/// Arguments for `launch` request. Additional attributes are implementation specific.
pub const LaunchArguments = struct {
    /// If true, the launch request should launch the program without enabling debugging.
    noDebug: ?bool = null,
    /// Arbitrary data from the previous, restarted session.
    /// The data is sent as the `restart` attribute of the `terminated` event
    /// The client should leave the data intact
    __restart: ?std.json.Value = null,
    /// Implementation specific data
    launch_data: ?std.json.Value = null,

    pub fn jsonParseFromValue(
        _: std.mem.Allocator,
        source: std.json.Value,
        _: std.json.ParseOptions,
    ) std.json.ParseFromValueError!@This() {
        return .{
            .noDebug = if (source.object.get("noDebug")) |noDebug| noDebug.bool else null,
            .__restart = if (source.object.get("__restart")) |__restart| __restart else null,
            .launch_data = source,
        };
    }
};

/// Arguments for `attach` request. Additional attributes are implementation specific.
pub const AttachArguments = struct {
    /// Arbitrary data from the previous, restarted session
    /// The data is sent as the `restart` attribute of the `terminated` event
    /// The client should leave the data intact
    __restart: std.json.Value = .null,
};

/// Arguments for `restart` request.
pub const RestartArguments = struct {
    /// The latest version of the `launch` or `attach` configuration.
    arguments: ?RestartUnion = null,
};

pub const RestartUnion = union(enum) {
    launch: LaunchArguments,
    attach: AttachArguments,
};

/// Arguments for `disconnect` request.
pub const DisconnectArguments = struct {
    /// A value of true indicates that this `disconnect` request is part of a restart sequence.
    restart: ?bool = null,
    /// Indicates whether the debuggee should be terminated when the debugger is disconnected.
    terminateDebuggee: ?bool = null,
    /// Indicates whether the debuggee should stay suspended when the debugger is disconnected.
    suspendDebuggee: ?bool = null,
};

/// Arguments for `terminate` request.
pub const TerminateArguments = struct {
    /// A value of true indicates that this `terminate` request is part of a restart sequence.
    restart: ?bool = null,
};

/// Arguments for `breakpointLocations` request.
pub const BreakpointLocationsArguments = struct {
    /// The source location of the breakpoints; either `source.path` or `source.sourceReference` must be specified.
    source: Source,
    /// Start line of range to search possible breakpoint locations in.
    line: u64,
    /// Start position within `line` to search possible breakpoint locations in.
    column: ?u64 = null,
    /// End line of range to search possible breakpoint locations in.
    endLine: ?u64 = null,
    /// End position within `endLine` to search possible breakpoint locations in.
    endColumn: ?u64 = null,
};

/// A `Source` is a descriptor for source code.
/// It is returned from the debug adapter as part of a `StackFrame` and it is used by clients when specifying breakpoints.
pub const Source = struct {
    /// The short name of the source. Every source returned from the debug adapter has a name.
    /// When sending a source to the debug adapter this name is optional.
    name: ?[]const u8 = null,
    /// The path of the source to be shown in the UI.
    /// It is only used to locate and load the content of the source if no `sourceReference` is specified (or its value is 0).
    path: ?[]const u8 = null,
    /// If the value > 0 the contents of the source must be retrieved through the `source` request (even if a path is specified).
    /// Since a `sourceReference` is only valid for a session, it can not be used to persist a source.
    /// The value should be less than or equal to 2147483647 (2^31-1).
    sourceReference: ?u64 = null,
    /// A hint for how to present the source in the UI.
    /// A value of `deemphasize` can be used to indicate that the source is not available or that it is skipped on stepping.
    presentationHint: ?[]const u8 = null,
    /// The origin of this source. For example, 'internal module', 'inlined content from source map', etc.
    origin: ?[]const u8 = null,
    /// A list of sources that are related to this source. These may be the source that generated this source.
    sources: ?[]const Source = null,
    /// Additional data that a debug adapter might want to loop through the client.
    /// The client should leave the data intact and persist it across sessions. The client should not interpret the data.
    adapterData: ?std.json.Value = null,
    /// The checksums associated with this file.
    checksums: ?[]const Checksum = null,
};

/// The checksum of an item calculated by the specified algorithm.
pub const Checksum = struct {
    /// The algorithm used to calculate this checksum.
    algorithm: ChecksumAlgorithm,
    /// Value of the checksum, encoded as a hexadecimal value.
    checksum: []const u8,
};

/// Response to `breakpointLocations` request.
/// Contains possible locations for source breakpoints.
pub const BreakpointLocationsResponseBody = struct {
    /// Sorted set of possible breakpoint locations.
    breakpoints: []const BreakpointLocation,
};

/// Properties of a breakpoint location returned from the `breakpointLocations` request.
pub const BreakpointLocation = struct {
    /// Start line of breakpoint location.
    line: u64,
    /// The start position of a breakpoint location. Position is measured in UTF-16 code units and the client
    /// capability `columnsStartAt1` determines whether it is 0- or 1-based.
    column: ?u64 = null,
    /// The end line of breakpoint location if the location covers a range.
    endLine: ?u64 = null,
    /// The end position of a breakpoint location (if the location covers a range). Position is measured in
    /// UTF-16 code units and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
    endColumn: ?u64 = null,
};

/// Arguments for `setBreakpoints` request.
pub const SetBreakpointsArguments = struct {
    /// The source location of the breakpoints; either `source.path` or `source.sourceReference` must be specified.
    source: Source,
    /// The code locations of the breakpoints.
    breakpoints: ?[]const SourceBreakpoint = null,
    /// Deprecated: The code locations of the breakpoints.
    lines: ?[]const u64 = null,
    /// A value of true indicates that the underlying source has been modified which results in new breakpoint locations.
    sourceModified: ?bool = null,
};

pub const SourceBreakpoint = struct {
    /// The source line of the breakpoint or logpoint.
    line: u64,
    /// Start position within source line of the breakpoint or logpoint. It is measured in UTF-16 code units and
    /// the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
    column: ?u64 = null,
    /// he expression for conditional breakpoints.
    /// It is only honored by a debug adapter if the corresponding capability `supportsConditionalBreakpoints` is true.
    condition: ?[]const u8 = null,
    /// The expression that controls how many hits of the breakpoint are ignored.
    /// The debug adapter is expected to interpret the expression as needed.
    /// The attribute is only honored by a debug adapter if the corresponding capability `supportsHitConditionalBreakpoints`
    /// is true.
    /// If both this property and `condition` are specified, `hitCondition` should be evaluated only if the `condition` is
    /// met, and the debug adapter should stop only if both conditions are met.
    hitCondition: ?[]const u8 = null,
    /// If this attribute exists and is non-empty, the debug adapter must not 'break' (stop)
    /// but log the message instead. Expressions within `{}` are interpolated.
    /// The attribute is only honored by a debug adapter if the corresponding capability `supportsLogPoints` is true.
    /// If either `hitCondition` or `condition` is specified, then the message should only be logged if those
    /// conditions are met.
    logMessage: ?[]const u8 = null,
    /// The mode of this breakpoint. If defined, this must be one of the `breakpointModes` the debug adapter advertised
    /// in its `Capabilities`.
    mode: ?[]const u8 = null,
};

/// Response to `setBreakpoints` request.
/// Returned is information about each breakpoint created by this request.
/// This includes the actual code location and whether the breakpoint could be verified.
/// The breakpoints returned are in the same order as the elements of the `breakpoints`
/// (or the deprecated `lines`) array in the arguments.
pub const SetBreakpointsResponseBody = struct {
    /// Information about the breakpoints.
    /// The array elements are in the same order as the elements of the `breakpoints` (or the deprecated `lines`) array in the arguments.
    breakpoints: []const Breakpoint,
};

/// Information about a breakpoint created in `setBreakpoints`, `setFunctionBreakpoints`, `setInstructionBreakpoints`, or
/// `setDataBreakpoints` requests.
pub const Breakpoint = struct {
    /// The identifier for the breakpoint. It is needed if breakpoint events are used to update or remove breakpoints.
    id: ?u64 = null,
    /// If true, the breakpoint could be set (but not necessarily at the desired location).
    verified: bool,
    /// A message about the state of the breakpoint.
    /// This is shown to the user and can be used to explain why a breakpoint
    /// could not be verified.
    message: ?[]const u8 = null,
    /// The source where the breakpoint is located.
    source: ?Source = null,
    /// The start line of the actual range covered by the breakpoint.
    line: ?u64 = null,
    /// Start position of the source range covered by the breakpoint. It is measured in UTF-16 code units and the client
    /// capability `columnsStartAt1` determines whether it is 0- or 1-based.
    column: ?u64 = null,
    /// The end line of the actual range covered by the breakpoint.
    endLine: ?u64 = null,
    /// End position of the source range covered by the breakpoint. It is measured in UTF-16 code units and the client
    /// capability `columnsStartAt1` determines whether it is 0- or 1-based.
    /// If no end line is given, then the end column is assumed to be in the start line.
    endColumn: ?u64 = null,
    /// A memory reference to where the breakpoint is set.
    instructionReference: ?[]const u8 = null,
    /// The offset from the instruction reference.
    /// This can be negative.
    offset: ?u64 = null,
    /// A machine-readable explanation of why a breakpoint may not be verified. If a breakpoint is verified or a specific reason is
    /// not known, the adapter should omit this property. Possible values include:
    /// - `pending`: Indicates a breakpoint might be verified in the future, but the adapter cannot verify it in the current state.
    /// - `failed`: Indicates a breakpoint was not able to be verified, and the adapter does not believe it can be verified
    /// without intervention.
    reason: ?BreakPointReason = null,
};

pub const BreakPointReason = enum {
    pending,
    failed,
};

/// Arguments for `setFunctionBreakpoints` request.
pub const SetFunctionBreakpointsArguments = struct {
    /// The function names of the breakpoints.
    breakpoints: []const FunctionBreakpoint,
};

/// Properties of a breakpoint passed to the `setFunctionBreakpoints` request.
pub const FunctionBreakpoint = struct {
    /// The name of the function.
    name: []const u8,
    /// An expression for conditional breakpoints.
    /// It is only honored by a debug adapter if the corresponding capability `supportsConditionalBreakpoints` is true.
    condition: ?[]const u8 = null,
    /// An expression that controls how many hits of the breakpoint are ignored.
    /// The debug adapter is expected to interpret the expression as needed.
    /// The attribute is only honored by a debug adapter if the corresponding capability `supportsHitConditionalBreakpoints`
    /// is true.
    hitCondition: ?[]const u8 = null,
};

/// Response to `setFunctionBreakpoints` request.
/// Returned is information about each breakpoint created by this request.
pub const SetFunctionBreakpointsResponseBody = struct {
    /// Information about the breakpoints. The array elements correspond to the elements of the `breakpoints` array.
    breakpoints: []const Breakpoint,
};

/// Arguments for `setExceptionBreakpoints` request.
pub const SetExceptionBreakpointsArguments = struct {
    /// Set of exception filters specified by their ID.
    filters: []const []const u8,
    /// Set of exception filters and their options.
    filterOptions: ?[]const ExceptionFilterOptions = null,
    /// Configuration options for selected exceptions.
    exceptionOptions: ?[]const ExceptionOptions = null,
};

/// An `ExceptionFilterOptions` is used to specify an exception filter together with a condition for the
/// `setExceptionBreakpoints` request.
pub const ExceptionFilterOptions = struct {
    /// ID of an exception filter returned by the `exceptionBreakpointFilters` capability.
    filterId: []const u8,
    /// An expression for conditional exceptions.
    /// The exception breaks into the debugger if the result of the condition is true.
    condition: ?[]const u8 = null,
    /// The mode of this exception breakpoint. If defined, this must be one of the `breakpointModes` the debug adapter advertised in its `Capabilities`.
    mode: ?[]const u8 = null,
};

/// An `ExceptionOptions` assigns configuration options to a set of exceptions.
pub const ExceptionOptions = struct {
    /// A path that selects a single or multiple exceptions in a tree. If `path` is missing, the whole tree is selected.
    /// By convention the first segment of the path is a category that is used to group exceptions in the UI.
    path: ?[]const ExceptionPathSegment = null,
    /// Condition when a thrown exception should result in a break.
    breakMode: []const ExceptionBreakMode,
};

pub const ExceptionBreakMode = enum {
    never,
    always,
    unhandled,
    userUnhandled,
};

pub const ExceptionPathSegment = struct {
    names: []const []const u8,
    negate: ?bool = null,
};

/// Response to `setExceptionBreakpoints` request.
/// The response contains an array of `Breakpoint` objects with information about each exception breakpoint or filter.
/// The `Breakpoint` objects are in the same order as the elements of the `filters`, `filterOptions`, `exceptionOptions`
/// arrays given as arguments. If both `filters` and `filterOptions` are given, the returned array must start with
/// `filters` information first, followed by `filterOptions` information.
/// The `verified` property of a `Breakpoint` object signals whether the exception breakpoint or filter could be
/// successfully created and whether the condition is valid. In case of an error the `message` property explains the
/// problem. The `id` property can be used to introduce a unique ID for the exception breakpoint or filter so that it
/// can be updated subsequently by sending breakpoint events.
/// For backward compatibility both the `breakpoints` array and the enclosing `body` are optional. If these elements
/// are missing a client is not able to show problems for individual exception breakpoints or filters.
pub const SetExceptionBreakpointsResponseBody = struct {
    /// Information about the exception breakpoints or filters.    /// The breakpoints returned are in the same order as the elements of the `filters`, `filterOptions`,
    /// `exceptionOptions` arrays in the arguments. If both `filters` and `filterOptions` are given, the returned
    /// array must start with `filters` information first, followed by `filterOptions` information.
    breakpoints: ?[]const Breakpoint = null,
};

/// Arguments for `dataBreakpointInfo` request.
pub const DataBreakpointInfoArguments = struct {
    /// Reference to the variable container if requested for a child of the container.
    /// The `variablesReference` must have been obtained in the current suspended state.
    /// See 'Lifetime of Object References' in the Overview section for details.
    variablesReference: ?u64 = null,
    /// The name of the variable's child to obtain data breakpoint information for.
    /// If `variablesReference` isn't specified, this can be an expression, or an address if `asAddress` is also true.
    name: []const u8,
    /// When name is an expression, evaluate in the scope of this stack frame.    /// If not specified, the expression is evaluated in the global scope. When `variablesReference` is specified,
    /// this property has no effect.
    frameId: ?u64 = null,
    /// If specified, a debug adapter should return information for the range of memory extending `bytes` number of bytes
    /// from the address or variable specified by `name`. Breakpoints set using the resulting data ID should pause on data
    /// access anywhere within that range.
    /// Clients may set this property only if the `supportsDataBreakpointBytes` capability is true.
    bytes: ?u64 = null,
    /// If `true`, the `name` is a memory address and the debugger should interpret it as a decimal value, or hex value if
    /// it is prefixed with `0x`.
    /// Clients may set this property only if the `supportsDataBreakpointBytes` capability is true.
    asAddress: ?bool = null,
    /// The mode of the desired breakpoint. If defined, this must be one of the `breakpointModes` the debug adapter
    /// advertised in its `Capabilities`.
    mode: ?[]const u8 = null,
};

/// Response body for `dataBreakpointInfo`.
pub const DataBreakpointInfoResponseBody = struct {
    /// An identifier for the data on which a data breakpoint can be registered with the `setDataBreakpoints` request
    /// or null if no data breakpoint is available. If a `variablesReference` or `frameId` is passed, the `dataId`
    /// is valid in the current suspended state, otherwise it's valid indefinitely. See 'Lifetime of Object References'
    /// in the Overview section for details. Breakpoints set using the `dataId` in the `setDataBreakpoints` request may
    /// outlive the lifetime of the associated `dataId`.
    dataId: ?[]const u8 = null,
    /// UI string that describes on what data the breakpoint is set on or why a data breakpoint is not available.
    description: []const u8,
    /// Attribute lists the available access types for a potential data breakpoint. A UI client could surface this information.
    accessTypes: ?[]const DataBreakpointAccessType = null,
    /// Attribute indicates that a potential data breakpoint could be persisted across sessions.
    canPersist: ?bool = null,
};

pub const DataBreakpointAccessType = enum {
    read,
    write,
    readWrite,
};

/// Arguments for `setDataBreakpoints` request.
pub const SetDataBreakpointsArguments = struct {
    /// The contents of this array replaces all existing data breakpoints.
    breakpoints: []const DataBreakpoint,
};

/// Properties of a data breakpoint passed to the `setDataBreakpoints` request.
pub const DataBreakpoint = struct {
    /// An id representing the data. This id is returned from the `dataBreakpointInfo` request.
    dataId: []const u8,
    /// The access type of the data.
    accessType: ?DataBreakpointAccessType = null,
    /// An expression for conditional breakpoints.
    condition: ?[]const u8 = null,
    /// An expression that controls how many hits of the breakpoint are ignored.
    /// The debug adapter is expected to interpret the expression as needed.
    hitCondition: ?[]const u8 = null,
};

/// Response to `setDataBreakpoints` request.
/// Returned is information about each breakpoint created by this request.
pub const SetDataBreakpointsResponseBody = struct {
    /// Information about the data breakpoints. The array elements correspond to the elements of the input argument
    /// `breakpoints` array.
    breakpoints: []const Breakpoint,
};

/// Arguments for `setInstructionBreakpoints` request.
pub const SetInstructionBreakpointsArguments = struct {
    /// The instruction references of the breakpoints.
    breakpoints: []const InstructionBreakpoint,
};

/// Properties of a breakpoint passed to the `setInstructionBreakpoints` request
pub const InstructionBreakpoint = struct {
    /// The instruction reference of the breakpoint.    /// This should be a memory or instruction pointer reference from an `EvaluateResponse`, `Variable`, `StackFrame`,
    /// `GotoTarget`, or `Breakpoint`.
    instructionReference: []const u8,
    /// The offset from the instruction reference in bytes.
    /// This can be negative.
    offset: ?i64 = null,
    /// An expression for conditional breakpoints.
    /// It is only honored by a debug adapter if the corresponding
    /// capability `supportsConditionalBreakpoints` is true.
    condition: ?[]const u8 = null,
    /// An expression that controls how many hits of the breakpoint are ignored.
    /// The debug adapter is expected to interpret the expression as needed.
    /// The attribute is only honored by a debug adapter if the corresponding capability `supportsHitConditionalBreakpoints` is true.
    hitCondition: ?[]const u8 = null,
    /// The mode of this breakpoint. If defined, this must be one of the `breakpointModes` the debug adapter advertised
    /// in its `Capabilities`.
    mode: ?[]const u8 = null,
};

/// Response body for `setInstructionBreakpoints`.
pub const SetInstructionBreakpointsResponseBody = struct {
    /// Information about the breakpoints. The array elements correspond to the elements of the `breakpoints` array.
    breakpoints: []const Breakpoint,
};

/// Arguments for `_continue` request.
pub const ContinueArguments = struct {
    /// Specifies the active thread. If the debug adapter supports single thread execution (see
    /// `supportsSingleThreadExecutionRequests`) and the argument `singleThread` is true, only the thread with this ID is resumed.
    threadId: u64,
    /// If this flag is true, execution is resumed only for the thread with given `threadId`.
    singleThread: ?bool = null,
};

/// Response body for `continue`.
pub const ContinueResponseBody = struct {
    /// If omitted or set to `true`, this response signals to the client that all threads have been resumed. The value `false` indicates that not all threads were resumed.
    allThreadsContinued: ?bool = null,
};

pub const SteppingGranularity = enum {
    /// The step should allow the program to run until the current statement has finished executing.
    /// The meaning of a statement is determined by the adapter and it may be considered equivalent to a line.
    /// For example 'for(int i = 0; i < 10; i++)' could be considered to have 3 statements 'int i = 0', 'i < 10', and 'i++'.
    statement,
    /// The step should allow the program to run until the current source line has executed.
    line,
    /// The step should allow one instruction to execute (e.g. one x86 instruction).
    instruction,
};

/// Arguments for `next` request.
pub const NextArguments = struct {
    /// Specifies the thread for which to resume execution for one step (of the given granularity).
    threadId: u64,
    /// If this flag is true, all other suspended threads are not resumed.
    singleThread: ?bool = null,
    /// Stepping granularity. If no granularity is specified, a granularity of `statement` is assumed.
    granularity: ?SteppingGranularity = null,
};

/// Arguments for `stepIn` request.
pub const StepInArguments = struct {
    /// Specifies the thread for which to resume execution for one step-into (of the given granularity).
    threadId: u64,
    /// If this flag is true, all other suspended threads are not resumed.
    singleThread: ?bool = null,
    /// Id of the target to step into.
    targetId: ?u64 = null,
    /// Stepping granularity. If no granularity is specified, a granularity of `statement` is assumed.
    granularity: ?SteppingGranularity = null,
};

/// Arguments for `stepOut` request.
pub const StepOutArguments = struct {
    /// Specifies the thread for which to resume execution for one step-out (of the given granularity).
    threadId: u64,
    /// If this flag is true, all other suspended threads are not resumed.
    singleThread: ?bool = null,
    /// Stepping granularity. If no granularity is specified, a granularity of `statement` is assumed.
    granularity: ?SteppingGranularity = null,
};

/// Arguments for `stepBack` request.
pub const StepBackArguments = struct {
    /// Specifies the thread for which to resume execution for one step backwards (of the given granularity).
    threadId: u64,
    /// If this flag is true, all other suspended threads are not resumed.
    singleThread: ?bool = null,
    /// Stepping granularity to step. If no granularity is specified, a granularity of `statement` is assumed.
    granularity: ?SteppingGranularity = null,
};

/// Arguments for `reverseContinue` request.
pub const ReverseContinueArguments = struct {
    /// Specifies the active thread. If the debug adapter supports single thread execution (see
    /// `supportsSingleThreadExecutionRequests`) and the `singleThread` argument is true, only the thread with
    /// this ID is resumed.
    threadId: u64,
    /// If this flag is true, backward execution is resumed only for the thread with given `threadId`.
    singleThread: ?bool = null,
};

/// Arguments for `restartFrame` request.
pub const RestartFrameArguments = struct {
    /// Restart the stack frame identified by `frameId`. The `frameId` must have been obtained in the current suspended state.
    /// See 'Lifetime of Object References' in the Overview section for details.
    frameId: u64,
};

/// Arguments for `goto` request.
pub const GotoArguments = struct {
    /// Set the goto target for this thread.
    threadId: u64,
    /// The location where the debuggee will continue to run.
    targetId: u64,
};

/// Arguments for `pause` request.
pub const PauseArguments = struct {
    /// Pause execution for this thread.
    threadId: u64,
};

test "From json" {
    const data: []const []const u8 = &.{
        "{ \"seq\": 1, \"type\": \"request\", \"command\": \"initialize\", \"arguments\": { \"adapterID\": \"example-adapter\", \"clientID\": \"my-client\", \"clientName\": \"My Client\", \"locale\": \"en-US\", \"linesStartAt1\": true, \"columnsStartAt1\": true, \"pathFormat\": \"path\", \"supportsVariableType\": true, \"supportsVariablePaging\": true, \"supportsRunInTerminalRequest\": true, \"supportsMemoryReferences\": true, \"supportsProgressReporting\": true, \"supportsInvalidatedEvent\": true, \"supportsMemoryEvent\": true, \"supportsArgsCanBeInterpretedByShell\": true, \"supportsStartDebuggingRequest\": true, \"supportsANSIStyling\": true } }",
        "{ \"seq\": 2, \"type\": \"event\", \"event\": \"initialized\" }",
        "{ \"seq\": 3, \"type\": \"request\", \"command\": \"setBreakpoints\", \"arguments\": { \"source\": { \"path\": \"/project/main.c\", \"name\": \"main.c\", \"sourceReference\": 0, \"presentationHint\": \"normal\", \"origin\": \"workspace\", \"sources\": [], \"adapterData\": null, \"checksums\": [] }, \"breakpoints\": [ { \"line\": 12, \"column\": 1, \"condition\": \"x > 0\", \"hitCondition\": \"3\", \"logMessage\": \"bp hit\", \"mode\": \"hardware\" } ], \"lines\": [ 12 ], \"sourceModified\": false } }",
        "{ \"seq\": 4, \"type\": \"request\", \"command\": \"configurationDone\", \"arguments\": {} }",
        "{ \"seq\": 5, \"type\": \"request\", \"command\": \"launch\", \"arguments\": { \"noDebug\": false, \"__restart\": {} } }",
        "{ \"seq\": 6, \"type\": \"event\", \"event\": \"process\", \"body\": { \"name\": \"/project/bin/app\", \"systemProcessId\": 12345, \"isLocalProcess\": true, \"startMethod\": \"launch\", \"pointerSize\": 64 } }",
        "{ \"seq\": 7, \"type\": \"event\", \"event\": \"thread\", \"body\": { \"reason\": \"started\", \"threadId\": 1 } }",
        "{ \"seq\": 8, \"type\": \"event\", \"event\": \"stopped\", \"body\": { \"reason\": \"breakpoint\", \"description\": \"Paused on breakpoint\", \"threadId\": 1, \"preserveFocusHint\": false, \"text\": \"bp #1\", \"allThreadsStopped\": true, \"hitBreakpointIds\": [ 1 ] } }",
        "{ \"seq\": 9, \"type\": \"request\", \"command\": \"stackTrace\", \"arguments\": { \"threadId\": 1, \"startFrame\": 0, \"levels\": 20, \"format\": { \"hex\": true, \"parameters\": true, \"parameterTypes\": true, \"parameterNames\": true, \"parameterValues\": true, \"line\": true, \"module\": true, \"includeAll\": true } } }",
        "{ \"seq\": 10, \"type\": \"request\", \"command\": \"scopes\", \"arguments\": { \"frameId\": 1000 } }",
        "{ \"seq\": 11, \"type\": \"request\", \"command\": \"variables\", \"arguments\": { \"variablesReference\": 2000, \"filter\": \"named\", \"start\": 0, \"count\": 50, \"format\": { \"hex\": false } } }",
        "{ \"seq\": 12, \"type\": \"request\", \"command\": \"continue\", \"arguments\": { \"threadId\": 1, \"singleThread\": false } }",
        "{ \"seq\": 13, \"type\": \"event\", \"event\": \"continued\", \"body\": { \"threadId\": 1, \"allThreadsContinued\": true } }",
        // "{ \"seq\": 14, \"type\": \"event\", \"event\": \"output\", \"body\": { \"category\": \"stdout\", \"output\": \"Hello, world!
        // \", \"group\": \"start\", \"variablesReference\": 0, \"source\": { \"path\": \"/project/main.c\", \"name\": \"main.c\", \"sourceReference\": 0, \"presentationHint\": \"normal\" }, \"line\": 12, \"column\": 1, \"data\": {}, \"locationReference\": 0 } }",
        "{ \"seq\": 15, \"type\": \"event\", \"event\": \"breakpoint\", \"body\": { \"reason\": \"changed\", \"breakpoint\": { \"id\": 1, \"verified\": true, \"message\": \"enabled\", \"source\": { \"path\": \"/project/main.c\", \"name\": \"main.c\" }, \"line\": 12, \"column\": 1, \"endLine\": 12, \"endColumn\": 1 } } }",
        "{ \"seq\": 16, \"type\": \"event\", \"event\": \"module\", \"body\": { \"reason\": \"new\", \"module\": { \"id\": \"mod-1\", \"name\": \"libmath.so\", \"path\": \"/usr/lib/libmath.so\", \"isOptimized\": true, \"isUserCode\": true, \"version\": \"1.2.3\", \"symbolStatus\": \"Symbols Loaded\", \"symbolFilePath\": \"/usr/lib/debug/libmath.so.debug\", \"dateTimeStamp\": \"2025-10-11T12:00:00Z\", \"addressRange\": \"0x1000-0x1FFF\" } } }",
        "{ \"seq\": 17, \"type\": \"event\", \"event\": \"loadedSource\", \"body\": { \"reason\": \"new\", \"source\": { \"path\": \"/project/main.c\", \"name\": \"main.c\", \"sourceReference\": 0 } } }",
        "{ \"seq\": 18, \"type\": \"event\", \"event\": \"capabilities\", \"body\": { \"capabilities\": { \"supportsConfigurationDoneRequest\": true, \"supportsFunctionBreakpoints\": true, \"supportsConditionalBreakpoints\": true, \"supportsHitConditionalBreakpoints\": true, \"supportsEvaluateForHovers\": true, \"exceptionBreakpointFilters\": [ { \"filter\": \"all\", \"label\": \"All Exceptions\", \"description\": \"Break on all exceptions\", \"default\": false, \"supportsCondition\": true, \"conditionDescription\": \"expr\" } ], \"supportsStepBack\": false, \"supportsSetVariable\": true, \"supportsRestartFrame\": false, \"supportsGotoTargetsRequest\": true, \"supportsStepInTargetsRequest\": true, \"supportsCompletionsRequest\": true, \"completionTriggerCharacters\": [ \".\" ], \"supportsModulesRequest\": true, \"additionalModuleColumns\": [ { \"attributeName\": \"path\", \"label\": \"Path\", \"format\": \"string\", \"type\": \"string\", \"width\": 40 } ], \"supportedChecksumAlgorithms\": [ \"MD5\", \"SHA1\", \"SHA256\", \"timestamp\" ], \"supportsRestartRequest\": true, \"supportsExceptionOptions\": true, \"supportsValueFormattingOptions\": true, \"supportsExceptionInfoRequest\": true, \"supportTerminateDebuggee\": true, \"supportSuspendDebuggee\": true, \"supportsDelayedStackTraceLoading\": true, \"supportsLoadedSourcesRequest\": true, \"supportsLogPoints\": true, \"supportsTerminateThreadsRequest\": true, \"supportsSetExpression\": true, \"supportsTerminateRequest\": true, \"supportsDataBreakpoints\": true, \"supportsReadMemoryRequest\": true, \"supportsWriteMemoryRequest\": true, \"supportsDisassembleRequest\": true, \"supportsCancelRequest\": true, \"supportsBreakpointLocationsRequest\": true, \"supportsClipboardContext\": true, \"supportsSteppingGranularity\": true, \"supportsInstructionBreakpoints\": true, \"supportsExceptionFilterOptions\": true, \"supportsSingleThreadExecutionRequests\": true, \"supportsDataBreakpointBytes\": true, \"breakpointModes\": [ { \"mode\": \"hardware\", \"label\": \"Hardware\", \"appliesTo\": [ \"source\", \"instruction\" ] } ], \"supportsANSIStyling\": true } } }",
        "{ \"seq\": 19, \"type\": \"event\", \"event\": \"progressStart\", \"body\": { \"progressId\": \"build\", \"title\": \"Building project\", \"requestId\": 5, \"cancellable\": true, \"message\": \"starting\", \"percentage\": 0 } }",
        "{ \"seq\": 20, \"type\": \"event\", \"event\": \"progressUpdate\", \"body\": { \"progressId\": \"build\", \"message\": \"Compiling...\", \"percentage\": 42 } }",
        "{ \"seq\": 21, \"type\": \"event\", \"event\": \"progressEnd\", \"body\": { \"progressId\": \"build\", \"message\": \"Build complete\" } }",
        "{ \"seq\": 22, \"type\": \"event\", \"event\": \"invalidated\", \"body\": { \"areas\": [ \"threads\", \"stacks\" ], \"threadId\": 1, \"stackFrameId\": 1000 } }",
        "{ \"seq\": 23, \"type\": \"event\", \"event\": \"memory\", \"body\": { \"memoryReference\": \"0x7ffee5a0\", \"offset\": 0, \"count\": 64 } }",
        "{ \"seq\": 24, \"type\": \"event\", \"event\": \"exited\", \"body\": { \"exitCode\": 0 } }",
        "{ \"seq\": 25, \"type\": \"event\", \"event\": \"terminated\", \"body\": { \"restart\": false } }",
    };

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();

    const gpa = debug_allocator.allocator();

    for (data) |sample| {
        const parsed_message_value = try std.json.parseFromSlice(
            std.json.Value,
            gpa,
            sample,
            .{},
        );

        defer parsed_message_value.deinit();

        const parsed_message = try std.json.parseFromValue(
            ProtocolMessage,
            gpa,
            parsed_message_value.value,
            .{
                .ignore_unknown_fields = true,
            },
        );

        defer parsed_message.deinit();

        std.debug.print("{}\n", .{parsed_message.value});
    }
}
