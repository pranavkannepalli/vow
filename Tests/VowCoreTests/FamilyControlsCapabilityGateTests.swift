import XCTest
@testable import VowCore

final class FamilyControlsCapabilityGateTests: XCTestCase {
    func test_stateFromAuthorizationStatusDescription_mapsApprovedToAuthorized() {
        XCTAssertEqual(
            FamilyControlsCapabilityGate.stateFromAuthorizationStatusDescription("approved"),
            .authorized
        )
        XCTAssertEqual(
            FamilyControlsCapabilityGate.stateFromAuthorizationStatusDescription("AuthorizationStatus.authorized"),
            .authorized
        )
    }

    func test_stateFromAuthorizationStatusDescription_mapsDeniedToNotAuthorized() {
        XCTAssertEqual(
            FamilyControlsCapabilityGate.stateFromAuthorizationStatusDescription("denied"),
            .notAuthorized
        )
        XCTAssertEqual(
            FamilyControlsCapabilityGate.stateFromAuthorizationStatusDescription("not authorized"),
            .notAuthorized
        )
    }

    func test_stateFromAuthorizationStatusDescription_unknownFallsBackToUnknown() {
        let state = FamilyControlsCapabilityGate.stateFromAuthorizationStatusDescription("some new status")
        switch state {
        case .unknown:
            break
        default:
            XCTFail("Expected unknown")
        }
    }

    func test_computeMissingExtensions_returnsOnlyMissing() {
        let required = [
            "com.example.ShieldConfigurationExtension",
            "com.example.ShieldActionExtension",
            "com.example.DeviceActivityExtension"
        ]
        let present: Set<String> = [
            "com.example.ShieldConfigurationExtension",
            "com.example.DeviceActivityExtension"
        ]

        let missing = FamilyControlsCapabilityGate.computeMissingExtensions(
            requiredExtensionBundleIdentifiers: required,
            presentExtensionBundleIdentifiers: present
        )

        XCTAssertEqual(Set(missing), Set(["com.example.ShieldActionExtension"]))
    }
}
