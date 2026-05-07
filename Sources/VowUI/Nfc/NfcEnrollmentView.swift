import VowCore

#if canImport(SwiftUI)
import SwiftUI

/// Minimal enrollment UX for binding an NFC card to a specific Vow target.
///
/// Real iOS wiring would use CoreNFC (or secure-element APIs) behind the
/// abstract `readFingerprint` closure.
public struct NfcEnrollmentView: View {
    public let target: BlockedTarget

    private let store: any NfcEnrollmentStore
    private let readFingerprint: @Sendable () async throws -> NfcCardFingerprint

    @State private var isEnrolling = false
    @State private var lastResult: String? = nil
    @State private var lastError: String? = nil

    public init(
        target: BlockedTarget,
        store: any NfcEnrollmentStore,
        readFingerprint: @escaping @Sendable () async throws -> NfcCardFingerprint
    ) {
        self.target = target
        self.store = store
        self.readFingerprint = readFingerprint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enroll NFC card")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Target: \(target.label ?? target.type.description)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Target ID: \(target.id.uuidString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button {
                isEnrolling = true
                lastError = nil
                lastResult = nil

                Task {
                    defer { isEnrolling = false }
                    do {
                        let fingerprint = try await readFingerprint()
                        try store.enroll(targetID: target.id, fingerprint: fingerprint)
                        lastResult = "Enrolled fingerprint: \(fingerprint.value.prefix(12))…"
                    } catch {
                        lastError = "Enrollment failed: \(error.localizedDescription)"
                    }
                }
            } label: {
                if isEnrolling {
                    ProgressView()
                } else {
                    Text("Tap card to enroll")
                }
            }
            .disabled(isEnrolling)

            if let lastResult {
                Text(lastResult)
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            if let lastError {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
        }
        .padding()
    }
}

private extension BlockedTarget.TargetType {
    var description: String {
        switch self {
        case .application: return "application"
        case .category: return "category"
        case .webDomain: return "webDomain"
        }
    }
}

#endif
