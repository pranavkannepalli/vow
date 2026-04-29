import Foundation

public struct BlockedTarget: Codable, Hashable, Identifiable {
    public enum RiskLevel: String, Codable, CaseIterable {
        case low, medium, high
    }

    public enum TargetType: Codable, Hashable {
        case application(Data)
        case category(Data)
        case webDomain(Data)
    }

    public let id: UUID
    public let type: TargetType
    public let riskLevel: RiskLevel
    public let label: String?

    public init(
        id: UUID = UUID(),
        type: TargetType,
        riskLevel: RiskLevel,
        label: String? = nil
    ) {
        self.id = id
        self.type = type
        self.riskLevel = riskLevel
        self.label = label
    }
}
