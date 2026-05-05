import Foundation

/// Opaque representation of an NFC card.
///
/// Production note: this should typically be derived from the card UID/
/// identifier and *hashed* (so raw identifiers aren’t stored).
public struct NfcCardFingerprint: Codable, Hashable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

public protocol NfcEnrollmentStore: Sendable {
    /// Associates an enrolled NFC card fingerprint with a specific unlock target.
    func enroll(targetID: UUID, fingerprint: NfcCardFingerprint) throws

    /// Returns whether the provided fingerprint is enrolled for the target.
    func isEnrolled(targetID: UUID, fingerprint: NfcCardFingerprint) throws -> Bool
}

/// Test/dev implementation.
public final class InMemoryNfcEnrollmentStore: NfcEnrollmentStore {
    private var enrolled: [UUID: Set<NfcCardFingerprint>] = [:]

    public init() {}

    public func enroll(targetID: UUID, fingerprint: NfcCardFingerprint) throws {
        enrolled[targetID, default: []].insert(fingerprint)
    }

    public func isEnrolled(targetID: UUID, fingerprint: NfcCardFingerprint) throws -> Bool {
        enrolled[targetID]?.contains(fingerprint) ?? false
    }
}

/// Wires an enrolled-card store into `NfcRuntimeEnforcer`.
public enum NfcVerificationFactory {
    /// Creates a verifier closure suitable for `NfcRuntimeEnforcer`.
    ///
    /// Fail-safe behavior: if reading the card fails, this returns `false`
    /// (which triggers enforcement alarm + deny).
    public static func makeVerifier(
        targetID: UUID,
        store: any NfcEnrollmentStore,
        readFingerprint: @Sendable @escaping () async throws -> NfcCardFingerprint
    ) -> () async throws -> Bool {
        return {
            do {
                let fingerprint = try await readFingerprint()
                return try store.isEnrolled(targetID: targetID, fingerprint: fingerprint)
            } catch {
                return false
            }
        }
    }

    /// Convenience for constructing a runtime enforcer for a specific target.
    public static func makeRuntimeEnforcer(
        targetID: UUID,
        store: any NfcEnrollmentStore,
        cardReader: @Sendable @escaping () async throws -> NfcCardFingerprint,
        scheduler: any AlarmScheduling,
        gracePeriodSeconds: TimeInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> NfcRuntimeEnforcer {
        let verifier = makeVerifier(targetID: targetID, store: store, readFingerprint: cardReader)
        return NfcRuntimeEnforcer(
            verifier: verifier,
            scheduler: scheduler,
            gracePeriodSeconds: gracePeriodSeconds,
            now: now
        )
    }
}
