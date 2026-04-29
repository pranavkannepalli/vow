import Foundation

/// Steps data adapter provided by the host app (e.g. HealthKit).
public protocol StepsEvidenceDataSource {
    func stepsDelta(from start: Date, until end: Date) async throws -> Int
}

/// Focus data adapter provided by the host app.
public protocol FocusEvidenceDataSource {
    func focusSeconds(from start: Date, until end: Date) async throws -> TimeInterval
    func hasFocusInterruption(from start: Date, until end: Date) async throws -> Bool
}

/// Journal completion data adapter provided by the host app.
public protocol JournalEvidenceDataSource {
    func journalObservation(from start: Date, until end: Date) async throws -> JournalEvidenceObservation
}

public struct JournalEvidenceObservation: Codable, Hashable {
    public var characterCount: Int
    public var meaningfulTokenCount: Int?

    /// 0.0..1.0 where higher means more repetition/spam.
    public var spamRepetitionRatio: Double?

    public init(
        characterCount: Int,
        meaningfulTokenCount: Int? = nil,
        spamRepetitionRatio: Double? = nil
    ) {
        self.characterCount = characterCount
        self.meaningfulTokenCount = meaningfulTokenCount
        self.spamRepetitionRatio = spamRepetitionRatio
    }
}

