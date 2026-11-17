import Foundation

/// Lifecycle contract for a future long-lived Minecraft JVM session.
/// It intentionally contains no JNI calls; the native supervisor must emit these events.
public enum HinekaGameSessionState: Equatable, CustomStringConvertible {
    case idle
    case preparing
    case starting
    case running
    case stopping
    case exited(Int32)
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .preparing, .starting, .running, .stopping:
            return true
        case .idle, .exited, .failed:
            return false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .exited, .failed:
            return true
        case .idle, .preparing, .starting, .running, .stopping:
            return false
        }
    }

    public var description: String {
        switch self {
        case .idle: return "idle"
        case .preparing: return "preparing"
        case .starting: return "starting"
        case .running: return "running"
        case .stopping: return "stopping"
        case .exited(let code): return "exited (code \(code))"
        case .failed(let message): return "failed: \(message)"
        }
    }
}

public enum HinekaGameSessionEvent: Equatable {
    case beginPreparation
    case preflightChecked
    case didStart
    case requestStop
    case didExit(Int32)
    case didFail(String)
    case reset
}

public enum HinekaGameSessionStateMachineError: LocalizedError {
    case invalidTransition(from: HinekaGameSessionState, event: HinekaGameSessionEvent)

    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let state, let event):
            return "Không thể áp dụng sự kiện \(event) khi game session đang ở trạng thái \(state)."
        }
    }
}

/// A deterministic state machine for the future game process supervisor.
/// The preflight report is mandatory before this machine can enter the starting state.
public struct HinekaGameSessionStateMachine {
    public private(set) var state: HinekaGameSessionState = .idle

    public init() {}

    /// Completes preparation only when runtime, renderer and launch-plan checks all pass.
    /// A failed report moves the session to a terminal failed state and never reaches starting.
    @discardableResult
    public mutating func completePreflight(
        _ report: HinekaGameStartupPreflightReport
    ) throws -> HinekaGameSessionState {
        guard state == .preparing else {
            throw HinekaGameSessionStateMachineError.invalidTransition(
                from: state,
                event: .preflightChecked
            )
        }
        state = report.canStart ? .starting : .failed(report.summary)
        return state
    }

    @discardableResult
    public mutating func apply(_ event: HinekaGameSessionEvent) throws -> HinekaGameSessionState {
        switch (state, event) {
        case (.idle, .beginPreparation):
            state = .preparing
        case (.starting, .didStart):
            state = .running
        case (.starting, .requestStop), (.running, .requestStop):
            state = .stopping
        case (.starting, .didExit(let code)),
             (.running, .didExit(let code)),
             (.stopping, .didExit(let code)):
            state = .exited(code)
        case (.preparing, .didFail(let message)),
             (.starting, .didFail(let message)),
             (.running, .didFail(let message)),
             (.stopping, .didFail(let message)):
            state = .failed(message)
        case (.exited, .reset), (.failed, .reset):
            state = .idle
        default:
            throw HinekaGameSessionStateMachineError.invalidTransition(from: state, event: event)
        }
        return state
    }
}
