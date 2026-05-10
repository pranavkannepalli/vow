import Foundation

/// Verifies (at runtime) whether Vow is safe to enable Screen Time / Family Controls flows.
///
/// This module is intentionally defensive:
/// - If FamilyControls.framework is not available at runtime, we treat capability as unknown.
/// - We gate shield application behind an authorization check and (optionally) a required extension presence check.
public struct FamilyControlsCapabilityGate {
    public enum State: Hashable {
        /// Family Controls authorization appears approved.
        case authorized
        /// Family Controls authorization appears denied.
        case notAuthorized
        /// Could not determine authorization status.
        case unknown(message: String)
    }
}

extension FamilyControlsCapabilityGate.State: Codable {
    private enum CodingKeys: String, CodingKey { case type, message }
    private enum Kind: String, Codable { case authorized, notAuthorized, unknown }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .authorized:
            try container.encode(Kind.authorized, forKey: .type)
        case .notAuthorized:
            try container.encode(Kind.notAuthorized, forKey: .type)
        case .unknown(let message):
            try container.encode(Kind.unknown, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .authorized:
            self = .authorized
        case .notAuthorized:
            self = .notAuthorized
        case .unknown:
            self = .unknown(message: (try? container.decode(String.self, forKey: .message)) ?? "unknown")
        }
    }
}

public struct ScreenTimeCapabilityVerificationReport: Codable, Hashable {
    public var familyControlsAuthorizationState: FamilyControlsCapabilityGate.State

    /// Bundle identifiers that the host app believes are required to safely enable the feature set.
    public var requiredExtensionBundleIdentifiers: [String]

    /// Bundle identifiers present inside the host app's built-in plug-ins folder (best-effort).
    public var presentExtensionBundleIdentifiers: [String]

    public var missingExtensionBundleIdentifiers: [String]

    public var isReady: Bool {
        guard familyControlsAuthorizationState == .authorized else { return false }
        return missingExtensionBundleIdentifiers.isEmpty
    }

    public init(
        familyControlsAuthorizationState: FamilyControlsCapabilityGate.State,
        requiredExtensionBundleIdentifiers: [String] = [],
        presentExtensionBundleIdentifiers: [String] = [],
        missingExtensionBundleIdentifiers: [String] = []
    ) {
        self.familyControlsAuthorizationState = familyControlsAuthorizationState
        self.requiredExtensionBundleIdentifiers = requiredExtensionBundleIdentifiers
        self.presentExtensionBundleIdentifiers = presentExtensionBundleIdentifiers
        self.missingExtensionBundleIdentifiers = missingExtensionBundleIdentifiers
    }
}

extension FamilyControlsCapabilityGate {
    /// Returns the current runtime authorization state.
    ///
    /// Implementation note:
    /// We avoid hard compile-time dependencies on FamilyControls by using best-effort runtime inspection.
    public static func currentAuthorizationState() -> State {
        // Use runtime lookup so this can compile on non-iOS environments.
        let classNameCandidates = [
            "FamilyControls.AuthorizationCenter",
            "AuthorizationCenter"
        ]

        let authorizationCenterObj: AnyObject? = classNameCandidates
            .compactMap { NSClassFromString($0) }
            .first
            .map { $0.perform(NSSelectorFromString("shared"))?.takeUnretainedValue() }

        guard let authorizationCenterObj else {
            return .unknown(message: "AuthorizationCenter not found at runtime")
        }

        guard let statusObj = authorizationCenterObj
            .perform(NSSelectorFromString("authorizationStatus"))?
            .takeUnretainedValue() else {
            return .unknown(message: "authorizationStatus not available")
        }

        let statusDescription = String(describing: statusObj)
        return stateFromAuthorizationStatusDescription(statusDescription)
    }

    /// Maps a runtime authorization status description into our safe gate states.
    ///
    /// Keep this mapping conservative: if we cannot match, return `.unknown`.
    public static func stateFromAuthorizationStatusDescription(_ description: String) -> State {
        let lower = description.lowercased()

        if lower.contains("approved") || lower == "authorizationstatus.authorized" || lower.contains("authorized") {
            return .authorized
        }

        if lower.contains("denied") || lower.contains("notauthorized") || lower.contains("not authorized") {
            return .notAuthorized
        }

        return .unknown(message: description)
    }

    public static func computeMissingExtensions(
        requiredExtensionBundleIdentifiers: [String],
        presentExtensionBundleIdentifiers: Set<String>
    ) -> [String] {
        requiredExtensionBundleIdentifiers.filter { !presentExtensionBundleIdentifiers.contains($0) }
    }

    /// Best-effort enumeration of extension bundle identifiers from the host app's built-in plug-ins.
    ///
    /// Returns `[]` if this can't be enumerated (e.g. tests, non-iOS runtime).
    public static func presentExtensionBundleIdentifiers() -> Set<String> {
        #if os(iOS) || os(tvOS) || os(watchOS)
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else { return [] }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var bundleIDs = Set<String>()
        for item in contents {
            guard let bundle = Bundle(url: item) else { continue }
            if let id = bundle.bundleIdentifier {
                bundleIDs.insert(id)
            }
        }
        return bundleIDs
        #else
        return []
        #endif
    }

    /// Full verification report for the current runtime.
    public static func verify(
        requiredExtensionBundleIdentifiers: [String] = []
    ) -> ScreenTimeCapabilityVerificationReport {
        let authState = currentAuthorizationState()
        let present = presentExtensionBundleIdentifiers()
        let missing = computeMissingExtensions(
            requiredExtensionBundleIdentifiers: requiredExtensionBundleIdentifiers,
            presentExtensionBundleIdentifiers: present
        )

        return ScreenTimeCapabilityVerificationReport(
            familyControlsAuthorizationState: authState,
            requiredExtensionBundleIdentifiers: requiredExtensionBundleIdentifiers,
            presentExtensionBundleIdentifiers: Array(present).sorted(),
            missingExtensionBundleIdentifiers: missing.sorted()
        )
    }
}
