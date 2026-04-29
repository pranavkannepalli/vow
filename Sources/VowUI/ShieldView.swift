import VowCore

#if canImport(SwiftUI)
import SwiftUI

public struct ShieldView: View {
    public let label: String?
    public let riskLevel: BlockedTarget.RiskLevel

    public let onRequestUnlock: () -> Void

    public init(
        label: String? = nil,
        riskLevel: BlockedTarget.RiskLevel,
        onRequestUnlock: @escaping () -> Void
    ) {
        self.label = label
        self.riskLevel = riskLevel
        self.onRequestUnlock = onRequestUnlock
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("Shield")
                .font(.title2)

            if let label {
                Text(label)
                    .font(.headline)
            }

            Text("Risk: \(riskLevel.rawValue.capitalized)")
                .foregroundStyle(.secondary)

            Button("Request Unlock") {
                onRequestUnlock()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#endif
