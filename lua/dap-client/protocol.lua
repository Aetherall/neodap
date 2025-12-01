---@meta DebugAdapterProtocol

--[[
-- Debug Adapter Protocol
-- Version: 1.63.3 (approximated based on common features, schema does not explicitly state version)
-- Source: Provided JSON Schema
--
-- The Debug Adapter Protocol defines the protocol used between an editor or IDE and a debugger or runtime.
--]]

--------------------------------------------------------------------------------
-- Aliases for Enums and Specific String Literal Types (namespaced under neodap)
--------------------------------------------------------------------------------

---@alias dap.JsonValue
---| any[] # JSON array
---| boolean # JSON boolean
---| integer # JSON integer
---| nil # JSON null
---| number # JSON number
---| table # JSON object
---| string # JSON string

---@alias dap.ProtocolMessageType
---| "request"
---| "response"
---| "event"

---@alias dap.ResponseMessageStatusEnum
---| "cancelled" # The request was **cancelled**.
---| "notStopped" # The request may be retried once the adapter is in a 'stopped' state.

---@alias dap.StoppedEventReasonEnum
---| "step"
---| "breakpoint"
---| "exception"
---| "pause"
---| "entry"
---| "goto"
---| "function breakpoint"
---| "data breakpoint"
---| "instruction breakpoint"

---@alias dap.ThreadEventReasonEnum
---| "started"
---| "exited"

---@alias dap.OutputEventCategoryEnum
---| "console" # Show the output in the client's default message UI, e.g. a `debug console`. This category should **only** be used for informational output from the debugger (as opposed to the debuggee).
---| "important" # A hint for the client to show the output in the client's UI for important and highly visible information, e.g. as a popup notification. This category should **only** be used for important messages from the debugger (as opposed to the debuggee). Since this category value is a hint, clients *might ignore* the hint and assume the `"console"` category.
---| "stdout" # Show the output as normal program output from the debuggee.
---| "stderr" # Show the output as error program output from the debuggee.
---| "telemetry" # Send the output to telemetry instead of showing it to the user.

---@alias dap.OutputEventGroupEnum
---| "start" # Start a new group in *expanded* mode. Subsequent output events are members of the group and should be shown indented.<br>The `output` attribute becomes the name of the group and is **not** indented.
---| "startCollapsed" # Start a new group in *collapsed* mode. Subsequent output events are members of the group and should be shown indented (as soon as the group is expanded).<br>The `output` attribute becomes the name of the group and is **not** indented.
---| "end" # End the current group and decrease the indentation of subsequent output events.<br>A non-empty `output` attribute is shown as the unindented end of the group.

--- Common reason for modification events (breakpoint, module, loaded source).
---@alias dap.ModificationReasonEnum
---| "changed"
---| "new"
---| "removed"

---@alias dap.ProcessEventStartMethodEnum
---| "launch" # Process was launched under the debugger.
---| "attach" # Debugger attached to an existing process.
---| "attachForSuspendedLaunch" # A project launcher component has launched a new process in a suspended state and then asked the debugger to attach.

--- Logical areas that can be invalidated by the `invalidated` event.
---@alias dap.InvalidatedAreas
---| "all" # **All** previously fetched data has become invalid and needs to be refetched.
---| "stacks" # Previously fetched stack related data has become invalid and needs to be refetched.
---| "threads" # Previously fetched thread related data has become invalid and needs to be refetched.
---| "variables" # Previously fetched variable data has become invalid and needs to be refetched.

---@alias dap.RunInTerminalKindEnum
---| "integrated"
---| "external"

---@alias dap.StartDebuggingRequestEnum
---| "launch"
---| "attach"

---@alias dap.InitializePathFormatEnum
---| "path"
---| "uri"

---@alias dap.VariablesFilterEnum
---| "indexed"
---| "named"

---@alias dap.EvaluateContextEnum
---| "watch" # `evaluate` is called from a watch view context.
---| "repl" # `evaluate` is called from a REPL context.
---| "hover" # `evaluate` is called to generate the debug hover contents.<br>This value should **only** be used if the corresponding capability `supportsEvaluateForHovers` is `true`.
---| "clipboard" # `evaluate` is called to generate clipboard contents.<br>This value should **only** be used if the corresponding capability `supportsClipboardContext` is `true`.
---| "variables" # `evaluate` is called from a variables view context.

---@alias dap.ColumnDescriptorTypeEnum
---| "string"
---| "number"
---| "boolean"
---| "unixTimestampUTC"

---@alias dap.SourcePresentationHintEnum
---| "normal"
---| "emphasize"
---| "deemphasize"

---@alias dap.StackFramePresentationHintEnum
---| "normal"
---| "label"
---| "subtle"

---@alias dap.ScopePresentationHintEnum
---| "arguments" # Scope contains method arguments.
---| "locals" # Scope contains local variables.
---| "registers" # Scope contains registers. **Only a single** `registers` scope should be returned from a `scopes` request.
---| "returnValue" # Scope contains one or more return values.

---@alias dap.VariablePresentationHintKindEnum
---| "property" # Indicates that the object is a property.
---| "method" # Indicates that the object is a method.
---| "class" # Indicates that the object is a class.
---| "data" # Indicates that the object is data.
---| "event" # Indicates that the object is an event.
---| "baseClass" # Indicates that the object is a base class.
---| "innerClass" # Indicates that the object is an inner class.
---| "interface" # Indicates that the object is an interface.
---| "mostDerivedClass" # Indicates that the object is the **most derived** class.
---| "virtual" # Indicates that the object is *virtual*, meaning it's a synthetic object introduced by the adapter for rendering purposes (e.g., an index range for large arrays).
---| "dataBreakpoint" # **Deprecated**: Indicates that a data breakpoint is registered for the object. The `hasDataBreakpoint` attribute should generally be used instead.

---@alias dap.VariablePresentationHintAttributeEnum
---| "static" # Indicates that the object is static.
---| "constant" # Indicates that the object is a constant.
---| "readOnly" # Indicates that the object is read-only.
---| "rawString" # Indicates that the object is a raw string.
---| "hasObjectId" # Indicates that the object can have an Object ID created for it. This is a *vestigial* attribute used by some clients; 'Object ID's are not specified in the protocol.
---| "canHaveObjectId" # Indicates that the object **has** an Object ID associated with it. This is a *vestigial* attribute used by some clients; 'Object ID's are not specified in the protocol.
---| "hasSideEffects" # Indicates that the evaluation had side effects.
---| "hasDataBreakpoint" # Indicates that the object has its value tracked by a data breakpoint.

---@alias dap.VariablePresentationHintVisibilityEnum
---| "public"
---| "private"
---| "protected"
---| "internal"
---| "final"

--- This enumeration defines all possible access types for data breakpoints.
---@alias dap.DataBreakpointAccessType "read"|"write"|"readWrite"

---@alias dap.BreakpointReasonEnum
---| "pending" # Indicates a breakpoint *might* be verified in the future, but the adapter **cannot** verify it in the current state.
---| "failed" # Indicates a breakpoint was **not** able to be verified, and the adapter does not believe it can be verified without intervention.

--- The granularity of one 'step' in the stepping requests `next`, `stepIn`, `stepOut`, and `stepBack`.
---@alias dap.SteppingGranularity
---| "statement" # The step should allow the program to run until the current *statement* has finished executing.<br>The meaning of a statement is determined by the adapter and it may be considered equivalent to a line.<br>For example `'for(int i = 0; i < 10; i++)'` could be considered to have 3 statements: `'int i = 0'`, `'i < 10'`, and `'i++'`.
---| "line" # The step should allow the program to run until the current *source line* has executed.
---| "instruction" # The step should allow *one instruction* to execute (e.g., one x86 instruction).

--- Some predefined types for the CompletionItem. Please note that not all clients have specific icons for all of them.
---@alias dap.CompletionItemType "method"|"function"|"constructor"|"field"|"variable"|"class"|"interface"|"module"|"property"|"unit"|"value"|"enum"|"keyword"|"snippet"|"text"|"color"|"file"|"reference"|"customcolor"

--- Names of checksum algorithms that may be supported by a debug adapter.
---@alias dap.ChecksumAlgorithm "MD5"|"SHA1"|"SHA256"|"timestamp"

--- This enumeration defines all possible conditions when a thrown exception should result in a break.
---@alias dap.ExceptionBreakMode
---| "never" # **Never** breaks.
---| "always" # **Always** breaks.
---| "unhandled" # Breaks when exception is *unhandled*.
---| "userUnhandled" # Breaks if the exception is **not handled by user code**.

---@alias dap.DisassembledInstructionPresentationHintEnum
---| "normal"
---| "invalid" # A value of `invalid` may be used to indicate this instruction is 'filler' and **cannot** be reached by the program. For example, unreadable memory addresses may be presented as `invalid`.

--- Describes one or more type of breakpoint a `dap.BreakpointMode` appliesTo. This is a non-exhaustive enumeration and may expand as future breakpoint types are added.
---@alias dap.BreakpointModeApplicability
---| "source" # In `dap.SourceBreakpoint`s
---| "exception" # In exception breakpoints applied in the `dap.ExceptionFilterOptions`
---| "data" # In data breakpoints requested in the `dap.DataBreakpointInfoRequest`
---| "instruction" # In `dap.InstructionBreakpoint`s

--------------------------------------------------------------------------------
-- Base Protocol Definitions
--------------------------------------------------------------------------------

--- Base class of requests, responses, and events.
--(Title: Base Protocol)
---@class dap.ProtocolMessage
---@field seq integer Sequence number of the message (also known as message ID). The `seq` for the **first** message sent by a client or debug adapter is `1`, and for each subsequent message is `1` greater than the previous message sent by that actor. `seq` can be used to order requests, responses, and events, and to associate requests with their corresponding responses. For protocol messages of type `request` the sequence number can be used to **cancel** the request.
---@field type dap.ProtocolMessageType Message type.

--- A client or debug adapter initiated request.
---@class dap.Request : dap.ProtocolMessage
---@field type "request" # Message type, overridden from `dap.ProtocolMessage`.
---@field command string The command to execute.
---@field arguments? dap.JsonValue Object containing arguments for the command. (Specific requests will use concrete argument types)

--- A debug adapter initiated event.
---@class dap.Event : dap.ProtocolMessage
---@field type "event" # Message type, overridden from `dap.ProtocolMessage`.
---@field event string Type of event.
---@field body? dap.JsonValue Event-specific information. (Specific events will use concrete body types)

--- Response for a request.
---@class dap.Response : dap.ProtocolMessage
---@field type "response" # Message type, overridden from `dap.ProtocolMessage`.
---@field request_seq integer Sequence number of the corresponding request.
---@field success boolean Outcome of the request.<br>If `true`, the request was successful and the `body` attribute *may* contain the result of the request.<br>If the value is `false`, the attribute `message` contains the error in short form and the `body` *may* contain additional information (see `dap.ErrorResponse.body.error`).
---@field command string The command requested.
---@field message? dap.ResponseMessageStatusEnum Contains the raw error in short form if `success` is `false`.<br>This raw error *might* be interpreted by the client and is **not** shown in the UI.<br>Some predefined values exist.
---@field body? dap.JsonValue Contains request result if `success` is `true` and error details if `success` is `false`. (Specific responses will use concrete body types)

--- A structured message object. Used to return errors from requests.
---@class dap.Message
---@field id integer Unique (within a debug adapter implementation) identifier for the message. The purpose of these error IDs is to help extension authors that have the requirement that every user-visible error message needs a corresponding error number, so that users or customer support can find information about the specific error more easily.
---@field format string A format string for the message. Embedded variables have the form `{name}`.<br>If a variable name starts with an underscore character (`_`), the variable does **not** contain user data (PII) and can be safely used for telemetry purposes.
---@field variables? table<string, string?> An object used as a dictionary for looking up the variables in the `format` string.<br>All dictionary values **must be strings** (per DAP spec), but indexing returns nil for missing keys (per Lua semantics).
---@field sendTelemetry? boolean If `true`, send to telemetry.
---@field showUser? boolean If `true`, show to user.
---@field url? string A URL where additional information about this message can be found.
---@field urlLabel? string A label that is presented to the user as the UI for opening the `url`.

---@class dap.ErrorResponseBody
---@field error? dap.Message A structured error message.

--- On error (whenever `success` is `false`), the `body` can provide more details.
---@class dap.ErrorResponse : dap.Response
---@field body dap.ErrorResponseBody # Overrides/specifies the `body` from `dap.Response`.

--------------------------------------------------------------------------------
-- Initialization and Configuration
--------------------------------------------------------------------------------

--- Arguments for `initialize` request.
---@class dap.InitializeRequestArguments
---@field adapterID string The ID of the debug adapter.
---@field clientID? string The ID of the client using this adapter.
---@field clientName? string The human-readable name of the client using this adapter.
---@field locale? string The ISO-639 locale of the client using this adapter (e.g., `en-US` or `de-CH`).
---@field linesStartAt1? boolean If `true`, all line numbers are 1-based (default).
---@field columnsStartAt1? boolean If `true`, all column numbers are 1-based (default).
---@field pathFormat? dap.InitializePathFormatEnum Determines in what format paths are specified. The default is `"path"`, which is the native format.
---@field supportsVariableType? boolean Client supports the `type` attribute for variables.
---@field supportsVariablePaging? boolean Client supports the paging of variables.
---@field supportsRunInTerminalRequest? boolean Client supports the `runInTerminal` request.
---@field supportsMemoryReferences? boolean Client supports memory references.
---@field supportsProgressReporting? boolean Client supports progress reporting.
---@field supportsInvalidatedEvent? boolean Client supports the `invalidated` event.
---@field supportsMemoryEvent? boolean Client supports the `memory` event.
---@field supportsArgsCanBeInterpretedByShell? boolean Client supports the `argsCanBeInterpretedByShell` attribute on the `runInTerminal` request.
---@field supportsStartDebuggingRequest? boolean Client supports the `startDebugging` request.
---@field supportsANSIStyling? boolean The client will interpret ANSI escape sequences in the display of `dap.OutputEventBody.output` and `dap.Variable.value` fields when `dap.Capabilities.supportsANSIStyling` is also enabled.

--- The `initialize` request is sent as the **first request** from the client to the debug adapter to configure it with client capabilities and to retrieve capabilities from the debug adapter.
--- **Until** the debug adapter has responded with an `initialize` response, the client **must not** send any additional requests or events to the debug adapter.
--- In addition, the debug adapter is **not allowed** to send any requests or events to the client until it has responded with an `initialize` response.
--- The `initialize` request *may only be sent once*.
--- (Title: Requests)
---@class dap.InitializeRequest : dap.Request
---@field command "initialize" # The command to execute.
---@field arguments dap.InitializeRequestArguments # Arguments for `initialize` request.

--- Information about the **capabilities of a debug adapter**.
--- (Title: Types)
---@class dap.Capabilities
---@field supportsConfigurationDoneRequest? boolean The debug adapter supports the `configurationDone` request.
---@field supportsFunctionBreakpoints? boolean The debug adapter supports function breakpoints.
---@field supportsConditionalBreakpoints? boolean The debug adapter supports conditional breakpoints.
---@field supportsHitConditionalBreakpoints? boolean The debug adapter supports breakpoints that break execution after a specified number of hits.
---@field supportsEvaluateForHovers? boolean The debug adapter supports a (side effect free) `evaluate` request for data hovers.
---@field exceptionBreakpointFilters? dap.ExceptionBreakpointsFilter[] Available exception filter options for the `setExceptionBreakpoints` request.
---@field supportsStepBack? boolean The debug adapter supports stepping back via the `stepBack` and `reverseContinue` requests.
---@field supportsSetVariable? boolean The debug adapter supports setting a variable to a value.
---@field supportsRestartFrame? boolean The debug adapter supports restarting a frame.
---@field supportsGotoTargetsRequest? boolean The debug adapter supports the `gotoTargets` request.
---@field supportsStepInTargetsRequest? boolean The debug adapter supports the `stepInTargets` request.
---@field supportsCompletionsRequest? boolean The debug adapter supports the `completions` request.
---@field completionTriggerCharacters? string[] The set of characters that should trigger completion in a REPL. If not specified, the UI should assume the `.` character.
---@field supportsModulesRequest? boolean The debug adapter supports the `modules` request.
---@field additionalModuleColumns? dap.ColumnDescriptor[] The set of additional module information exposed by the debug adapter.
---@field supportedChecksumAlgorithms? dap.ChecksumAlgorithm[] Checksum algorithms supported by the debug adapter.
---@field supportsRestartRequest? boolean The debug adapter supports the `restart` request. In this case, a client should **not** implement `restart` by terminating and relaunching the adapter but by calling the `restart` request.
---@field supportsExceptionOptions? boolean The debug adapter supports `exceptionOptions` on the `setExceptionBreakpoints` request.
---@field supportsValueFormattingOptions? boolean The debug adapter supports a `format` attribute on the `stackTrace`, `variables`, and `evaluate` requests.
---@field supportsExceptionInfoRequest? boolean The debug adapter supports the `exceptionInfo` request.
---@field supportTerminateDebuggee? boolean The debug adapter supports the `terminateDebuggee` attribute on the `disconnect` request.
---@field supportSuspendDebuggee? boolean The debug adapter supports the `suspendDebuggee` attribute on the `disconnect` request.
---@field supportsDelayedStackTraceLoading? boolean The debug adapter supports the *delayed loading* of parts of the stack, which requires that both the `startFrame` and `levels` arguments and the `totalFrames` result of the `stackTrace` request are supported.
---@field supportsLoadedSourcesRequest? boolean The debug adapter supports the `loadedSources` request.
---@field supportsLogPoints? boolean The debug adapter supports log points by interpreting the `logMessage` attribute of the `dap.SourceBreakpoint`.
---@field supportsTerminateThreadsRequest? boolean The debug adapter supports the `terminateThreads` request.
---@field supportsSetExpression? boolean The debug adapter supports the `setExpression` request.
---@field supportsTerminateRequest? boolean The debug adapter supports the `terminate` request.
---@field supportsDataBreakpoints? boolean The debug adapter supports data breakpoints.
---@field supportsReadMemoryRequest? boolean The debug adapter supports the `readMemory` request.
---@field supportsWriteMemoryRequest? boolean The debug adapter supports the `writeMemory` request.
---@field supportsDisassembleRequest? boolean The debug adapter supports the `disassemble` request.
---@field supportsCancelRequest? boolean The debug adapter supports the `cancel` request.
---@field supportsBreakpointLocationsRequest? boolean The debug adapter supports the `breakpointLocations` request.
---@field supportsClipboardContext? boolean The debug adapter supports the `"clipboard"` context value in the `evaluate` request.
---@field supportsSteppingGranularity? boolean The debug adapter supports stepping granularities (argument `granularity`) for the stepping requests.
---@field supportsInstructionBreakpoints? boolean The debug adapter supports adding breakpoints based on instruction references.
---@field supportsExceptionFilterOptions? boolean The debug adapter supports `filterOptions` as an argument on the `setExceptionBreakpoints` request.
---@field supportsSingleThreadExecutionRequests? boolean The debug adapter supports the `singleThread` property on the execution requests (`continue`, `next`, `stepIn`, `stepOut`, `reverseContinue`, `stepBack`).
---@field supportsDataBreakpointBytes? boolean The debug adapter supports the `asAddress` and `bytes` fields in the `dataBreakpointInfo` request.
---@field breakpointModes? dap.BreakpointMode[] Modes of breakpoints supported by the debug adapter, such as `'hardware'` or `'software'`. If present, the client *may* allow the user to select a mode and include it in its `setBreakpoints` request.<br><br>Clients *may* present the first applicable mode in this array as the 'default' mode in gestures that set breakpoints.
---@field supportsANSIStyling? boolean The debug adapter supports ANSI escape sequences in styling of `dap.OutputEventBody.output` and `dap.Variable.value` fields.

--- Response to `initialize` request.
---@class dap.InitializeResponse : dap.Response
---@field body? dap.Capabilities # The capabilities of this debug adapter.

--- This event indicates that the debug adapter is **ready to accept configuration requests** (e.g., `setBreakpoints`, `setExceptionBreakpoints`).
--- A debug adapter is expected to send this event when it is ready to accept configuration requests (but **not before** the `initialize` request has finished).
--- The sequence of events/requests is as follows:
--- - Adapter sends `initialized` event (after the `initialize` request has returned).
--- - Client sends zero or more `setBreakpoints` requests.
--- - Client sends one `setFunctionBreakpoints` request (if corresponding capability `supportsFunctionBreakpoints` is `true`).
--- - Client sends a `setExceptionBreakpoints` request if one or more `exceptionBreakpointFilters` have been defined (or if `supportsConfigurationDoneRequest` is **not** `true`).
--- - Client sends other future configuration requests.
--- - Client sends one `configurationDone` request to indicate the end of the configuration.
--- (Title: Events)
---@class dap.InitializedEvent : dap.Event
---@field event "initialized" # Type of event.
---@field body? any # No body defined in schema for InitializedEvent, but Event base class allows it.

--- Arguments for `configurationDone` request.
---@class dap.ConfigurationDoneArguments -- This class has no properties defined in the schema.

--- This request indicates that the client has **finished initialization** of the debug adapter.
--- So it is the *last request* in the sequence of configuration requests (which was started by the `initialized` event).
--- Clients should **only** call this request if the corresponding capability `supportsConfigurationDoneRequest` is `true`.
---@class dap.ConfigurationDoneRequest : dap.Request
---@field command "configurationDone" # The command to execute.
---@field arguments? dap.ConfigurationDoneArguments # Arguments for `configurationDone` request.

--- Response to `configurationDone` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.ConfigurationDoneResponse : dap.Response

--------------------------------------------------------------------------------
-- Launching and Attaching
--------------------------------------------------------------------------------

--- Arguments for `launch` request. Additional attributes are implementation specific.
---@class dap.LaunchRequestArguments
---@field noDebug? boolean If `true`, the `launch` request should launch the program **without enabling debugging**.
---@field __restart? dap.JsonValue Arbitrary data from the previous, *restarted* session.<br>The data is sent as the `restart` attribute of the `terminated` event.<br>The client should leave the data *intact*.
---@field [string] any # Allows other properties, implementation specific.

--- This `launch` request is sent from the client to the debug adapter to **start the debuggee** with or without debugging (if `noDebug` is `true`).
--- Since launching is debugger/runtime specific, the arguments for this request are **not part of this specification**.
---@class dap.LaunchRequest : dap.Request
---@field command "launch" # The command to execute.
---@field arguments dap.LaunchRequestArguments # Arguments for `launch` request.

--- Response to `launch` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.LaunchResponse : dap.Response

--- Arguments for `attach` request. Additional attributes are implementation specific.
---@class dap.AttachRequestArguments
---@field __restart? dap.JsonValue Arbitrary data from the previous, *restarted* session.<br>The data is sent as the `restart` attribute of the `terminated` event.<br>The client should leave the data *intact*.
---@field [string] any # Allows other properties, implementation specific.

--- The `attach` request is sent from the client to the debug adapter to **attach to a debuggee that is already running**.
--- Since attaching is debugger/runtime specific, the arguments for this request are **not part of this specification**.
---@class dap.AttachRequest : dap.Request
---@field command "attach" # The command to execute.
---@field arguments dap.AttachRequestArguments # Arguments for `attach` request.

--- Response to `attach` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.AttachResponse : dap.Response

--------------------------------------------------------------------------------
-- Session Lifecycle (Restart, Disconnect, Terminate)
--------------------------------------------------------------------------------

--- Arguments for `restart` request.
---@class dap.RestartArguments
---@field arguments? dap.LaunchRequestArguments|dap.AttachRequestArguments The latest version of the `launch` or `attach` configuration.

--- **Restarts a debug session**. Clients should **only** call this request if the corresponding capability `supportsRestartRequest` is `true`.
--- If the capability is missing or has the value `false`, a typical client *emulates* `restart` by terminating the debug adapter first and then launching it anew.
---@class dap.RestartRequest : dap.Request
---@field command "restart" # The command to execute.
---@field arguments? dap.RestartArguments # Arguments for `restart` request.

--- Response to `restart` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.RestartResponse : dap.Response

--- Arguments for `disconnect` request.
---@class dap.DisconnectArguments
---@field restart? boolean A value of `true` indicates that this `disconnect` request is part of a *restart sequence*.
---@field terminateDebuggee? boolean Indicates whether the debuggee should be **terminated** when the debugger is disconnected.<br>If unspecified, the debug adapter is free to do whatever it thinks is best.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportTerminateDebuggee` is `true`.
---@field suspendDebuggee? boolean Indicates whether the debuggee should stay **suspended** when the debugger is disconnected.<br>If unspecified, the debuggee should resume execution.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportSuspendDebuggee` is `true`.

--- The `disconnect` request asks the debug adapter to **disconnect from the debuggee** (thus ending the debug session) and then to **shut down itself** (the debug adapter).
--- In addition, the debug adapter **must terminate the debuggee** if it was started with the `launch` request. If an `attach` request was used to connect to the debuggee, then the debug adapter **must not** terminate the debuggee.
--- This implicit behavior of when to terminate the debuggee can be overridden with the `terminateDebuggee` argument (which is **only** supported by a debug adapter if the corresponding capability `supportTerminateDebuggee` is `true`).
---@class dap.DisconnectRequest : dap.Request
---@field command "disconnect" # The command to execute.
---@field arguments? dap.DisconnectArguments # Arguments for `disconnect` request.

--- Response to `disconnect` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.DisconnectResponse : dap.Response

--- Arguments for `terminate` request.
---@class dap.TerminateArguments
---@field restart? boolean A value of `true` indicates that this `terminate` request is part of a *restart sequence*.

--- The `terminate` request is sent from the client to the debug adapter in order to **shut down the debuggee gracefully**. Clients should **only** call this request if the capability `supportsTerminateRequest` is `true`.
--- Typically, a debug adapter implements `terminate` by sending a software signal which the debuggee intercepts in order to clean things up properly before terminating itself.
--- **Please note** that this request does **not directly affect** the state of the debug session: if the debuggee decides to *veto* the graceful shutdown for any reason by not terminating itself, then the debug session just *continues*.
--- Clients can surface the `terminate` request as an explicit command or they can integrate it into a two-stage `Stop` command that first sends `terminate` to request a graceful shutdown, and if that fails, uses `disconnect` for a forceful shutdown.
---@class dap.TerminateRequest : dap.Request
---@field command "terminate" # The command to execute.
---@field arguments? dap.TerminateArguments # Arguments for `terminate` request.

--- Response to `terminate` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.TerminateResponse : dap.Response

---@class dap.TerminatedEventBody
---@field restart? dap.JsonValue A debug adapter *may* set `restart` to `true` (or to an arbitrary object) to request that the client **restarts the session**.<br>The value is **not interpreted** by the client and passed *unmodified* as an attribute `__restart` to the `launch` and `attach` requests.

--- The event indicates that debugging of the debuggee has **terminated**. This does **not** mean that the debuggee itself has exited.
---@class dap.TerminatedEvent : dap.Event
---@field event "terminated" # Type of event.
---@field body? dap.TerminatedEventBody # Event-specific information.

---@class dap.ExitedEventBody
---@field exitCode integer The exit code returned from the debuggee.

--- The event indicates that the debuggee has **exited** and returns its exit code.
---@class dap.ExitedEvent : dap.Event
---@field event "exited" # Type of event.
---@field body dap.ExitedEventBody # Event-specific information.

--------------------------------------------------------------------------------
-- Cancel Request
--------------------------------------------------------------------------------

--- Arguments for `cancel` request.
---@class dap.CancelArguments
---@field requestId? integer The ID (attribute `seq`) of the request to cancel. If missing, **no request is cancelled**.<br>Both a `requestId` and a `progressId` can be specified in one request.
---@field progressId? string The ID (attribute `progressId`) of the progress to cancel. If missing, **no progress is cancelled**.<br>Both a `requestId` and a `progressId` can be specified in one request.

--- The `cancel` request is used by the client in **two** situations:
--- - To indicate that it is **no longer interested** in the result produced by a specific request issued earlier.
--- - To **cancel a progress sequence**.
--- Clients should **only** call this request if the corresponding capability `supportsCancelRequest` is `true`.
--- This request has a *hint* characteristic: a debug adapter can **only** be expected to make a 'best effort' in honoring this request, but there are **no guarantees**.
--- The `cancel` request *may* return an error if it could not cancel an operation, but a client should **refrain** from presenting this error to end users.
--- The request that got cancelled **still needs to send a response back**. This can either be a normal result (`success` attribute `true`) or an error response (`success` attribute `false` and the `message` set to `"cancelled"`).
--- Returning *partial results* from a cancelled request is possible, but please note that a client has **no generic way** for detecting that a response is partial or not.
--- The progress that got cancelled **still needs to send a `progressEnd` event back**.
--- A client should **not assume** that progress just got cancelled after sending the `cancel` request.
---@class dap.CancelRequest : dap.Request
---@field command "cancel" # The command to execute.
---@field arguments? dap.CancelArguments # Arguments for `cancel` request.

--- Response to `cancel` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.CancelResponse : dap.Response

--------------------------------------------------------------------------------
-- Breakpoint Management
--------------------------------------------------------------------------------

--- Properties of a breakpoint location returned from the `breakpointLocations` request.
---@class dap.BreakpointLocation
---@field line integer Start line of breakpoint location.
---@field column? integer The start position of a breakpoint location. Position is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field endLine? integer The end line of breakpoint location if the location covers a range.
---@field endColumn? integer The end position of a breakpoint location (if the location covers a range). Position is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.

--- Arguments for `breakpointLocations` request.
---@class dap.BreakpointLocationsArguments
---@field source dap.Source The source location of the breakpoints; either `source.path` or `source.sourceReference` **must be specified**.
---@field line integer Start line of range to search possible breakpoint locations in. If **only** the line is specified, the request returns all possible locations in that line.
---@field column? integer Start position within `line` to search possible breakpoint locations in. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based. If no column is given, the first position in the start line is assumed.
---@field endLine? integer End line of range to search possible breakpoint locations in. If no end line is given, then the end line is assumed to be the start line.
---@field endColumn? integer End position within `endLine` to search possible breakpoint locations in. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based. If no end column is given, the last position in the end line is assumed.

--- The `breakpointLocations` request returns **all possible locations for source breakpoints** in a given range.
--- Clients should **only** call this request if the corresponding capability `supportsBreakpointLocationsRequest` is `true`.
---@class dap.BreakpointLocationsRequest : dap.Request
---@field command "breakpointLocations" # The command to execute.
---@field arguments dap.BreakpointLocationsArguments # Arguments for `breakpointLocations` request. Changed from optional as schema has it required for command

---@class dap.BreakpointLocationsResponseBody
---@field breakpoints dap.BreakpointLocation[] *Sorted set* of possible breakpoint locations.

--- Response to `breakpointLocations` request.
--- Contains possible locations for source breakpoints.
---@class dap.BreakpointLocationsResponse : dap.Response
---@field body dap.BreakpointLocationsResponseBody # Response body.

--- Properties of a breakpoint or logpoint passed to the `setBreakpoints` request.
---@class dap.SourceBreakpoint
---@field line integer The source line of the breakpoint or logpoint.
---@field column? integer Start position within source line of the breakpoint or logpoint. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field condition? string The expression for conditional breakpoints.<br>It is **only honored** by a debug adapter if the corresponding capability `supportsConditionalBreakpoints` is `true`.
---@field hitCondition? string The expression that controls how many hits of the breakpoint are ignored.<br>The debug adapter is expected to interpret the expression as needed.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsHitConditionalBreakpoints` is `true`.<br>If both this property and `condition` are specified, `hitCondition` should be evaluated **only if** the `condition` is met, and the debug adapter should stop **only if both** conditions are met.
---@field logMessage? string If this attribute exists and is non-empty, the debug adapter **must not 'break'** (stop)<br>but log the message instead. Expressions within `{}` are interpolated.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsLogPoints` is `true`.<br>If either `hitCondition` or `condition` is specified, then the message should **only be logged** if those conditions are met.
---@field mode? string The mode of this breakpoint. If defined, this **must be one** of the `breakpointModes` the debug adapter advertised in its `dap.Capabilities`.

--- Arguments for `setBreakpoints` request.
---@class dap.SetBreakpointsArguments
---@field source dap.Source The source location of the breakpoints; either `source.path` or `source.sourceReference` **must be specified**.
---@field breakpoints? dap.SourceBreakpoint[] The code locations of the breakpoints.
---@field lines? integer[] **Deprecated**: The code locations of the breakpoints.
---@field sourceModified? boolean A value of `true` indicates that the underlying source has been *modified*, which results in new breakpoint locations.

--- Sets **multiple breakpoints** for a single source and **clears all previous breakpoints** in that source.
--- To clear all breakpoints for a source, specify an *empty array*.
--- When a breakpoint is hit, a `stopped` event (with reason `"breakpoint"`) is generated.
---@class dap.SetBreakpointsRequest : dap.Request
---@field command "setBreakpoints" # The command to execute.
---@field arguments dap.SetBreakpointsArguments # Arguments for `setBreakpoints` request.

--- Information about a breakpoint created in `setBreakpoints`, `setFunctionBreakpoints`, `setInstructionBreakpoints`, or `setDataBreakpoints` requests.
---@class dap.Breakpoint
---@field verified boolean If `true`, the breakpoint could be set (but **not necessarily** at the desired location).
---@field id? integer The identifier for the breakpoint. It is needed if breakpoint events are used to update or remove breakpoints.
---@field message? string A message about the state of the breakpoint.<br>This is shown to the user and can be used to explain why a breakpoint could not be verified.
---@field source? dap.Source The source where the breakpoint is located.
---@field line? integer The start line of the actual range covered by the breakpoint.
---@field column? integer Start position of the source range covered by the breakpoint. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field endLine? integer The end line of the actual range covered by the breakpoint.
---@field endColumn? integer End position of the source range covered by the breakpoint. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.<br>If no end line is given, then the end column is assumed to be in the start line.
---@field instructionReference? string A memory reference to where the breakpoint is set.
---@field offset? integer The offset from the instruction reference.<br>This can be negative.
---@field reason? dap.BreakpointReasonEnum A machine-readable explanation of why a breakpoint *may not be verified*. If a breakpoint is verified or a specific reason is not known, the adapter should **omit** this property.

---@class dap.SetBreakpointsResponseBody
---@field breakpoints dap.Breakpoint[] Information about the breakpoints.<br>The array elements are in the **same order** as the elements of the `breakpoints` (or the deprecated `lines`) array in the arguments.

--- Response to `setBreakpoints` request.
--- Returned is information about each breakpoint created by this request.
--- This includes the *actual code location* and whether the breakpoint could be *verified*.
--- The breakpoints returned are in the **same order** as the elements of the `breakpoints` (or the deprecated `lines`) array in the arguments.
---@class dap.SetBreakpointsResponse : dap.Response
---@field body dap.SetBreakpointsResponseBody # Response body.

--- Properties of a breakpoint passed to the `setFunctionBreakpoints` request.
---@class dap.FunctionBreakpoint
---@field name string The name of the function.
---@field condition? string An expression for conditional breakpoints.<br>It is **only honored** by a debug adapter if the corresponding capability `supportsConditionalBreakpoints` is `true`.
---@field hitCondition? string An expression that controls how many hits of the breakpoint are ignored.<br>The debug adapter is expected to interpret the expression as needed.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsHitConditionalBreakpoints` is `true`.

--- Arguments for `setFunctionBreakpoints` request.
---@class dap.SetFunctionBreakpointsArguments
---@field breakpoints dap.FunctionBreakpoint[] The function names of the breakpoints.

--- **Replaces all existing function breakpoints** with new function breakpoints.
--- To clear all function breakpoints, specify an *empty array*.
--- When a function breakpoint is hit, a `stopped` event (with reason `"function breakpoint"`) is generated.
--- Clients should **only** call this request if the corresponding capability `supportsFunctionBreakpoints` is `true`.
---@class dap.SetFunctionBreakpointsRequest : dap.Request
---@field command "setFunctionBreakpoints" # The command to execute.
---@field arguments dap.SetFunctionBreakpointsArguments # Arguments for `setFunctionBreakpoints` request.

---@class dap.SetFunctionBreakpointsResponseBody
---@field breakpoints dap.Breakpoint[] Information about the breakpoints. The array elements correspond to the elements of the `breakpoints` array.

--- Response to `setFunctionBreakpoints` request.
--- Returned is information about each breakpoint created by this request.
---@class dap.SetFunctionBreakpointsResponse : dap.Response
---@field body dap.SetFunctionBreakpointsResponseBody # Response body.

--- Arguments for `setExceptionBreakpoints` request.
---@class dap.SetExceptionBreakpointsArguments
---@field filters string[] Set of exception filters specified by their ID. The set of all possible exception filters is defined by the `exceptionBreakpointFilters` capability. The `filter` and `filterOptions` sets are *additive*.
---@field filterOptions? dap.ExceptionFilterOptions[] Set of exception filters and their options. The set of all possible exception filters is defined by the `exceptionBreakpointFilters` capability. This attribute is **only honored** by a debug adapter if the corresponding capability `supportsExceptionFilterOptions` is `true`. The `filter` and `filterOptions` sets are *additive*.
---@field exceptionOptions? dap.ExceptionOptions[] Configuration options for selected exceptions.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsExceptionOptions` is `true`.

--- The request configures the debugger's response to **thrown exceptions**. Each of the `filters`, `filterOptions`, and `exceptionOptions` in the request are *independent configurations* to a debug adapter indicating a kind of exception to catch. An exception thrown in a program should result in a `stopped` event from the debug adapter (with reason `"exception"`) if **any** of the configured filters match.
--- Clients should **only** call this request if the corresponding capability `exceptionBreakpointFilters` returns one or more filters.
---@class dap.SetExceptionBreakpointsRequest : dap.Request
---@field command "setExceptionBreakpoints" # The command to execute.
---@field arguments dap.SetExceptionBreakpointsArguments # Arguments for `setExceptionBreakpoints` request.

---@class dap.SetExceptionBreakpointsResponseBody
---@field breakpoints? dap.Breakpoint[] Information about the exception breakpoints or filters.<br>The breakpoints returned are in the **same order** as the elements of the `filters`, `filterOptions`, `exceptionOptions` arrays in the arguments. If both `filters` and `filterOptions` are given, the returned array **must start** with `filters` information first, followed by `filterOptions` information.

--- Response to `setExceptionBreakpoints` request.
--- The response contains an array of `dap.Breakpoint` objects with information about each exception breakpoint or filter. The `dap.Breakpoint` objects are in the **same order** as the elements of the `filters`, `filterOptions`, `exceptionOptions` arrays given as arguments. If both `filters` and `filterOptions` are given, the returned array **must start** with `filters` information first, followed by `filterOptions` information.
--- The `verified` property of a `dap.Breakpoint` object signals whether the exception breakpoint or filter could be successfully created and whether the condition is valid. In case of an error, the `message` property explains the problem. The `id` property can be used to introduce a unique ID for the exception breakpoint or filter so that it can be updated subsequently by sending breakpoint events.
--- For **backward compatibility**, both the `breakpoints` array and the enclosing `body` are *optional*. If these elements are missing, a client is **not able to** show problems for individual exception breakpoints or filters.
---@class dap.SetExceptionBreakpointsResponse : dap.Response
---@field body? dap.SetExceptionBreakpointsResponseBody # Response body.

--- Arguments for `dataBreakpointInfo` request.
---@class dap.DataBreakpointInfoArguments
---@field name string The name of the variable's child to obtain data breakpoint information for.<br>If `variablesReference` isn't specified, this can be an expression, or an address if `asAddress` is also `true`.
---@field variablesReference? integer Reference to the variable container if the data breakpoint is requested for a child of the container. The `variablesReference` **must** have been obtained in the current suspended state. See 'Lifetime of Object References' in the Overview section for details.
---@field frameId? integer When `name` is an expression, evaluate it in the scope of this stack frame. If not specified, the expression is evaluated in the global scope. When `variablesReference` is specified, this property has **no effect**.
---@field bytes? integer If specified, a debug adapter should return information for the range of memory extending `bytes` number of bytes from the address or variable specified by `name`. Breakpoints set using the resulting data ID should pause on data access *anywhere within that range*.<br><br>Clients *may* set this property **only if** the `supportsDataBreakpointBytes` capability is `true`.
---@field asAddress? boolean If `true`, the `name` is a memory address and the debugger should interpret it as a decimal value, or hex value if it is prefixed with `0x`.<br><br>Clients *may* set this property **only if** the `supportsDataBreakpointBytes` capability is `true`.
---@field mode? string The mode of the desired breakpoint. If defined, this **must be one** of the `breakpointModes` the debug adapter advertised in its `dap.Capabilities`.

--- Obtains information on a **possible data breakpoint** that could be set on an expression or variable.
--- Clients should **only** call this request if the corresponding capability `supportsDataBreakpoints` is `true`.
---@class dap.DataBreakpointInfoRequest : dap.Request
---@field command "dataBreakpointInfo" # The command to execute.
---@field arguments dap.DataBreakpointInfoArguments # Arguments for `dataBreakpointInfo` request.

---@class dap.DataBreakpointInfoResponseBody
---@field dataId string|nil An identifier for the data on which a data breakpoint can be registered with the `setDataBreakpoints` request, or `nil` if no data breakpoint is available. If a `variablesReference` or `frameId` is passed, the `dataId` is valid in the *current suspended state*; otherwise, it's valid *indefinitely*. See 'Lifetime of Object References' in the Overview section for details. Breakpoints set using the `dataId` in the `setDataBreakpoints` request *may outlive* the lifetime of the associated `dataId`.
---@field description string UI string that describes on what data the breakpoint is set on or why a data breakpoint is not available.
---@field accessTypes? dap.DataBreakpointAccessType[] Attribute lists the *available access types* for a potential data breakpoint. A UI client could surface this information.
---@field canPersist? boolean Attribute indicates that a potential data breakpoint could be *persisted across sessions*.

--- Response to `dataBreakpointInfo` request.
---@class dap.DataBreakpointInfoResponse : dap.Response
---@field body dap.DataBreakpointInfoResponseBody # Response body.

--- Properties of a data breakpoint passed to the `setDataBreakpoints` request.
---@class dap.DataBreakpoint
---@field dataId string An ID representing the data. This ID is returned from the `dataBreakpointInfo` request.
---@field accessType? dap.DataBreakpointAccessType The access type of the data.
---@field condition? string An expression for conditional breakpoints.
---@field hitCondition? string An expression that controls how many hits of the breakpoint are ignored.<br>The debug adapter is expected to interpret the expression as needed.

--- Arguments for `setDataBreakpoints` request.
---@class dap.SetDataBreakpointsArguments
---@field breakpoints dap.DataBreakpoint[] The contents of this array **replaces all existing data breakpoints**. An *empty array* clears all data breakpoints.

--- **Replaces all existing data breakpoints** with new data breakpoints.
--- To clear all data breakpoints, specify an *empty array*.
--- When a data breakpoint is hit, a `stopped` event (with reason `"data breakpoint"`) is generated.
--- Clients should **only** call this request if the corresponding capability `supportsDataBreakpoints` is `true`.
---@class dap.SetDataBreakpointsRequest : dap.Request
---@field command "setDataBreakpoints" # The command to execute.
---@field arguments dap.SetDataBreakpointsArguments # Arguments for `setDataBreakpoints` request.

---@class dap.SetDataBreakpointsResponseBody
---@field breakpoints dap.Breakpoint[] Information about the data breakpoints. The array elements correspond to the elements of the input argument `breakpoints` array.

--- Response to `setDataBreakpoints` request.
--- Returned is information about each breakpoint created by this request.
---@class dap.SetDataBreakpointsResponse : dap.Response
---@field body dap.SetDataBreakpointsResponseBody # Response body.

--- Properties of a breakpoint passed to the `setInstructionBreakpoints` request.
---@class dap.InstructionBreakpoint
---@field instructionReference string The instruction reference of the breakpoint.<br>This should be a memory or instruction pointer reference from an `dap.EvaluateResponse`, `dap.Variable`, `dap.StackFrame`, `dap.GotoTarget`, or `dap.Breakpoint`.
---@field offset? integer The offset from the instruction reference in bytes.<br>This can be negative.
---@field condition? string An expression for conditional breakpoints.<br>It is **only honored** by a debug adapter if the corresponding capability `supportsConditionalBreakpoints` is `true`.
---@field hitCondition? string An expression that controls how many hits of the breakpoint are ignored.<br>The debug adapter is expected to interpret the expression as needed.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsHitConditionalBreakpoints` is `true`.
---@field mode? string The mode of this breakpoint. If defined, this **must be one** of the `breakpointModes` the debug adapter advertised in its `dap.Capabilities`.

--- Arguments for `setInstructionBreakpoints` request
---@class dap.SetInstructionBreakpointsArguments
---@field breakpoints dap.InstructionBreakpoint[] The instruction references of the breakpoints

--- **Replaces all existing instruction breakpoints**. Typically, instruction breakpoints would be set from a disassembly window.
--- To clear all instruction breakpoints, specify an *empty array*.
--- When an instruction breakpoint is hit, a `stopped` event (with reason `"instruction breakpoint"`) is generated.
--- Clients should **only** call this request if the corresponding capability `supportsInstructionBreakpoints` is `true`.
---@class dap.SetInstructionBreakpointsRequest : dap.Request
---@field command "setInstructionBreakpoints" # The command to execute.
---@field arguments dap.SetInstructionBreakpointsArguments # Arguments for `setInstructionBreakpoints` request

---@class dap.SetInstructionBreakpointsResponseBody
---@field breakpoints dap.Breakpoint[] Information about the breakpoints. The array elements correspond to the elements of the `breakpoints` array.

--- Response to `setInstructionBreakpoints` request
---@class dap.SetInstructionBreakpointsResponse : dap.Response
---@field body dap.SetInstructionBreakpointsResponseBody # Response body.

---@class dap.BreakpointEventBody
---@field reason dap.ModificationReasonEnum The reason for the event.
---@field breakpoint dap.Breakpoint The `id` attribute is used to find the target breakpoint; the other attributes are used as the new values.

--- The event indicates that some information about a **breakpoint has changed**.
---@class dap.BreakpointEvent : dap.Event
---@field event "breakpoint" # Type of event.
---@field body dap.BreakpointEventBody # Event-specific information.

--- A `BreakpointMode` is provided as an option when setting breakpoints on sources or instructions.
---@class dap.BreakpointMode
---@field mode string The internal ID of the mode. This value is passed to the `setBreakpoints` request.
---@field label string The name of the breakpoint mode. This is shown in the UI.
---@field appliesTo dap.BreakpointModeApplicability[] Describes one or more types of breakpoint this mode applies to.
---@field description? string A help text providing additional information about the breakpoint mode. This string is typically shown as a hover and can be translated.

--------------------------------------------------------------------------------
-- Execution Control (Stepping, Continue, Pause, etc.)
--------------------------------------------------------------------------------

---@class dap.StoppedEventBody
---@field reason dap.StoppedEventReasonEnum The *reason* for the event.<br>For backward compatibility, this string is shown in the UI if the `description` attribute is missing (but it **must not** be translated).
---@field description? string The *full reason* for the event, e.g., 'Paused on exception'. This string is shown in the UI *as is* and can be translated.
---@field threadId? integer The thread which was stopped.
---@field preserveFocusHint? boolean A value of `true` hints to the client that this event should **not** change the focus.
---@field text? string Additional information. E.g., if `reason` is `"exception"`, `text` contains the exception name. This string is shown in the UI.
---@field allThreadsStopped? boolean If `allThreadsStopped` is `true`, a debug adapter can announce that **all threads have stopped**.<br>  - The client should use this information to enable that all threads can be expanded to access their stacktraces.<br>  - If the attribute is missing or `false`, **only** the thread with the given `threadId` can be expanded.
---@field hitBreakpointIds? integer[] IDs of the breakpoints that triggered the event. In most cases, there is only a single breakpoint, but here are some examples for multiple breakpoints:<br>  - Different types of breakpoints map to the same location.<br>  - Multiple source breakpoints get collapsed to the same instruction by the compiler/runtime.<br>  - Multiple function breakpoints with different function names map to the same location.

--- The event indicates that the execution of the debuggee has **stopped** due to some condition.
--- This can be caused by a breakpoint previously set, a stepping request has completed, by executing a debugger statement, etc.
---@class dap.StoppedEvent : dap.Event
---@field event "stopped" # Type of event.
---@field body dap.StoppedEventBody # Event-specific information.

--- Arguments for `continue` request.
---@class dap.ContinueArguments
---@field threadId integer Specifies the active thread. If the debug adapter supports single thread execution (see `supportsSingleThreadExecutionRequests`) and the argument `singleThread` is `true`, **only** the thread with this ID is resumed.
---@field singleThread? boolean If this flag is `true`, execution is resumed **only** for the thread with the given `threadId`.

--- The request **resumes execution of all threads**. If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting the `singleThread` argument to `true` resumes **only** the specified thread. If not all threads were resumed, the `allThreadsContinued` attribute of the response should be set to `false`.
---@class dap.ContinueRequest : dap.Request
---@field command "continue" # The command to execute.
---@field arguments dap.ContinueArguments # Arguments for `continue` request.

---@class dap.ContinueResponseBody
---@field allThreadsContinued? boolean If omitted or set to `true`, this response signals to the client that **all threads have been resumed**. The value `false` indicates that **not all threads were resumed**.

--- Response to `continue` request.
---@class dap.ContinueResponse : dap.Response
---@field body dap.ContinueResponseBody # Response body.

---@class dap.ContinuedEventBody
---@field threadId integer The thread which was continued.
---@field allThreadsContinued? boolean If omitted or set to `true`, this event signals to the client that **all threads have been resumed**. The value `false` indicates that **not all threads were resumed**.

--- The event indicates that the execution of the debuggee has **continued**.
--- **Please note**: A debug adapter is **not expected** to send this event in response to a request that implies that execution continues (e.g., `launch` or `continue`).
--- It is **only necessary** to send a `continued` event if there was no previous request that implied this.
---@class dap.ContinuedEvent : dap.Event
---@field event "continued" # Type of event.
---@field body dap.ContinuedEventBody # Event-specific information.

--- Arguments for `next` request.
---@class dap.NextArguments
---@field threadId integer Specifies the thread for which to resume execution for one step (of the given granularity).
---@field singleThread? boolean If this flag is `true`, all other suspended threads are **not resumed**.
---@field granularity? dap.SteppingGranularity Stepping granularity. If no granularity is specified, a granularity of `"statement"` is assumed.

--- The request executes **one step** (in the given granularity) for the specified thread and allows all other threads to run freely by resuming them.
--- If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting the `singleThread` argument to `true` prevents other suspended threads from resuming.
--- The debug adapter first sends the response and then a `stopped` event (with reason `"step"`) after the step has completed.
---@class dap.NextRequest : dap.Request
---@field command "next" # The command to execute.
---@field arguments dap.NextArguments # Arguments for `next` request.

--- Response to `next` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.NextResponse : dap.Response

--- A `StepInTarget` can be used in the `stepIn` request and determines into which single target the `stepIn` request should step.
---@class dap.StepInTarget
---@field id integer Unique identifier for a step-in target.
---@field label string The name of the step-in target (shown in the UI).
---@field line? integer The line of the step-in target.
---@field column? integer Start position of the range covered by the step-in target. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field endLine? integer The end line of the range covered by the step-in target.
---@field endColumn? integer End position of the range covered by the step-in target. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.

--- Arguments for `stepInTargets` request.
---@class dap.StepInTargetsArguments
---@field frameId integer The stack frame for which to retrieve the possible step-in targets.

--- This request retrieves the **possible step-in targets** for the specified stack frame.
--- These targets can be used in the `stepIn` request.
--- Clients should **only** call this request if the corresponding capability `supportsStepInTargetsRequest` is `true`.
---@class dap.StepInTargetsRequest : dap.Request
---@field command "stepInTargets" # The command to execute.
---@field arguments dap.StepInTargetsArguments # Arguments for `stepInTargets` request.

---@class dap.StepInTargetsResponseBody
---@field targets dap.StepInTarget[] The possible step-in targets of the specified source location.

--- Response to `stepInTargets` request.
---@class dap.StepInTargetsResponse : dap.Response
---@field body dap.StepInTargetsResponseBody # Response body.

--- Arguments for `stepIn` request.
---@class dap.StepInArguments
---@field threadId integer Specifies the thread for which to resume execution for one step-into (of the given granularity).
---@field singleThread? boolean If this flag is `true`, all other suspended threads are **not resumed**.
---@field targetId? integer ID of the target to step into.
---@field granularity? dap.SteppingGranularity Stepping granularity. If no granularity is specified, a granularity of `"statement"` is assumed.

--- The request resumes the given thread to **step into** a function/method and allows all other threads to run freely by resuming them.
--- If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting the `singleThread` argument to `true` prevents other suspended threads from resuming.
--- If the request **cannot step into a target**, `stepIn` behaves like the `next` request.
--- The debug adapter first sends the response and then a `stopped` event (with reason `"step"`) after the step has completed.
--- If there are multiple function/method calls (or other targets) on the source line, the argument `targetId` can be used to control into which target the `stepIn` should occur.
--- The list of possible targets for a given source line can be retrieved via the `stepInTargets` request.
---@class dap.StepInRequest : dap.Request
---@field command "stepIn" # The command to execute.
---@field arguments dap.StepInArguments # Arguments for `stepIn` request.

--- Response to `stepIn` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.StepInResponse : dap.Response

--- Arguments for `stepOut` request.
---@class dap.StepOutArguments
---@field threadId integer Specifies the thread for which to resume execution for one step-out (of the given granularity).
---@field singleThread? boolean If this flag is `true`, all other suspended threads are **not resumed**.
---@field granularity? dap.SteppingGranularity Stepping granularity. If no granularity is specified, a granularity of `"statement"` is assumed.

--- The request resumes the given thread to **step out** (return) from a function/method and allows all other threads to run freely by resuming them.
--- If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting the `singleThread` argument to `true` prevents other suspended threads from resuming.
--- The debug adapter first sends the response and then a `stopped` event (with reason `"step"`) after the step has completed.
---@class dap.StepOutRequest : dap.Request
---@field command "stepOut" # The command to execute.
---@field arguments dap.StepOutArguments # Arguments for `stepOut` request.

--- Response to `stepOut` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.StepOutResponse : dap.Response

--- Arguments for `stepBack` request.
---@class dap.StepBackArguments
---@field threadId integer Specifies the thread for which to resume execution for one step backwards (of the given granularity).
---@field singleThread? boolean If this flag is `true`, all other suspended threads are **not resumed**.
---@field granularity? dap.SteppingGranularity Stepping granularity to step. If no granularity is specified, a granularity of `"statement"` is assumed.

--- The request executes **one backward step** (in the given granularity) for the specified thread and allows all other threads to run backward freely by resuming them.
--- If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting the `singleThread` argument to `true` prevents other suspended threads from resuming.
--- The debug adapter first sends the response and then a `stopped` event (with reason `"step"`) after the step has completed.
--- Clients should **only** call this request if the corresponding capability `supportsStepBack` is `true`.
---@class dap.StepBackRequest : dap.Request
---@field command "stepBack" # The command to execute.
---@field arguments dap.StepBackArguments # Arguments for `stepBack` request.

--- Response to `stepBack` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.StepBackResponse : dap.Response

--- Arguments for `reverseContinue` request.
---@class dap.ReverseContinueArguments
---@field threadId integer Specifies the active thread. If the debug adapter supports single thread execution (see `supportsSingleThreadExecutionRequests`) and the `singleThread` argument is `true`, **only** the thread with this ID is resumed.
---@field singleThread? boolean If this flag is `true`, backward execution is resumed **only** for the thread with the given `threadId`.

--- The request **resumes backward execution** of all threads. If the debug adapter supports single thread execution (see capability `supportsSingleThreadExecutionRequests`), setting the `singleThread` argument to `true` resumes **only** the specified thread. If not all threads were resumed, the `allThreadsContinued` attribute of the response should be set to `false`.
--- Clients should **only** call this request if the corresponding capability `supportsStepBack` is `true`.
---@class dap.ReverseContinueRequest : dap.Request
---@field command "reverseContinue" # The command to execute.
---@field arguments dap.ReverseContinueArguments # Arguments for `reverseContinue` request.

--- Response to `reverseContinue` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.ReverseContinueResponse : dap.Response

--- Arguments for `restartFrame` request.
---@class dap.RestartFrameArguments
---@field frameId integer Restart the stack frame identified by `frameId`. The `frameId` **must** have been obtained in the current suspended state. See 'Lifetime of Object References' in the Overview section for details.

--- The request **restarts execution** of the specified stack frame.
--- The debug adapter first sends the response and then a `stopped` event (with reason `"restart"`) after the restart has completed.
--- Clients should **only** call this request if the corresponding capability `supportsRestartFrame` is `true`.
---@class dap.RestartFrameRequest : dap.Request
---@field command "restartFrame" # The command to execute.
---@field arguments dap.RestartFrameArguments # Arguments for `restartFrame` request.

--- Response to `restartFrame` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.RestartFrameResponse : dap.Response

--- A `GotoTarget` describes a code location that can be used as a target in the `goto` request.
--- The possible goto targets can be determined via the `gotoTargets` request.
---@class dap.GotoTarget
---@field id integer Unique identifier for a goto target. This is used in the `goto` request.
---@field label string The name of the goto target (shown in the UI).
---@field line integer The line of the goto target.
---@field column? integer The column of the goto target.
---@field endLine? integer The end line of the range covered by the goto target.
---@field endColumn? integer The end column of the range covered by the goto target.
---@field instructionPointerReference? string A memory reference for the instruction pointer value represented by this target.

--- Arguments for `gotoTargets` request.
---@class dap.GotoTargetsArguments
---@field source dap.Source The source location for which the goto targets are determined.
---@field line integer The line location for which the goto targets are determined.
---@field column? integer The position within `line` for which the goto targets are determined. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.

--- This request retrieves the **possible goto targets** for the specified source location.
--- These targets can be used in the `goto` request.
--- Clients should **only** call this request if the corresponding capability `supportsGotoTargetsRequest` is `true`.
---@class dap.GotoTargetsRequest : dap.Request
---@field command "gotoTargets" # The command to execute.
---@field arguments dap.GotoTargetsArguments # Arguments for `gotoTargets` request.

---@class dap.GotoTargetsResponseBody
---@field targets dap.GotoTarget[] The possible goto targets of the specified location.

--- Response to `gotoTargets` request.
---@class dap.GotoTargetsResponse : dap.Response
---@field body dap.GotoTargetsResponseBody # Response body.

--- Arguments for `goto` request.
---@class dap.GotoArguments
---@field threadId integer Set the goto target for this thread.
---@field targetId integer The location where the debuggee will continue to run.

--- The request sets the location where the debuggee will **continue to run**.
--- This makes it possible to *skip* the execution of code or to *execute code again*.
--- The code between the current location and the goto target is **not executed** but skipped.
--- The debug adapter first sends the response and then a `stopped` event with reason `"goto"`.
--- Clients should **only** call this request if the corresponding capability `supportsGotoTargetsRequest` is `true` (because only then do goto targets exist that can be passed as arguments).
---@class dap.GotoRequest : dap.Request
---@field command "goto" # The command to execute.
---@field arguments dap.GotoArguments # Arguments for `goto` request.

--- Response to `goto` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.GotoResponse : dap.Response

--- Arguments for `pause` request.
---@class dap.PauseArguments
---@field threadId integer Pause execution for this thread.

--- The request **suspends the debuggee**.
--- The debug adapter first sends the response and then a `stopped` event (with reason `"pause"`) after the thread has been paused successfully.
---@class dap.PauseRequest : dap.Request
---@field command "pause" # The command to execute.
---@field arguments dap.PauseArguments # Arguments for `pause` request.

--- Response to `pause` request. This is just an **acknowledgement**, so no `body` field is required.
---@class dap.PauseResponse : dap.Response

--------------------------------------------------------------------------------
-- Data Inspection (Stack, Scopes, Variables, Evaluate, Memory)
--------------------------------------------------------------------------------

--- Arguments for `stackTrace` request.
---@class dap.StackTraceArguments
---@field threadId integer Retrieve the stacktrace for this thread.
---@field startFrame? integer The index of the first frame to return; if omitted, frames start at `0`.
---@field levels? integer The maximum number of frames to return. If `levels` is not specified or `0`, **all frames** are returned.
---@field format? dap.StackFrameFormat Specifies details on how to format the returned `dap.StackFrame.name`. The debug adapter *may* format requested details in any way that would make sense to a developer.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsValueFormattingOptions` is `true`.

--- The request returns a **stacktrace** from the current execution state of a given thread.
--- A client can request *all* stack frames by omitting the `startFrame` and `levels` arguments. For performance-conscious clients, and if the corresponding capability `supportsDelayedStackTraceLoading` is `true`, stack frames can be retrieved in a *piecemeal* way with the `startFrame` and `levels` arguments. The response of the `stackTrace` request *may* contain a `totalFrames` property that hints at the total number of frames in the stack. If a client needs this total number upfront, it can issue a request for a single (first) frame and, depending on the value of `totalFrames`, decide how to proceed. In any case, a client should be prepared to receive *fewer frames than requested*, which is an indication that the end of the stack has been reached.
---@class dap.StackTraceRequest : dap.Request
---@field command "stackTrace" # The command to execute.
---@field arguments dap.StackTraceArguments # Arguments for `stackTrace` request.

---@class dap.StackTraceResponseBody
---@field stackFrames? dap.StackFrame[] The frames of the stack frame. If the array has length zero, there are **no stack frames available**.<br>This means that there is no location information available. Optional because some DAP adapters may not send it.
---@field totalFrames? integer The total number of frames available in the stack. If omitted or if `totalFrames` is larger than the available frames, a client is expected to request frames until a request returns *less frames than requested* (which indicates the end of the stack). Returning monotonically increasing `totalFrames` values for subsequent requests can be used to enforce paging in the client.

--- Response to `stackTrace` request.
---@class dap.StackTraceResponse : dap.Response
---@field body dap.StackTraceResponseBody # Response body.

--- Arguments for `scopes` request.
---@class dap.ScopesArguments
---@field frameId integer Retrieve the scopes for the stack frame identified by `frameId`. The `frameId` **must** have been obtained in the current suspended state. See 'Lifetime of Object References' in the Overview section for details.

--- The request returns the **variable scopes** for a given stack frame ID.
---@class dap.ScopesRequest : dap.Request
---@field command "scopes" # The command to execute.
---@field arguments dap.ScopesArguments # Arguments for `scopes` request.

---@class dap.ScopesResponseBody
---@field scopes dap.Scope[] The scopes of the stack frame. If the array has length zero, there are **no scopes available**.

--- Response to `scopes` request.
---@class dap.ScopesResponse : dap.Response
---@field body dap.ScopesResponseBody # Response body.

--- Arguments for `variables` request.
---@class dap.VariablesArguments
---@field variablesReference integer The variable for which to retrieve its children. The `variablesReference` **must** have been obtained in the current suspended state. See 'Lifetime of Object References' in the Overview section for details.
---@field filter? dap.VariablesFilterEnum Filter to limit the child variables to either named or indexed. If omitted, **both types** are fetched.
---@field start? integer The index of the first variable to return; if omitted, children start at `0`.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsVariablePaging` is `true`.
---@field count? integer The number of variables to return. If `count` is missing or `0`, **all variables** are returned.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsVariablePaging` is `true`.
---@field format? dap.ValueFormat Specifies details on how to format the Variable values.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsValueFormattingOptions` is `true`.

--- Retrieves **all child variables** for the given variable reference.
--- A filter can be used to limit the fetched children to either *named* or *indexed* children.
---@class dap.VariablesRequest : dap.Request
---@field command "variables" # The command to execute.
---@field arguments dap.VariablesArguments # Arguments for `variables` request.

---@class dap.VariablesResponseBody
---@field variables dap.Variable[] All (or a range) of variables for the given variable reference.

--- Response to `variables` request.
---@class dap.VariablesResponse : dap.Response
---@field body dap.VariablesResponseBody # Response body.

--- Arguments for `setVariable` request.
---@class dap.SetVariableArguments
---@field variablesReference integer The reference of the variable container. The `variablesReference` **must** have been obtained in the current suspended state. See 'Lifetime of Object References' in the Overview section for details.
---@field name string The name of the variable in the container.
---@field value string The value of the variable.
---@field format? dap.ValueFormat Specifies details on how to format the response value.

--- Set the variable with the given name in the variable container to a **new value**. Clients should **only** call this request if the corresponding capability `supportsSetVariable` is `true`.
--- If a debug adapter implements both `setVariable` and `setExpression`, a client will **only use `setExpression`** if the variable has an `evaluateName` property.
---@class dap.SetVariableRequest : dap.Request
---@field command "setVariable" # The command to execute.
---@field arguments dap.SetVariableArguments # Arguments for `setVariable` request.

---@class dap.SetVariableResponseBody
---@field value string The *new value* of the variable.
---@field type? string The type of the new value. Typically shown in the UI when hovering over the value.
---@field variablesReference? integer If `variablesReference` is `> 0`, the new value is structured and its children can be retrieved by passing `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object References' in the Overview section for details.<br><br>If this property is included in the response, any `variablesReference` previously associated with the updated variable, and those of its children, are **no longer valid**.
---@field namedVariables? integer The number of named child variables.<br>The client can use this information to present the variables in a paged UI and fetch them in chunks.<br>The value should be less than or equal to `2147483647` (2^31-1).
---@field indexedVariables? integer The number of indexed child variables.<br>The client can use this information to present the variables in a paged UI and fetch them in chunks.<br>The value should be less than or equal to `2147483647` (2^31-1).
---@field memoryReference? string A memory reference to a location appropriate for this result.<br>For pointer type eval results, this is generally a reference to the memory address contained in the pointer.<br>This attribute *may* be returned by a debug adapter if the corresponding capability `supportsMemoryReferences` is `true`.
---@field valueLocationReference? integer A reference that allows the client to request the location where the new value is declared. For example, if the new value is a function pointer, the adapter *may* be able to look up the function's location. This should be present **only if** the adapter is likely to be able to resolve the location.<br><br>This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview section for details.

--- Response to `setVariable` request.
---@class dap.SetVariableResponse : dap.Response
---@field body dap.SetVariableResponseBody # Response body.

--- Arguments for `evaluate` request.
---@class dap.EvaluateArguments
---@field expression string The expression to evaluate.
---@field frameId? integer Evaluate the expression in the scope of this stack frame. If not specified, the expression is evaluated in the *global scope*.
---@field line? integer The contextual line where the expression should be evaluated. In the `'hover'` context, this should be set to the start of the expression being hovered.
---@field column? integer The contextual column where the expression should be evaluated. This *may* be provided if `line` is also provided.<br><br>It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field source? dap.Source The contextual source in which the `line` is found. This **must be provided** if `line` is provided.
---@field context? dap.EvaluateContextEnum The context in which the `evaluate` request is used.
---@field format? dap.ValueFormat Specifies details on how to format the result.<br>The attribute is **only honored** by a debug adapter if the corresponding capability `supportsValueFormattingOptions` is `true`.

--- **Evaluates the given expression** in the context of a stack frame.
--- The expression has access to any variables and arguments that are in scope.
---@class dap.EvaluateRequest : dap.Request
---@field command "evaluate" # The command to execute.
---@field arguments dap.EvaluateArguments # Arguments for `evaluate` request.

---@class dap.EvaluateResponseBody
---@field result string The result of the `evaluate` request.
---@field variablesReference integer If `variablesReference` is `> 0`, the evaluate result is structured, and its children can be retrieved by passing `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object References' in the Overview section for details.
---@field type? string The type of the evaluate result.<br>This attribute should **only** be returned by a debug adapter if the corresponding capability `supportsVariableType` is `true`.
---@field presentationHint? dap.VariablePresentationHint Properties of an evaluate result that can be used to determine how to render the result in the UI.
---@field namedVariables? integer The number of named child variables.<br>The client can use this information to present the variables in a paged UI and fetch them in chunks.<br>The value should be less than or equal to `2147483647` (2^31-1).
---@field indexedVariables? integer The number of indexed child variables.<br>The client can use this information to present the variables in a paged UI and fetch them in chunks.<br>The value should be less than or equal to `2147483647` (2^31-1).
---@field memoryReference? string A memory reference to a location appropriate for this result.<br>For pointer type eval results, this is generally a reference to the memory address contained in the pointer.<br>This attribute *may* be returned by a debug adapter if the corresponding capability `supportsMemoryReferences` is `true`.
---@field valueLocationReference? integer A reference that allows the client to request the location where the returned value is declared. For example, if a function pointer is returned, the adapter *may* be able to look up the function's location. This should be present **only if** the adapter is likely to be able to resolve the location.<br><br>This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview section for details.

--- Response to `evaluate` request.
---@class dap.EvaluateResponse : dap.Response
---@field body dap.EvaluateResponseBody # Response body.

--- Arguments for `setExpression` request.
---@class dap.SetExpressionArguments
---@field expression string The l-value expression to assign to.
---@field value string The value expression to assign to the l-value expression.
---@field frameId? integer Evaluate the expressions in the scope of this stack frame. If not specified, the expressions are evaluated in the *global scope*.
---@field format? dap.ValueFormat Specifies how the resulting value should be formatted.

--- Evaluates the given `value` expression and **assigns it to the `expression`** which **must be a modifiable l-value**.
--- The expressions have access to any variables and arguments that are in scope of the specified frame.
--- Clients should **only** call this request if the corresponding capability `supportsSetExpression` is `true`.
--- If a debug adapter implements both `setExpression` and `setVariable`, a client uses `setExpression` if the variable has an `evaluateName` property.
---@class dap.SetExpressionRequest : dap.Request
---@field command "setExpression" # The command to execute.
---@field arguments dap.SetExpressionArguments # Arguments for `setExpression` request.

---@class dap.SetExpressionResponseBody
---@field value string The *new value* of the expression.
---@field type? string The type of the value.<br>This attribute should **only** be returned by a debug adapter if the corresponding capability `supportsVariableType` is `true`.
---@field presentationHint? dap.VariablePresentationHint Properties of a value that can be used to determine how to render the result in the UI.
---@field variablesReference? integer If `variablesReference` is `> 0`, the evaluate result is structured, and its children can be retrieved by passing `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object References' in the Overview section for details.
---@field namedVariables? integer The number of named child variables.<br>The client can use this information to present the variables in a paged UI and fetch them in chunks.<br>The value should be less than or equal to `2147483647` (2^31-1).
---@field indexedVariables? integer The number of indexed child variables.<br>The client can use this information to present the variables in a paged UI and fetch them in chunks.<br>The value should be less than or equal to `2147483647` (2^31-1).
---@field memoryReference? string A memory reference to a location appropriate for this result.<br>For pointer type eval results, this is generally a reference to the memory address contained in the pointer.<br>This attribute *may* be returned by a debug adapter if the corresponding capability `supportsMemoryReferences` is `true`.
---@field valueLocationReference? integer A reference that allows the client to request the location where the new value is declared. For example, if the new value is a function pointer, the adapter *may* be able to look up the function's location. This should be present **only if** the adapter is likely to be able to resolve the location.<br><br>This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview section for details.

--- Response to `setExpression` request.
---@class dap.SetExpressionResponse : dap.Response
---@field body dap.SetExpressionResponseBody # Response body.

--- Arguments for `readMemory` request.
---@class dap.ReadMemoryArguments
---@field memoryReference string Memory reference to the base location from which data should be read.
---@field count integer Number of bytes to read at the specified location and offset.
---@field offset? integer Offset (in bytes) to be applied to the reference location before reading data. Can be negative.

--- **Reads bytes from memory** at the provided location.
--- Clients should **only** call this request if the corresponding capability `supportsReadMemoryRequest` is `true`.
---@class dap.ReadMemoryRequest : dap.Request
---@field command "readMemory" # The command to execute.
---@field arguments dap.ReadMemoryArguments # Arguments for `readMemory` request.

---@class dap.ReadMemoryResponseBody
---@field address string The address of the first byte of data returned.<br>Treated as a hex value if prefixed with `0x`, or as a decimal value otherwise.
---@field unreadableBytes? integer The number of *unreadable bytes* encountered after the last successfully read byte.<br>This can be used to determine the number of bytes that should be skipped before a subsequent `readMemory` request succeeds.
---@field data? string The bytes read from memory, encoded using base64. If the decoded length of `data` is **less than** the requested `count` in the original `dap.ReadMemoryRequest`, and `unreadableBytes` is zero or omitted, then the client should assume it's reached the end of readable memory.

--- Response to `readMemory` request.
---@class dap.ReadMemoryResponse : dap.Response
---@field body? dap.ReadMemoryResponseBody # Optional because `success: false` might omit body

--- Arguments for `writeMemory` request.
---@class dap.WriteMemoryArguments
---@field memoryReference string Memory reference to the base location to which data should be written.
---@field data string Bytes to write, encoded using base64.
---@field offset? integer Offset (in bytes) to be applied to the reference location before writing data. Can be negative.
---@field allowPartial? boolean Property to control *partial writes*. If `true`, the debug adapter should attempt to write memory even if the entire memory region is **not writable**. In such a case, the debug adapter should stop after hitting the first byte of memory that cannot be written and return the number of bytes written in the response via the `offset` and `bytesWritten` properties.<br>If `false` or missing, a debug adapter should attempt to verify the region is writable before writing, and **fail the response** if it is not.

--- **Writes bytes to memory** at the provided location.
--- Clients should **only** call this request if the corresponding capability `supportsWriteMemoryRequest` is `true`.
---@class dap.WriteMemoryRequest : dap.Request
---@field command "writeMemory" # The command to execute.
---@field arguments dap.WriteMemoryArguments # Arguments for `writeMemory` request.

---@class dap.WriteMemoryResponseBody
---@field offset? integer Property that should be returned when `allowPartial` is `true` to indicate the offset of the *first byte of data successfully written*. Can be negative.
---@field bytesWritten? integer Property that should be returned when `allowPartial` is `true` to indicate the *number of bytes starting from address that were successfully written*.

--- Response to `writeMemory` request.
---@class dap.WriteMemoryResponse : dap.Response
---@field body? dap.WriteMemoryResponseBody # Body is optional

--- Arguments for `disassemble` request.
---@class dap.DisassembleArguments
---@field memoryReference string Memory reference to the base location containing the instructions to disassemble.
---@field instructionCount integer Number of instructions to disassemble starting at the specified location and offset.<br>An adapter **must return exactly this number** of instructions - any unavailable instructions should be replaced with an implementation-defined 'invalid instruction' value.
---@field offset? integer Offset (in bytes) to be applied to the reference location before disassembling. Can be negative.
---@field instructionOffset? integer Offset (in instructions) to be applied *after* the byte offset (if any) before disassembling. Can be negative.
---@field resolveSymbols? boolean If `true`, the adapter should attempt to resolve memory addresses and other values to symbolic names.

--- **Disassembles code** stored at the provided location.
--- Clients should **only** call this request if the corresponding capability `supportsDisassembleRequest` is `true`.
---@class dap.DisassembleRequest : dap.Request
---@field command "disassemble" # The command to execute.
---@field arguments dap.DisassembleArguments # Arguments for `disassemble` request.

---@class dap.DisassembleResponseBody
---@field instructions dap.DisassembledInstruction[] The list of disassembled instructions.

--- Response to `disassemble` request.
---@class dap.DisassembleResponse : dap.Response
---@field body? dap.DisassembleResponseBody # Body is optional if success is false

--------------------------------------------------------------------------------
-- Source, Thread, and Module Management
--------------------------------------------------------------------------------

--- A `Source` is a descriptor for source code.
--- It is returned from the debug adapter as part of a `StackFrame` and it is used by clients when specifying breakpoints.
---@class dap.Source
---@field name? string The short name of the source. Every source returned from the debug adapter has a name.<br>When sending a source to the debug adapter this name is optional.
---@field path? string The path of the source to be shown in the UI.<br>It is only used to locate and load the content of the source if no `sourceReference` is specified (or its value is 0).
---@field sourceReference? integer If the value > 0 the contents of the source must be retrieved through the `source` request (even if a path is specified).<br>Since a `sourceReference` is only valid for a session, it can not be used to persist a source.<br>The value should be less than or equal to 2147483647 (2^31-1).
---@field presentationHint? dap.SourcePresentationHintEnum A hint for how to present the source in the UI.<br>A value of `deemphasize` can be used to indicate that the source is not available or that it is skipped on stepping.
---@field origin? string The origin of this source. For example, 'internal module', 'inlined content from source map', etc.
---@field sources? dap.Source[] A list of sources that are related to this source. These may be the source that generated this source.
---@field adapterData? dap.JsonValue Additional data that a debug adapter might want to loop through the client.<br>The client should leave the data intact and persist it across sessions. The client should not interpret the data.
---@field checksums? dap.Checksum[] The checksums associated with this file.

--- Arguments for `source` request.
---@class dap.SourceArguments
---@field sourceReference integer The reference to the source. This is the same as `source.sourceReference`.<br>This is provided for **backward compatibility** since old clients do not understand the `source` attribute.
---@field source? dap.Source Specifies the source content to load. Either `source.path` or `source.sourceReference` **must be specified**.

--- The request retrieves the **source code** for a given source reference.
---@class dap.SourceRequest : dap.Request
---@field command "source" # The command to execute.
---@field arguments dap.SourceArguments # Arguments for `source` request.

---@class dap.SourceResponseBody
---@field content string Content of the source reference.
---@field mimeType? string Content type (MIME type) of the source.

--- Response to `source` request.
---@class dap.SourceResponse : dap.Response
---@field body dap.SourceResponseBody # Response body.

--- Arguments for `loadedSources` request.
---@class dap.LoadedSourcesArguments -- This class has no properties defined in the schema.

--- Retrieves the set of **all sources currently loaded** by the debugged process.
--- Clients should **only** call this request if the corresponding capability `supportsLoadedSourcesRequest` is `true`.
---@class dap.LoadedSourcesRequest : dap.Request
---@field command "loadedSources" # The command to execute.
---@field arguments? dap.LoadedSourcesArguments # Arguments for `loadedSources` request.

---@class dap.LoadedSourcesResponseBody
---@field sources dap.Source[] Set of loaded sources.

--- Response to `loadedSources` request.
---@class dap.LoadedSourcesResponse : dap.Response
---@field body dap.LoadedSourcesResponseBody # Response body.

---@class dap.LoadedSourceEventBody
---@field reason dap.ModificationReasonEnum The reason for the event.
---@field source dap.Source The new, changed, or removed source.

--- The event indicates that some **source has been added, changed, or removed** from the set of all loaded sources.
---@class dap.LoadedSourceEvent : dap.Event
---@field event "loadedSource" # Type of event.
---@field body dap.LoadedSourceEventBody # Event-specific information.

--- A Thread
---@class dap.Thread
---@field id integer Unique identifier for the thread.
---@field name string The name of the thread.

--- The request retrieves a list of **all threads**.
---@class dap.ThreadsRequest : dap.Request
---@field command "threads" # The command to execute.

---@class dap.ThreadsResponseBody
---@field threads dap.Thread[] All threads.

--- Response to `threads` request.
---@class dap.ThreadsResponse : dap.Response
---@field body dap.ThreadsResponseBody # Response body.

--- Arguments for `terminateThreads` request.
---@class dap.TerminateThreadsArguments
---@field threadIds? integer[] IDs of threads to be terminated.

--- The request **terminates the threads** with the given IDs.
--- Clients should **only** call this request if the corresponding capability `supportsTerminateThreadsRequest` is `true`.
---@class dap.TerminateThreadsRequest : dap.Request
---@field command "terminateThreads" # The command to execute.
---@field arguments dap.TerminateThreadsArguments # Arguments for `terminateThreads` request.

--- Response to `terminateThreads` request. This is just an **acknowledgement**, no `body` field is required.
---@class dap.TerminateThreadsResponse : dap.Response

---@class dap.ThreadEventBody
---@field reason dap.ThreadEventReasonEnum The reason for the event.
---@field threadId integer The identifier of the thread.

--- The event indicates that a thread has **started** or **exited**.
---@class dap.ThreadEvent : dap.Event
---@field event "thread" # Type of event.
---@field body dap.ThreadEventBody # Event-specific information.

--- A Module object represents a row in the modules view.
--- The `id` attribute identifies a module in the modules view and is used in a `module` event for identifying a module for adding, updating or deleting.
--- The `name` attribute is used to minimally render the module in the UI.
--- Additional attributes can be added to the module. They show up in the module view if they have a corresponding `ColumnDescriptor`.
--- To avoid an unnecessary proliferation of additional attributes with similar semantics but different names, we recommend to re-use attributes from the 'recommended' list below first, and only introduce new attributes if nothing appropriate could be found.
---@class dap.Module
---@field id integer|string Unique identifier for the module.
---@field name string A name of the module.
---@field path? string Logical full path to the module. The exact definition is implementation defined, but usually this would be a full path to the on-disk file for the module.
---@field isOptimized? boolean True if the module is optimized.
---@field isUserCode? boolean True if the module is considered 'user code' by a debugger that supports 'Just My Code'.
---@field version? string Version of Module.
---@field symbolStatus? string User-understandable description of if symbols were found for the module (ex: 'Symbols Loaded', 'Symbols not found', etc.)
---@field symbolFilePath? string Logical full path to the symbol file. The exact definition is implementation defined.
---@field dateTimeStamp? string Module created or modified, encoded as a RFC 3339 timestamp.
---@field addressRange? string Address range covered by this module.

--- Arguments for `modules` request.
---@class dap.ModulesArguments
---@field startModule? integer The index of the first module to return; if omitted, modules start at `0`.
---@field moduleCount? integer The number of modules to return. If `moduleCount` is not specified or `0`, **all modules** are returned.

--- Modules can be retrieved from the debug adapter with this request, which can either return **all modules** or a **range of modules** to support paging.
--- Clients should **only** call this request if the corresponding capability `supportsModulesRequest` is `true`.
---@class dap.ModulesRequest : dap.Request
---@field command "modules" # The command to execute.
---@field arguments dap.ModulesArguments # Arguments for `modules` request.

---@class dap.ModulesResponseBody
---@field modules dap.Module[] All modules or a range of modules.
---@field totalModules? integer The total number of modules available.

--- Response to `modules` request.
---@class dap.ModulesResponse : dap.Response
---@field body dap.ModulesResponseBody # Response body.

---@class dap.ModuleEventBody
---@field reason dap.ModificationReasonEnum The reason for the event.
---@field module dap.Module The new, changed, or removed module. In case of `"removed"`, **only** the module `id` is used.

--- The event indicates that some information about a **module has changed**.
---@class dap.ModuleEvent : dap.Event
---@field event "module" # Type of event.
---@field body dap.ModuleEventBody # Event-specific information.

--------------------------------------------------------------------------------
-- Completions, Exceptions, and Location Info
--------------------------------------------------------------------------------

--- Arguments for `completions` request.
---@class dap.CompletionsArguments
---@field text string One or more source lines. Typically, this is the text users have typed into the debug console *before* they asked for completion.
---@field column integer The position within `text` for which to determine the completion proposals. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field frameId? integer Returns completions in the scope of this stack frame. If not specified, the completions are returned for the *global scope*.
---@field line? integer A line for which to determine the completion proposals. If missing, the first line of the text is assumed.

--- Returns a list of **possible completions** for a given caret position and text.
--- Clients should **only** call this request if the corresponding capability `supportsCompletionsRequest` is `true`.
---@class dap.CompletionsRequest : dap.Request
---@field command "completions" # The command to execute.
---@field arguments dap.CompletionsArguments # Arguments for `completions` request.

---@class dap.CompletionsResponseBody
---@field targets dap.CompletionItem[] The possible completions.

--- Response to `completions` request.
---@class dap.CompletionsResponse : dap.Response
---@field body dap.CompletionsResponseBody # Response body.

--- Arguments for `exceptionInfo` request.
---@class dap.ExceptionInfoArguments
---@field threadId integer Thread for which exception information should be retrieved.

--- Retrieves the **details of the exception** that caused this event to be raised.
--- Clients should **only** call this request if the corresponding capability `supportsExceptionInfoRequest` is `true`.
---@class dap.ExceptionInfoRequest : dap.Request
---@field command "exceptionInfo" # The command to execute.
---@field arguments dap.ExceptionInfoArguments # Arguments for `exceptionInfo` request.

---@class dap.ExceptionInfoResponseBody
---@field exceptionId string ID of the exception that was thrown.
---@field breakMode dap.ExceptionBreakMode Mode that caused the exception notification to be raised.
---@field description? string Descriptive text for the exception.
---@field details? dap.ExceptionDetails Detailed information about the exception.

--- Response to `exceptionInfo` request.
---@class dap.ExceptionInfoResponse : dap.Response
---@field body dap.ExceptionInfoResponseBody # Response body.

--- Arguments for `locations` request.
---@class dap.LocationsArguments
---@field locationReference integer Location reference to resolve.

--- Looks up information about a **location reference** previously returned by the debug adapter.
---@class dap.LocationsRequest : dap.Request
---@field command "locations" # The command to execute.
---@field arguments dap.LocationsArguments # Arguments for `locations` request.

---@class dap.LocationsResponseBody
---@field source dap.Source The source containing the location; either `source.path` or `source.sourceReference` **must be specified**.
---@field line integer The line number of the location. The client capability `linesStartAt1` determines whether it is 0- or 1-based.
---@field column? integer Position of the location within the `line`. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based. If no column is given, the first position in the start line is assumed.
---@field endLine? integer End line of the location, present if the location refers to a *range*. The client capability `linesStartAt1` determines whether it is 0- or 1-based.
---@field endColumn? integer End position of the location within `endLine`, present if the location refers to a *range*. It is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.

--- Response to `locations` request.
---@class dap.LocationsResponse : dap.Response
---@field body? dap.LocationsResponseBody # Body is optional if success is false

--------------------------------------------------------------------------------
-- General Events (Not tied to a specific request/response)
--------------------------------------------------------------------------------

---@class dap.OutputEventBody
---@field output string The output to report.<br><br>ANSI escape sequences may be used to influence text color and styling if `supportsANSIStyling` is present in both the adapter's `Capabilities` and the client's `InitializeRequestArguments`. A client may strip any unrecognized ANSI sequences.<br><br>If the `supportsANSIStyling` capabilities are not both true, then the client should display the output literally.
---@field category? dap.OutputEventCategoryEnum The output category. If not specified or if the category is not understood by the client, `console` is assumed.
---@field group? dap.OutputEventGroupEnum Support for keeping an output log organized by grouping related messages.
---@field variablesReference? integer If an attribute `variablesReference` exists and its value is > 0, the output contains objects which can be retrieved by passing `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object References' in the Overview section for details.
---@field source? dap.Source The source location where the output was produced.
---@field line? integer The source location's line where the output was produced.
---@field column? integer The position in `line` where the output was produced. It is measured in UTF-16 code units and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field data? dap.JsonValue Additional data to report. For the `telemetry` category the data is sent to telemetry, for the other categories the data is shown in JSON format.
---@field locationReference? integer A reference that allows the client to request the location where the new value is declared. For example, if the logged value is function pointer, the adapter may be able to look up the function's location. This should be present only if the adapter is likely to be able to resolve the location.<br><br>This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview section for details.

--- The event indicates that the target has produced some output.
---@class dap.OutputEvent : dap.Event
---@field event "output" # Type of event.
---@field body dap.OutputEventBody # Event-specific information.

---@class dap.ProcessEventBody
---@field name string The *logical name* of the process. This is usually the full path to the process's executable file (e.g., `/home/example/myproj/program.js`).
---@field systemProcessId? integer The process ID of the debugged process, as assigned by the operating system. This property should be **omitted** for logical processes that do not map to operating system processes on the machine.
---@field isLocalProcess? boolean If `true`, the process is running on the **same computer** as the debug adapter.
---@field startMethod? dap.ProcessEventStartMethodEnum Describes *how* the debug engine started debugging this process.
---@field pointerSize? integer The size of a pointer or address for this process, in bits. This value *may* be used by clients when formatting addresses for display.

--- The event indicates that the debugger has begun debugging a **new process**. Either one that it has launched or one that it has attached to.
---@class dap.ProcessEvent : dap.Event
---@field event "process" # Type of event.
---@field body dap.ProcessEventBody # Event-specific information.

---@class dap.CapabilitiesEventBody
---@field capabilities dap.Capabilities The set of *updated* capabilities.

--- The event indicates that **one or more capabilities have changed**.
--- Since the capabilities are dependent on the client and its UI, it *might not be possible* to change them at random times (or too late).
--- Consequently, this event has a *hint* characteristic: a client can **only** be expected to make a 'best effort' in honoring individual capabilities, but there are **no guarantees**.
--- **Only changed** capabilities need to be included; all other capabilities keep their values.
---@class dap.CapabilitiesEvent : dap.Event
---@field event "capabilities" # Type of event.
---@field body dap.CapabilitiesEventBody # Event-specific information.

---@class dap.InvalidatedEventBody
---@field areas? dap.InvalidatedAreas[] Set of logical areas that got invalidated. This property has a *hint* characteristic: a client can **only** be expected to make a 'best effort' in honoring the areas, but there are **no guarantees**. If this property is missing, empty, or if values are not understood, the client should assume a single value `"all"`.
---@field threadId? integer If specified, the client **only** needs to refetch data related to this thread.
---@field stackFrameId? integer If specified, the client **only** needs to refetch data related to this stack frame (and the `threadId` is ignored).

--- This event signals that some state in the debug adapter has changed and requires that the client needs to **re-render the data snapshot** previously requested.
--- Debug adapters do **not have to** emit this event for runtime changes like `stopped` or `thread` events because in that case, the client refetches the new state anyway. But the event *can be used*, for example, to refresh the UI after rendering formatting has changed in the debug adapter.
--- This event should **only** be sent if the corresponding capability `supportsInvalidatedEvent` is `true`.
---@class dap.InvalidatedEvent : dap.Event
---@field event "invalidated" # Type of event.
---@field body dap.InvalidatedEventBody # Event-specific information.

---@class dap.MemoryEventBody
---@field memoryReference string Memory reference of a memory range that has been updated.
---@field offset integer Starting offset in bytes where memory has been updated. Can be negative.
---@field count integer Number of bytes updated.

--- This event indicates that some **memory range has been updated**. It should **only** be sent if the corresponding capability `supportsMemoryEvent` is `true`.
--- Clients typically react to the event by re-issuing a `readMemory` request if they show the memory identified by the `memoryReference` and if the updated memory range overlaps the displayed range. Clients should **not make assumptions** about how individual memory references relate to each other, so they should not assume that they are part of a single continuous address range and might overlap.
--- Debug adapters can use this event to indicate that the contents of a memory range has changed due to some other request like `setVariable` or `setExpression`. Debug adapters are **not expected** to emit this event for each and every memory change of a running program, because that information is typically not available from debuggers and it would flood clients with too many events.
---@class dap.MemoryEvent : dap.Event
---@field event "memory" # Type of event.
---@field body dap.MemoryEventBody # Event-specific information.

--------------------------------------------------------------------------------
-- Progress Reporting Events
--------------------------------------------------------------------------------

---@class dap.ProgressStartEventBody
---@field progressId string An ID that can be used in subsequent `progressUpdate` and `progressEnd` events to make them refer to the same progress reporting.<br>IDs **must be unique** within a debug session.
---@field title string Short title of the progress reporting. Shown in the UI to describe the long-running operation.
---@field requestId? integer The request ID that this progress report is related to. If specified, a debug adapter is expected to emit progress events for the long-running request until the request has been either *completed* or *cancelled*.<br>If the `requestId` is omitted, the progress report is assumed to be related to some general activity of the debug adapter.
---@field cancellable? boolean If `true`, the request that reports progress *may be cancelled* with a `cancel` request.<br>So, this property basically controls whether the client should use UX that supports cancellation.<br>Clients that **don't support cancellation** are allowed to ignore the setting.
---@field message? string More detailed progress message.
---@field percentage? number Progress percentage to display (value range: `0` to `100`). If omitted, no percentage is shown.

--- The event signals that a **long-running operation is about to start** and provides additional information for the client to set up a corresponding progress and cancellation UI.
--- The client is *free to delay* the showing of the UI in order to reduce flicker.
--- This event should **only** be sent if the corresponding capability `supportsProgressReporting` is `true`.
---@class dap.ProgressStartEvent : dap.Event
---@field event "progressStart" # Type of event.
---@field body dap.ProgressStartEventBody # Event-specific information.

---@class dap.ProgressUpdateEventBody
---@field progressId string The ID that was introduced in the initial `progressStart` event.
---@field message? string More detailed progress message. If omitted, the *previous message* (if any) is used.
---@field percentage? number Progress percentage to display (value range: `0` to `100`). If omitted, no percentage is shown.

--- The event signals that the progress reporting needs to be **updated** with a new message and/or percentage.
--- The client does **not have to** update the UI immediately, but the client **needs to keep track** of the message and/or percentage values.
--- This event should **only** be sent if the corresponding capability `supportsProgressReporting` is `true`.
---@class dap.ProgressUpdateEvent : dap.Event
---@field event "progressUpdate" # Type of event.
---@field body dap.ProgressUpdateEventBody # Event-specific information.

---@class dap.ProgressEndEventBody
---@field progressId string The ID that was introduced in the initial `dap.ProgressStartEvent`.
---@field message? string More detailed progress message. If omitted, the *previous message* (if any) is used.

--- The event signals the **end of the progress reporting** with a final message.
--- This event should **only** be sent if the corresponding capability `supportsProgressReporting` is `true`.
---@class dap.ProgressEndEvent : dap.Event
---@field event "progressEnd" # Type of event.
---@field body dap.ProgressEndEventBody # Event-specific information.

--------------------------------------------------------------------------------
-- Reverse Requests (Adapter to Client)
--------------------------------------------------------------------------------

--- Arguments for `runInTerminal` request.
---@class dap.RunInTerminalRequestArguments
---@field args string[] List of arguments. The first argument is the command to run.
---@field cwd string Working directory for the command. For non-empty, valid paths this typically results in execution of a change directory command.
---@field kind? dap.RunInTerminalKindEnum What kind of terminal to launch. Defaults to `integrated` if not specified.
---@field title? string Title of the terminal.
---@field env? table<string, string|nil> Environment key-value pairs that are added to or removed from the default environment.<br>A string is a proper value for an environment variable. The value `nil` removes the variable from the environment.
---@field argsCanBeInterpretedByShell? boolean This property should only be set if the corresponding capability `supportsArgsCanBeInterpretedByShell` is true. If the client uses an intermediary shell to launch the application, then the client must not attempt to escape characters with special meanings for the shell. The user is fully responsible for escaping as needed and that arguments using special characters may not be portable across shells.

--- This request is sent from the debug adapter to the client to run a command in a terminal.
--- This is typically used to launch the debuggee in a terminal provided by the client.
--- This request should only be called if the corresponding client capability `supportsRunInTerminalRequest` is true.
--- Client implementations of `runInTerminal` are free to run the command however they choose including issuing the command to a command line interpreter (aka 'shell'). Argument strings passed to the `runInTerminal` request must arrive verbatim in the command to be run. As a consequence, clients which use a shell are responsible for escaping any special shell characters in the argument strings to prevent them from being interpreted (and modified) by the shell.
--- Some users may wish to take advantage of shell processing in the argument strings. For clients which implement `runInTerminal` using an intermediary shell, the `argsCanBeInterpretedByShell` property can be set to true. In this case the client is requested not to escape any special shell characters in the argument strings.
--- (Title: Reverse Requests)
---@class dap.RunInTerminalRequest : dap.Request
---@field command "runInTerminal"
---@field arguments dap.RunInTerminalRequestArguments

---@class dap.RunInTerminalResponseBody
---@field processId? integer The process ID. The value should be less than or equal to 2147483647 (2^31-1).
---@field shellProcessId? integer The process ID of the terminal shell. The value should be less than or equal to 2147483647 (2^31-1).

--- Response to `runInTerminal` request.
---@class dap.RunInTerminalResponse : dap.Response
---@field body dap.RunInTerminalResponseBody

--- Arguments for `startDebugging` request.
---@class dap.StartDebuggingRequestArguments
---@field configuration table Arguments passed to the new debug session. The arguments must only contain properties understood by the `launch` or `attach` requests of the debug adapter and they must not contain any client-specific properties (e.g. `type`) or client-specific features (e.g. substitutable 'variables').
---@field request dap.StartDebuggingRequestEnum Indicates whether the new debug session should be started with a `launch` or `attach` request.
---@field [string] any # Allows additional properties

--- This request is sent from the debug adapter to the client to start a new debug session of the same type as the caller.
--- This request should only be sent if the corresponding client capability `supportsStartDebuggingRequest` is true.
--- A client implementation of `startDebugging` should start a new debug session (of the same type as the caller) in the same way that the caller's session was started. If the client supports hierarchical debug sessions, the newly created session can be treated as a child of the caller session.
---@class dap.StartDebuggingRequest : dap.Request
---@field command "startDebugging"
---@field arguments dap.StartDebuggingRequestArguments

--- Response to `startDebugging` request. This is just an acknowledgement, so no body field is required.
---@class dap.StartDebuggingResponse : dap.Response

--------------------------------------------------------------------------------
-- Other Supporting Type Definitions
--------------------------------------------------------------------------------

--- A `ColumnDescriptor` specifies what module attribute to show in a column of the modules view, how to format it,
--- and what the column's label should be.
--- It is only used if the underlying UI actually supports this level of customization.
---@class dap.ColumnDescriptor
---@field attributeName string Name of the attribute rendered in this column.
---@field label string Header UI label of column.
---@field format? string Format to use for the rendered values in this column. TBD how the format strings looks like.
---@field type? dap.ColumnDescriptorTypeEnum Datatype of values in this column. Defaults to `string` if not specified.
---@field width? integer Width of this column in characters (hint only).

--- A Stackframe contains the source location.
---@class dap.StackFrame
---@field id integer An identifier for the stack frame. It must be unique across all threads.<br>This id can be used to retrieve the scopes of the frame with the `scopes` request or to restart the execution of a stack frame.
---@field name string The name of the stack frame, typically a method name.
---@field line integer The line within the source of the frame. If the source attribute is missing or doesn't exist, `line` is 0 and should be ignored by the client.
---@field column integer Start position of the range covered by the stack frame. It is measured in UTF-16 code units and the client capability `columnsStartAt1` determines whether it is 0- or 1-based. If attribute `source` is missing or doesn't exist, `column` is 0 and should be ignored by the client.
---@field source? dap.Source The source of the frame.
---@field endLine? integer The end line of the range covered by the stack frame.
---@field endColumn? integer End position of the range covered by the stack frame. It is measured in UTF-16 code units and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field canRestart? boolean Indicates whether this frame can be restarted with the `restartFrame` request. Clients should only use this if the debug adapter supports the `restart` request and the corresponding capability `supportsRestartFrame` is true. If a debug adapter has this capability, then `canRestart` defaults to `true` if the property is absent.
---@field instructionPointerReference? string A memory reference for the current instruction pointer in this frame.
---@field moduleId? integer|string The module associated with this frame, if any.
---@field presentationHint? dap.StackFramePresentationHintEnum A hint for how to present this frame in the UI.<br>A value of `label` can be used to indicate that the frame is an artificial frame that is used as a visual label or separator. A value of `subtle` can be used to change the appearance of a frame in a 'subtle' way.

--- A `Scope` is a named container for variables. Optionally a scope can map to a source or a range within a source.
---@class dap.Scope
---@field name string Name of the scope such as 'Arguments', 'Locals', or 'Registers'. This string is shown in the UI as is and can be translated.
---@field variablesReference integer The variables of this scope can be retrieved by passing the value of `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object References' in the Overview section for details.
---@field expensive boolean If true, the number of variables in this scope is large or expensive to retrieve.
---@field presentationHint? dap.ScopePresentationHintEnum A hint for how to present this scope in the UI. If this attribute is missing, the scope is shown with a generic UI.
---@field namedVariables? integer The number of named variables in this scope.<br>The client can use this information to present the variables in a paged UI and fetch them in chunks.
---@field indexedVariables? integer The number of indexed variables in this scope.<br>The client can use this information to present the variables in a paged UI and fetch them in chunks.
---@field source? dap.Source The source for this scope.
---@field line? integer The start line of the range covered by this scope.
---@field column? integer Start position of the range covered by the scope. It is measured in UTF-16 code units and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.
---@field endLine? integer The end line of the range covered by this scope.
---@field endColumn? integer End position of the range covered by the scope. It is measured in UTF-16 code units and the client capability `columnsStartAt1` determines whether it is 0- or 1-based.

--- Properties of a variable that can be used to determine how to render the variable in the UI.
---@class dap.VariablePresentationHint
---@field kind? dap.VariablePresentationHintKindEnum The kind of variable. Before introducing additional values, try to use the listed values.
---@field attributes? dap.VariablePresentationHintAttributeEnum[] Set of attributes represented as an array of strings. Before introducing additional values, try to use the listed values.
---@field visibility? dap.VariablePresentationHintVisibilityEnum Visibility of variable. Before introducing additional values, try to use the listed values.
---@field lazy? boolean If true, clients can present the variable with a UI that supports a specific gesture to trigger its evaluation.<br>This mechanism can be used for properties that require executing code when retrieving their value and where the code execution can be expensive and/or produce side-effects. A typical example are properties based on a getter function.<br>Please note that in addition to the `lazy` flag, the variable's `variablesReference` is expected to refer to a variable that will provide the value through another `variable` request.

--- A Variable is a name/value pair.
--- The `type` attribute is shown if space permits or when hovering over the variable's name.
--- The `kind` attribute is used to render additional properties of the variable, e.g. different icons can be used to indicate that a variable is public or private.
--- If the value is structured (has children), a handle is provided to retrieve the children with the `variables` request.
--- If the number of named or indexed children is large, the numbers should be returned via the `namedVariables` and `indexedVariables` attributes.
--- The client can use this information to present the children in a paged UI and fetch them in chunks.
---@class dap.Variable
---@field name string The variable's name.
---@field value string The variable's value.<br>This can be a multi-line text, e.g. for a function the body of a function.<br>For structured variables (which do not have a simple value), it is recommended to provide a one-line representation of the structured object. This helps to identify the structured object in the collapsed state when its children are not yet visible.<br>An empty string can be used if no value should be shown in the UI.
---@field variablesReference integer If `variablesReference` is > 0, the variable is structured and its children can be retrieved by passing `variablesReference` to the `variables` request as long as execution remains suspended. See 'Lifetime of Object References' in the Overview section for details.
---@field type? string The type of the variable's value. Typically shown in the UI when hovering over the value.<br>This attribute should only be returned by a debug adapter if the corresponding capability `supportsVariableType` is true.
---@field presentationHint? dap.VariablePresentationHint Properties of a variable that can be used to determine how to render the variable in the UI.
---@field evaluateName? string The evaluatable name of this variable which can be passed to the `evaluate` request to fetch the variable's value.
---@field namedVariables? integer The number of named child variables.<br>The client can use this information to present the children in a paged UI and fetch them in chunks.
---@field indexedVariables? integer The number of indexed child variables.<br>The client can use this information to present the children in a paged UI and fetch them in chunks.
---@field memoryReference? string A memory reference associated with this variable.<br>For pointer type variables, this is generally a reference to the memory address contained in the pointer.<br>For executable data, this reference may later be used in a `disassemble` request.<br>This attribute may be returned by a debug adapter if corresponding capability `supportsMemoryReferences` is true.
---@field declarationLocationReference? integer A reference that allows the client to request the location where the variable is declared. This should be present only if the adapter is likely to be able to resolve the location.<br><br>This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview section for details.
---@field valueLocationReference? integer A reference that allows the client to request the location where the variable's value is declared. For example, if the variable contains a function pointer, the adapter may be able to look up the function's location. This should be present only if the adapter is likely to be able to resolve the location.<br><br>This reference shares the same lifetime as the `variablesReference`. See 'Lifetime of Object References' in the Overview section for details.

--- An `ExceptionBreakpointsFilter` is shown in the UI as a filter option for configuring how exceptions are dealt with.
---@class dap.ExceptionBreakpointsFilter
---@field filter string The internal ID of the filter option. This value is passed to the `setExceptionBreakpoints` request.
---@field label string The name of the filter option. This is shown in the UI.
---@field description? string A help text providing additional information about the exception filter. This string is typically shown as a hover and can be translated.
---@field default? boolean Initial value of the filter option. If not specified, a value `false` is assumed.
---@field supportsCondition? boolean Controls whether a condition can be specified for this filter option. If `false` or missing, a condition **cannot** be set.
---@field conditionDescription? string A help text providing information about the condition. This string is shown as the placeholder text for a text box and can be translated.

--- An `ExceptionFilterOptions` is used to specify an exception filter together with a condition for the `setExceptionBreakpoints` request.
---@class dap.ExceptionFilterOptions
---@field filterId string ID of an exception filter returned by the `exceptionBreakpointFilters` capability.
---@field condition? string An expression for conditional exceptions.<br>The exception breaks into the debugger if the result of the condition is `true`.
---@field mode? string The mode of this exception breakpoint. If defined, this **must be one** of the `breakpointModes` the debug adapter advertised in its `dap.Capabilities`.

--- An `ExceptionOptions` assigns configuration options to a set of exceptions.
---@class dap.ExceptionOptions
---@field breakMode dap.ExceptionBreakMode Condition when a thrown exception should result in a break.
---@field path? dap.ExceptionPathSegment[] A path that selects a single or multiple exceptions in a tree. If `path` is missing, the *whole tree* is selected.<br>By convention, the first segment of the path is a category that is used to group exceptions in the UI.

--- An `ExceptionPathSegment` represents a segment in a path that is used to match leafs or nodes in a tree of exceptions.
--- If a segment consists of more than one name, it matches the names provided if `negate` is `false` or missing, or it matches *anything except* the names provided if `negate` is `true`.
---@class dap.ExceptionPathSegment
---@field names string[] Depending on the value of `negate`, the names that should match or not match.
---@field negate? boolean If `false` or missing, this segment matches the names provided; otherwise, it matches *anything except* the names provided.

--- Detailed information about an exception that has occurred.
---@class dap.ExceptionDetails
---@field message? string Message contained in the exception.
---@field typeName? string Short type name of the exception object.
---@field fullTypeName? string Fully-qualified type name of the exception object.
---@field evaluateName? string An expression that can be evaluated in the current scope to obtain the exception object.
---@field stackTrace? string Stack trace at the time the exception was thrown.
---@field innerException? dap.ExceptionDetails[] Details of the exception contained by this exception, if any.

--- The checksum of an item calculated by the specified algorithm.
---@class dap.Checksum
---@field algorithm dap.ChecksumAlgorithm The algorithm used to calculate this checksum.
---@field checksum string Value of the checksum, encoded as a hexadecimal value.

--- Represents a single disassembled instruction.
---@class dap.DisassembledInstruction
---@field address string The address of the instruction. Treated as a hex value if prefixed with `0x`, or as a decimal value otherwise.
---@field instruction string Text representing the instruction and its operands, in an implementation-defined format.
---@field instructionBytes? string Raw bytes representing the instruction and its operands, in an implementation-defined format.
---@field symbol? string Name of the symbol that corresponds with the location of this instruction, if any.
---@field location? dap.Source Source location that corresponds to this instruction, if any.<br>Should **always be set** (if available) on the first instruction returned,<br>but can be *omitted afterwards* if this instruction maps to the same source file as the previous instruction.
---@field line? integer The line within the source location that corresponds to this instruction, if any.
---@field column? integer The column within the line that corresponds to this instruction, if any.
---@field endLine? integer The end line of the range that corresponds to this instruction, if any.
---@field endColumn? integer The end column of the range that corresponds to this instruction, if any.
---@field presentationHint? dap.DisassembledInstructionPresentationHintEnum A hint for how to present the instruction in the UI.

--- `CompletionItems` are the suggestions returned from the `completions` request.
---@class dap.CompletionItem
---@field label string The label of this completion item. By default, this is also the text that is inserted when selecting this completion.
---@field text? string If `text` is returned and not an empty string, then it is inserted *instead of* the `label`.
---@field sortText? string A string that should be used when comparing this item with other items. If not returned or an empty string, the `label` is used instead.
---@field detail? string A human-readable string with additional information about this item, like type or symbol information.
---@field type? dap.CompletionItemType The item's type. Typically, the client uses this information to render the item in the UI with an icon.
---@field start? integer Start position (within the `text` attribute of the `completions` request) where the completion text is added. The position is measured in UTF-16 code units, and the client capability `columnsStartAt1` determines whether it is 0- or 1-based. If the start position is omitted, the text is added at the location specified by the `column` attribute of the `completions` request.
---@field length? integer Length determines how many characters are overwritten by the completion text, and it is measured in UTF-16 code units. If missing, the value `0` is assumed, which results in the completion text being inserted.
---@field selectionStart? integer Determines the start of the new selection *after* the text has been inserted (or replaced). `selectionStart` is measured in UTF-16 code units and **must be** in the range `0` and length of the completion text. If omitted, the selection starts at the end of the completion text.
---@field selectionLength? integer Determines the length of the new selection *after* the text has been inserted (or replaced), and it is measured in UTF-16 code units. The selection **cannot extend beyond** the bounds of the completion text. If omitted, the length is assumed to be `0`.

--- Provides formatting information for a value.
---@class dap.ValueFormat
---@field hex? boolean Display the value in hex.

--- Provides formatting information for a stack frame.
---@class dap.StackFrameFormat : dap.ValueFormat
---@field parameters? boolean Displays parameters for the stack frame.
---@field parameterTypes? boolean Displays the types of parameters for the stack frame.
---@field parameterNames? boolean Displays the names of parameters for the stack frame.
---@field parameterValues? boolean Displays the values of parameters for the stack frame.
---@field line? boolean Displays the line number of the stack frame.
---@field module? boolean Displays the module of the stack frame.
---@field includeAll? boolean Includes **all** stack frames, including those the debug adapter *might otherwise hide*.

--------------------------------------------------------------------------------
-- Tools
--------------------------------------------------------------------------------

---@alias dap.AnyEvent dap.BreakpointEvent | dap.CapabilitiesEvent | dap.ContinuedEvent | dap.ExitedEvent | dap.InitializedEvent | dap.InvalidatedEvent | dap.LoadedSourceEvent | dap.MemoryEvent | dap.ModuleEvent | dap.OutputEvent | dap.ProcessEvent | dap.ProgressEndEvent | dap.ProgressStartEvent | dap.ProgressUpdateEvent | dap.StoppedEvent | dap.TerminatedEvent | dap.ThreadEvent
---@alias dap.AnyEventName "breakpoint" | "capabilities" | "continued" | "exited" | "initialized" | "invalidated" | "loadedSource" | "memory" | "module" | "output" | "process" | "progressEnd" | "progressStart" | "progressUpdate" | "stopped" | "terminated" | "thread"
---@alias dap.AnyEventBody dap.BreakpointEventBody | dap.CapabilitiesEventBody | dap.ContinuedEventBody | dap.ExitedEventBody | dap.InitializedEventBody | dap.InvalidatedEventBody | dap.LoadedSourceEventBody | dap.MemoryEventBody | dap.ModuleEventBody | dap.OutputEventBody | dap.ProcessEventBody | dap.ProgressEndEventBody | dap.ProgressStartEventBody | dap.ProgressUpdateEventBody | dap.StoppedEventBody | dap.TerminatedEventBody | dap.ThreadEventBody

---@alias dap.AnyRequest dap.AttachRequest | dap.BreakpointLocationsRequest | dap.CompletionsRequest | dap.ConfigurationDoneRequest | dap.ContinueRequest | dap.DataBreakpointInfoRequest | dap.DisassembleRequest | dap.DisconnectRequest | dap.EvaluateRequest | dap.ExceptionInfoRequest | dap.GotoRequest | dap.GotoTargetsRequest | dap.InitializeRequest | dap.LaunchRequest | dap.LoadedSourcesRequest | dap.LocationsRequest | dap.ModulesRequest | dap.NextRequest | dap.PauseRequest | dap.ReadMemoryRequest | dap.RestartRequest | dap.RestartFrameRequest | dap.ReverseContinueRequest | dap.ScopesRequest | dap.SetBreakpointsRequest | dap.SetDataBreakpointsRequest | dap.SetExceptionBreakpointsRequest | dap.SetExpressionRequest | dap.SetFunctionBreakpointsRequest | dap.SetInstructionBreakpointsRequest | dap.SetVariableRequest | dap.SourceRequest | dap.StackTraceRequest | dap.StepBackRequest | dap.StepInRequest | dap.StepInTargetsRequest | dap.StepOutRequest | dap.TerminateRequest | dap.TerminateThreadsRequest | dap.ThreadsRequest | dap.VariablesRequest | dap.WriteMemoryRequest
---@alias dap.AnyRequestCommand "attach" | "breakpointLocations" | "completions" | "configurationDone" | "continue" | "dataBreakpointInfo" | "disassemble" | "disconnect" | "evaluate" | "exceptionInfo" | "goto" | "gotoTargets" | "initialize" | "launch" | "loadedSources" | "locations" | "modules" | "next" | "pause" | "readMemory" | "restart" | "restartFrame" | "reverseContinue" | "scopes" | "setBreakpoints" | "setDataBreakpoints" | "setExceptionBreakpoints" | "setExpression" | "setFunctionBreakpoints" | "setInstructionBreakpoints" | "setVariable" | "source" | "stackTrace" | "stepBack" | "stepIn" | "stepInTargets" | "stepOut" | "terminateThreads"
---@alias dap.AnyResponse dap.AttachResponse | dap.BreakpointLocationsResponse | dap.CompletionsResponse | dap.ConfigurationDoneResponse | dap.ContinueResponse | dap.DataBreakpointInfoResponse | dap.DisassembleResponse | dap.DisconnectResponse | dap.EvaluateResponse | dap.ExceptionInfoResponse | dap.GotoResponse | dap.GotoTargetsResponse | dap.InitializeResponse | dap.LaunchResponse | dap.LoadedSourcesResponse | dap.LocationsResponse | dap.ModulesResponse | dap.NextResponse | dap.PauseResponse | dap.ReadMemoryResponse | dap.RestartResponse | dap.RestartFrameResponse | dap.ReverseContinueResponse | dap.ScopesResponse | dap.SetBreakpointsResponse | dap.SetDataBreakpointsResponse | dap.SetExceptionBreakpointsResponse | dap.SetExpressionResponse | dap.SetFunctionBreakpointsResponse | dap.SetInstructionBreakpointsResponse | dap.SetVariableResponse | dap.SourceResponse | dap.StackTraceResponse | dap.StepBackResponse | dap.StepInResponse | dap.StepInTargetsResponse | dap.StepOutResponse | dap.TerminateResponse | dap.TerminateThreadsResponse | dap.ThreadsResponse | dap.VariablesResponse | dap.WriteMemoryResponse

---@alias dap.AnyReverseRequest dap.RunInTerminalRequest | dap.StartDebuggingRequest
---@alias dap.AnyReverseRequestArguments dap.RunInTerminalRequestArguments | dap.StartDebuggingRequestArguments
---@alias dap.AnyReverseRequestCommand "runInTerminal" | "startDebugging"
---@alias dap.AnyReverseResponse dap.RunInTerminalResponse | dap.StartDebuggingResponse

---@alias dap.AnyIncomingMessage dap.AnyEvent | dap.AnyReverseRequest | dap.AnyResponse
---@alias dap.AnyOutgoingMessage dap.AnyRequest | dap.AnyReverseResponse
---@alias dap.AnyMessage dap.AnyIncomingMessage | dap.AnyOutgoingMessage
