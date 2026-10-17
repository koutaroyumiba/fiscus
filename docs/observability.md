# Observability

## Status

Proposed. This document defines the intended observability boundaries; the event system described here is not yet implemented.

## Goals

Fiscus should make command execution and failures understandable without requiring a network service or telemetry collector.

Observability has four distinct outputs:

- **Command output:** stable user-facing results written to standard output.
- **Diagnostics:** actionable errors and warnings written to standard error.
- **Operational events:** structured local records describing command phases, durations, outcomes, validation failures, and persistence stages.
- **Audit history:** durable financial records such as journal transactions, provenance, reversals, and corrections.

Operational events must never substitute for accounting records or audit history.

## Privacy

Financial data is sensitive. Operational events must omit private journal content by default, including:

- amounts and prices;
- account names;
- transaction descriptions and notes;
- journal contents and source text;
- credentials and tokens;
- personally identifying values.

Events may record non-sensitive aggregate information when useful, such as input counts, elapsed time, phase names, result categories, and stable diagnostic codes.

Any future telemetry export must be optional and explicit. Local operation must not depend on telemetry infrastructure or network access.

## Operation identity

Each command execution should receive an operation ID. Every operational event emitted during that command should carry the same ID so that related events can be correlated.

Operation IDs identify executions, not financial transactions. They must not be written into the journal as accounting identifiers.

## Architecture

Observability side effects belong at application, CLI, and persistence boundaries—not inside pure accounting calculations.

Core code should return specific errors and useful structured context. Boundary code may translate those results into diagnostics and operational events through a small event-sink interface.

An illustrative interface is:

```zig
pub const EventSink = struct {
    context: *anyopaque,
    emitFn: *const fn (context: *anyopaque, event: Event) void,

    pub fn emit(self: EventSink, event: Event) void {
        self.emitFn(self.context, event);
    }
};
```

The final interface should remain synchronous and infallible unless concrete requirements justify additional complexity. A no-op sink should keep observability optional, while tests should be able to use an in-memory sink without parsing terminal output.

## Event model

An operational event should contain only the fields needed to understand execution:

- operation ID;
- event or phase name;
- start, completion, or failure outcome;
- elapsed duration where applicable;
- stable diagnostic code for known failures;
- non-sensitive counts where useful.

Initial command phases may include:

1. command start;
2. source discovery and reading;
3. parsing and decoding;
4. journal validation;
5. report calculation;
6. rendering;
7. persistence validation, writing, and replacement when mutation is added;
8. command completion or failure.

Report events may record report type, date-boundary interpretation, input counts, duration, and outcome, but must not record financial values.

## Diagnostics

Human-readable diagnostics and operational events serve different purposes:

- diagnostics explain a problem to the user and identify relevant source spans;
- operational events describe that a phase failed and classify the failure without copying private source content.

Stable diagnostic error codes should be shared between these layers where practical.

## Storage and retention

The first implementation should use structured local records. Before implementation, Fiscus should decide:

- whether records are JSON Lines or another simple format;
- the default storage location;
- whether recording is opt-in or enabled by default;
- rotation and retention behavior;
- file permissions and failure behavior;
- whether timestamps affect deterministic tests.

Failure to write an optional operational event should not corrupt or invalidate journal operations. Persistence events associated with journal mutation may require stricter handling and must be designed alongside atomic writes and recovery.

## Testing

Tests should verify that:

- related events share an operation ID;
- expected phases and outcomes are emitted;
- failures produce stable classifications;
- event payloads do not contain journal text or other private values;
- pure accounting calculations do not emit events directly;
- a no-op sink does not change command behavior;
- event capture does not require parsing stdout or stderr.

## Suggested implementation sequence

1. Define operation IDs and a small event type.
2. Add no-op and in-memory event sinks.
3. Instrument command start and completion.
4. Instrument load, decode, validate, and report-calculation boundaries.
5. Add stable diagnostic codes.
6. Choose a local structured-event format and retention policy.
7. Instrument persistence only when safe journal mutation is introduced.
8. Consider optional telemetry export only after local events are useful and privacy behavior is tested.
