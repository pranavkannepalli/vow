import VowCore

#if canImport(SwiftUI)
import SwiftUI
import UIKit

public struct ProductivityDialView: View {
    // MARK: - Outputs

    public var onSessionCompleted: (() -> Void)?
    public var onSegmentCompleted: ((PomodoroSegment) -> Void)?

    // MARK: - Dial UX

    @State private var engine: PomodoroDialEngine
    @State private var tickLoopTask: Task<Void, Never>? = nil
    @State private var lastRemainingSeconds: TimeInterval = 0

    public init(
        focusDurationSeconds: TimeInterval = 25 * 60,
        restDurationSeconds: TimeInterval = 5 * 60,
        onSessionCompleted: (() -> Void)? = nil,
        onSegmentCompleted: ((PomodoroSegment) -> Void)? = nil
    ) {
        self.onSessionCompleted = onSessionCompleted
        self.onSegmentCompleted = onSegmentCompleted
        _engine = State(initialValue: PomodoroDialEngine(focusDurationSeconds: focusDurationSeconds, restDurationSeconds: restDurationSeconds))
    }

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                dialBase
                dialForeground
                dialContent
            }
            .frame(width: 220, height: 220)
            .gesture(rotationGesture)

            HStack(spacing: 12) {
                pauseResumeButton
                skipButton
            }

            VStack(spacing: 4) {
                Text(statusText)
                    .font(.headline)
                Text(timeText)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .onAppear {
            lastRemainingSeconds = engine.state.remainingSeconds
            syncTickLoop()
        }
        .onChange(of: engine.state.status) { _ in
            syncTickLoop()
        }
    }

    // MARK: - UI

    private var dialBase: some View {
        Circle().fill(Color(.systemGray6))
    }

    private var dialForeground: some View {
        let progress = progress01
        return Circle()
            .trim(from: 0, to: progress)
            .stroke(gradientColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.easeOut(duration: 0.2), value: progress)
    }

    private var dialContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.primary)
            Text(engine.state.segment == .focus ? "FOCUS" : (engine.state.segment == .rest ? "REST" : "SPIN"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }

    private var pauseResumeButton: some View {
        Button {
            switch engine.state.status {
            case .running:
                _ = engine.handle(.pauseTapped)
            case .paused:
                _ = engine.handle(.resumeTapped)
            default:
                break
            }
        } label: {
            Text(engine.state.status == .paused ? "Resume" : "Pause")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(!(engine.state.status == .running || engine.state.status == .paused))
    }

    private var skipButton: some View {
        Button {
            let analytics = engine.handle(.skipTapped)
            handleAnalytics(analytics)
        } label: {
            Text("Skip")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(!(engine.state.status == .running || engine.state.status == .paused))
    }

    private var rotationGesture: some Gesture {
        RotationGesture(minimumAngleDelta: .degrees(25))
            .onEnded { _ in
                // Dial-specific UX: "spin" starts; subsequent spins trigger skip.
                if engine.state.status == .idle {
                    let analytics = engine.handle(.spunToStart)
                    handleAnalytics(analytics)
                } else if engine.state.status == .running || engine.state.status == .paused {
                    let analytics = engine.handle(.skipTapped)
                    handleAnalytics(analytics)
                }
            }
    }

    private var statusText: String {
        switch engine.state.status {
        case .idle: return "Ready"
        case .running: return engine.state.segment == .focus ? "In Focus" : "Rest Break"
        case .paused: return "Paused"
        case .completed: return "Session Complete"
        }
    }

    private var timeText: String {
        let seconds = max(0, Int(engine.state.remainingSeconds.rounded()))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var progress01: Double {
        guard let segment = engine.state.segment else { return 0 }
        let total = (segment == .focus) ? engine.state.focusDurationSeconds : engine.state.restDurationSeconds
        guard total > 0 else { return 0 }
        return min(1, max(0, engine.state.remainingSeconds / total))
    }

    private var gradientColor: LinearGradient {
        let isFocus = engine.state.segment == .focus
        return LinearGradient(
            colors: isFocus ? [.green, .mint] : [.blue, .cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Loop + analytics

    @MainActor
    private func syncTickLoop() {
        tickLoopTask?.cancel()
        tickLoopTask = nil

        guard engine.state.status == .running else { return }

        tickLoopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                // If the user changed state, stop early.
                guard engine.state.status == .running else { return }

                let analytics = engine.handle(.ticked(seconds: 1))
                if engine.state.remainingSeconds != lastRemainingSeconds {
                    lastRemainingSeconds = engine.state.remainingSeconds
                }
                handleAnalytics(analytics)
            }
        }
    }

    @MainActor
    private func handleAnalytics(_ analytics: [PomodoroDialAnalyticsEvent]) {
        for event in analytics {
            switch event {
            case .segmentCompleted(let segment):
                onSegmentCompleted?(segment)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .sessionCompleted:
                onSessionCompleted?()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

#endif
