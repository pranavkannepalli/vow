import XCTest
@testable import VowCore

final class NfcEnrollmentTests: XCTestCase {
    func testMakeVerifier_returnsTrue_whenFingerprintIsEnrolled() async throws {
        let store = InMemoryNfcEnrollmentStore()
        let targetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let fingerprint = NfcCardFingerprint(value: "fp-abc")

        try store.enroll(targetID: targetID, fingerprint: fingerprint)

        let verifier = NfcVerificationFactory.makeVerifier(
            targetID: targetID,
            store: store,
            readFingerprint: { fingerprint }
        )

        let result = try await verifier()
        XCTAssertTrue(result)
    }

    func testMakeVerifier_returnsFalse_whenFingerprintIsNotEnrolled() async throws {
        let store = InMemoryNfcEnrollmentStore()
        let targetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let verifier = NfcVerificationFactory.makeVerifier(
            targetID: targetID,
            store: store,
            readFingerprint: { NfcCardFingerprint(value: "fp-unknown") }
        )

        let result = try await verifier()
        XCTAssertFalse(result)
    }

    func testMakeVerifier_returnsFalse_whenReaderThrows() async throws {
        enum ReaderError: Error { case boom }

        let store = InMemoryNfcEnrollmentStore()
        let targetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let verifier = NfcVerificationFactory.makeVerifier(
            targetID: targetID,
            store: store,
            readFingerprint: { throw ReaderError.boom }
        )

        let result = try await verifier()
        XCTAssertFalse(result)
    }
}
