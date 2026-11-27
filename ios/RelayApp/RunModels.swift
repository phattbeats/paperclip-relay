import Foundation

/// Models for the run inspector.
///
/// The board's run records are large — a single heartbeat run serializes to
/// roughly 300 KB because it carries the controller lease, the identity
/// history and the runner profile. Decoding all of that on a phone to show
/// six fields would be the design that breaks on day one, so every model
/// here names only the fields the screen actually renders. Swift's decoder
/// ignores the rest.
///
/// Every shape below was read from a live run on the deployed board.
struct RunRecord: Codable, Identifiable, Hashable {
    let id: String
    let agentId: String?
    let issueId: String?
    let status: String?
    let startedAt: String?
    let finishedAt: String?
    let createdAt: String?
    let updatedAt: String?

    /// The one-line description of what the run is doing right now, as the
    /// board phrases it ("run phase: prepare_turn (172ms)").
    let currentStatusMessage: String?

    /// The tool the run is currently calling, when it is calling one.
    let currentToolName: String?

    /// The tail of the agent's last assistant message.
    let lastAssistantSnippet: String?

    let error: String?
    let errorCode: String?

    /// The board's own phase label for the run ("Working", "Confirming
    /// execution"), which is more readable than the raw stage.
    let execution: RunExecution?

    /// Why the board believes the run is alive, stalled or done.
    let livenessState: String?
    let livenessReason: String?

    let invocationSource: String?
    let triggerDetail: String?
    let adapterType: String?
    let runtimeMode: String?
    let scopeKind: String?

    /// Cost and tokens for the run. The board reports both camelCase and
    /// snake_case spellings, and which one is present depends on the
    /// adapter, so both are decoded and the camelCase one wins.
    let usageJson: RunUsage?

    /// The run's outcome, including whether a timeout fired.
    let resultJson: RunResult?

    let logBytes: Int?
    let scheduledRetryAt: String?
    let continuationAttempt: Int?

    /// What the phone shows as the run's headline cost.
    var costLabel: String? {
        guard let usd = usageJson?.costUsd ?? usageJson?.costUsdSnake else { return nil }
        return usd.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    var isRunning: Bool {
        guard let status else { return false }
        return status == "running" || status == "queued" || status == "pending"
    }
}

/// The board's per-run execution state.
struct RunExecution: Codable, Hashable {
    let phase: String?
    let label: String?
    let canStop: Bool?
    let cause: String?
}

/// Cost and token usage for a run.
struct RunUsage: Codable, Hashable {
    let costUsd: Double?
    let cost_usd: Double?
    let inputTokens: Int?
    let input_tokens: Int?
    let outputTokens: Int?
    let output_tokens: Int?
    let cachedInputTokens: Int?
    let cache_read_input_tokens: Int?
    let model: String?
    let provider: String?
    let billingType: String?
    let billing_type: String?

    var costUsdSnake: Double? { cost_usd }
    var resolvedInputTokens: Int? { inputTokens ?? input_tokens }
    var resolvedOutputTokens: Int? { outputTokens ?? output_tokens }
    var resolvedCachedTokens: Int? { cachedInputTokens ?? cache_read_input_tokens }
    var resolvedBillingType: String? { billingType ?? billing_type }
}

/// The run's outcome.
struct RunResult: Codable, Hashable {
    let stopReason: String?
    let timeoutFired: Bool?
    let timeoutSource: String?
    let effectiveTimeoutSec: Int?
}

/// One event in a run's stream.
struct RunEvent: Codable, Identifiable, Hashable {
    let id: Int
    let seq: Int?
    let eventType: String?
    let stream: String?
    let level: String?
    let message: String?
    let createdAt: String?

    /// Events carry a `payload` object the phone does not render. It ranges
    /// from a couple of bytes to tens of kilobytes for a single event, so
    /// the client asks for a bounded number of events and decodes only the
    /// fields above.
}

/// The issues a run touched.
struct RunIssueLink: Codable, Identifiable, Hashable {
    let issueId: String
    let identifier: String?
    let title: String?
    let status: String?
    let priority: String?

    var id: String { issueId }
}

/// The tail of a run's log.
///
/// The log endpoint returns NDJSON: one JSON object per line, each carrying
/// a timestamp, a stream name and a chunk of text. The phone renders the
/// chunks in order.
struct RunLog: Codable, Hashable {
    let runId: String?
    let store: String?
    let logRef: String?
    let content: String?
    let nextOffset: Int?

    /// The log's text, one line per record.
    ///
    /// A chunk that is not JSON is kept verbatim rather than dropped: the
    /// log is the one place where a stray line is evidence.
    var lines: [String] {
        guard let content, !content.isEmpty else { return [] }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { raw in
                guard let data = raw.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let chunk = object["chunk"] as? String else {
                    return String(raw)
                }
                return chunk.hasSuffix("\n") ? String(chunk.dropLast()) : chunk
            }
    }
}

/// A run as listed for an issue.
struct IssueRun: Codable, Identifiable, Hashable {
    let runId: String
    let status: String?
    let agentId: String?
    let adapterType: String?
    let startedAt: String?
    let finishedAt: String?
    let createdAt: String?
    let invocationSource: String?
    let errorCode: String?
    let error: String?
    let usageJson: RunUsage?
    let resultJson: RunResult?
    let livenessState: String?
    let livenessReason: String?
    let logBytes: Int?

    var id: String { runId }

    var costLabel: String? {
        guard let usd = usageJson?.costUsd ?? usageJson?.costUsdSnake else { return nil }
        return usd.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}
