import Foundation

public struct FrictionPolicy: Codable, Hashable {
    public var lowSeconds: ClosedRange<Double>
    public var mediumSeconds: ClosedRange<Double>
    public var highSeconds: ClosedRange<Double>

    public init(
        lowSeconds: ClosedRange<Double> = 10...30,
        mediumSeconds: ClosedRange<Double> = 60...120,
        highSeconds: ClosedRange<Double> = 180...300
    ) {
        self.lowSeconds = lowSeconds
        self.mediumSeconds = mediumSeconds
        self.highSeconds = highSeconds
    }
}

public enum FrictionTier: String, Codable {
    case low
    case medium
    case high
}

public struct FrictionInputs: Codable, Hashable {
    public var tier: FrictionTier
    public var lateNight: Bool
    public var dailyScore: Double   // 0..100
    public var recentRelapseScore: Double
    public var priorUnlockCountToday: Int

    public init(
        tier: FrictionTier,
        lateNight: Bool = false,
        dailyScore: Double = 50,
        recentRelapseScore: Double = 0,
        priorUnlockCountToday: Int = 0
    ) {
        self.tier = tier
        self.lateNight = lateNight
        self.dailyScore = dailyScore
        self.recentRelapseScore = recentRelapseScore
        self.priorUnlockCountToday = priorUnlockCountToday
    }
}

/// v1 skeleton: computes an initial friction duration.
/// TODO: incorporate dynamic modifiers as per PRD.
public struct FrictionEngine: Codable {
    public var policy: FrictionPolicy

    public init(policy: FrictionPolicy = FrictionPolicy()) {
        self.policy = policy
    }

    public func seconds(for inputs: FrictionInputs, now: Date = Date()) -> Double {
        switch inputs.tier {
        case .low:
            return policy.lowSeconds.lowerBound
        case .medium:
            return policy.mediumSeconds.lowerBound
        case .high:
            return policy.highSeconds.lowerBound
        }
    }
}
