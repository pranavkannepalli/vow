import Foundation

public enum PomodoroSegment: String, Codable, Equatable {
    case focus
    case rest
}

public enum PomodoroStatus: String, Codable, Equatable {
    case idle
    case running
    case paused
    case completed
}

public struct PomodoroDialState: Codable, Equatable {
    public var status: PomodoroStatus
    public var segment: PomodoroSegment?
    public var remainingSeconds: TimeInterval

    public var focusDurationSeconds: TimeInterval
    public var restDurationSeconds: TimeInterval

    public init(
        status: PomodoroStatus = .idle,
        segment: PomodoroSegment? = nil,
        remainingSeconds: TimeInterval = 0,
        focusDurationSeconds: TimeInterval = 25 * 60,
        restDurationSeconds: TimeInterval = 5 * 60
    ) {
        self.status = status
        self.segment = segment
        self.remainingSeconds = remainingSeconds
        self.focusDurationSeconds = focusDurationSeconds
        self.restDurationSeconds = restDurationSeconds
    }
}

public enum PomodoroDialEvent: Codable, Equatable {
    case spunToStart
    case pauseTapped
    case resumeTapped
    case skipTapped
    case ticked(seconds: TimeInterval)
}

public enum PomodoroDialAnalyticsEvent: Equatable {
    case segmentCompleted(PomodoroSegment)
    case sessionCompleted
}

/// Pure (no timers/UI) pomodoro control loop suitable for dial UX.
public struct PomodoroDialEngine: Codable, Equatable {
    public private(set) var state: PomodoroDialState

    public init(focusDurationSeconds: TimeInterval = 25 * 60, restDurationSeconds: TimeInterval = 5 * 60) {
        self.state = PomodoroDialState(
            focusDurationSeconds: focusDurationSeconds,
            restDurationSeconds: restDurationSeconds
        )
    }

    public mutating func handle(_ event: PomodoroDialEvent) -> [PomodoroDialAnalyticsEvent] {
        var analytics: [PomodoroDialAnalyticsEvent] = []

        switch event {
        case .spunToStart:
            guard state.status == .idle else { return analytics }
            state.status = .running
            state.segment = .focus
            state.remainingSeconds = state.focusDurationSeconds

        case .pauseTapped:
            guard state.status == .running else { return analytics }
            state.status = .paused

        case .resumeTapped:
            guard state.status == .paused else { return analytics }
            state.status = .running

        case .skipTapped:
            guard state.status == .running || state.status == .paused else { return analytics }
            analytics.append(contentsOf: completeCurrentSegmentAndAdvance())

        case .ticked(let seconds):
            guard state.status == .running else { return analytics }
            let clampedSeconds = max(0, seconds)
            guard clampedSeconds > 0 else { return analytics }

            state.remainingSeconds -= clampedSeconds

            // Handle overshoot by advancing multiple segments in one tick.
            while state.status == .running, state.remainingSeconds <= 0 {
                analytics.append(contentsOf: completeCurrentSegmentAndAdvance())
            }
        }

        return analytics
    }

    private mutating func completeCurrentSegmentAndAdvance() -> [PomodoroDialAnalyticsEvent] {
        guard let segment = state.segment else { return [] }

        var analytics: [PomodoroDialAnalyticsEvent] = []
        analytics.append(.segmentCompleted(segment))

        switch segment {
        case .focus:
            state.segment = .rest
            state.remainingSeconds = state.restDurationSeconds
            state.status = .running
        case .rest:
            state.segment = nil
            state.remainingSeconds = 0
            state.status = .completed
            analytics.append(.sessionCompleted)
        }

        return analytics
    }
}
