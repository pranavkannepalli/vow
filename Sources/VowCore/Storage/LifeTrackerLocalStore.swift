import Foundation

/// A minimal, local-only persistence layer for Vow’s life logging.
///
/// Design goals for v1:
/// - store everything on-device
/// - keep telemetry off by default (no network in this module)
/// - support user export + delete (privacy-first founder trust)
public final class LifeTrackerLocalStore {
    public enum StoreError: Error {
        case corruptedFile(String)
    }

    public struct ExportEnvelope: Codable {
        public var userID: UUID
        public var exportedAt: Date
        public var events: [LifeTrackerEvent]
        public var dayRecords: [LifeTrackerDayRecord]
    }

    public struct LocalStorePaths {
        public var eventsURL: URL
        public var dayRecordsURL: URL

        public init(eventsURL: URL, dayRecordsURL: URL) {
            self.eventsURL = eventsURL
            self.dayRecordsURL = dayRecordsURL
        }
    }

    private let calendar: Calendar
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let pointPolicy: LifeTrackerPointPolicy

    public init(
        calendar: Calendar = .current,
        pointPolicy: LifeTrackerPointPolicy = .init(),
        fileManager: FileManager = .default
    ) {
        self.calendar = calendar
        self.pointPolicy = pointPolicy
        self.fileManager = fileManager

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func paths(for userID: UUID) -> LocalStorePaths {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        // Keep filenames stable and user-scoped.
        let eventsURL = base.appendingPathComponent("vow_lifetracker_events_\(userID.uuidString).json")
        let dayRecordsURL = base.appendingPathComponent("vow_lifetracker_day_records_\(userID.uuidString).json")
        return .init(eventsURL: eventsURL, dayRecordsURL: dayRecordsURL)
    }

    // MARK: - Events

    public func loadEvents(userID: UUID) throws -> [LifeTrackerEvent] {
        let url = paths(for: userID).eventsURL
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([LifeTrackerEvent].self, from: data)
        } catch {
            throw StoreError.corruptedFile("events")
        }
    }

    public func appendEvents(_ newEvents: [LifeTrackerEvent], userID: UUID) throws {
        guard !newEvents.isEmpty else { return }

        // Safety: ensure events match the requested user.
        let filtered = newEvents.filter { $0.userID == userID }
        let dropped = newEvents.count - filtered.count
        _ = dropped // kept for debugging, but no logging/telemetry here.

        var events = try loadEvents(userID: userID)
        events.append(contentsOf: filtered)
        events.sort { $0.occurredAt < $1.occurredAt }

        try atomicWrite(events, to: paths(for: userID).eventsURL)

        // Update day records for the affected local days.
        let affectedDays = Set(filtered.map { calendar.startOfDay(for: $0.occurredAt) })
        var dayRecords = try loadDayRecords(userID: userID)

        let engine = LifeTrackerEngine(pointPolicy: pointPolicy)
        for day in affectedDays {
            let dayStart = calendar.startOfDay(for: day)
            let existing = dayRecords.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) })
            let dayEvents = events.filter { calendar.isDate($0.occurredAt, inSameDayAs: dayStart) && $0.userID == userID }

            let updated = engine.upsertDailySummary(
                existing: existing,
                userID: userID,
                date: dayStart,
                events: dayEvents,
                calendar: calendar
            )

            if let idx = dayRecords.firstIndex(where: { $0.id == updated.id }) {
                dayRecords[idx] = updated
            } else {
                dayRecords.append(updated)
            }
        }

        dayRecords.sort { $0.date < $1.date }
        try atomicWrite(dayRecords, to: paths(for: userID).dayRecordsURL)
    }

    // MARK: - Day records

    public func loadDayRecords(userID: UUID) throws -> [LifeTrackerDayRecord] {
        let url = paths(for: userID).dayRecordsURL
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([LifeTrackerDayRecord].self, from: data)
        } catch {
            throw StoreError.corruptedFile("dayRecords")
        }
    }

    // MARK: - Export / Delete

    /// Export weekly review data as JSON (shareable with host apps).
    public func exportWeeklyReviewJSON(
        userID: UUID,
        weekStart: Date,
        weekEnd: Date
    ) throws -> Data {
        let normalizedWeekStart = calendar.startOfDay(for: weekStart)
        let normalizedWeekEnd = calendar.startOfDay(for: weekEnd)

        let engine = LifeTrackerEngine(pointPolicy: pointPolicy)

        let events = try loadEvents(userID: userID)
        let storedDayRecords = try loadDayRecords(userID: userID)
        let storedByDay = Dictionary(grouping: storedDayRecords, by: { calendar.startOfDay(for: $0.date) })

        // Build the day record list (generate missing days from events).
        var days: [LifeTrackerDayRecord] = []
        var cursor = normalizedWeekStart
        while cursor <= normalizedWeekEnd {
            let dayEvents = events.filter { $0.userID == userID && calendar.isDate($0.occurredAt, inSameDayAs: cursor) }
            if dayEvents.isEmpty {
                // Still include a “zero” record so the review UI can render complete weeks.
                let record = engine.upsertDailySummary(
                    existing: storedByDay[cursor]?.first,
                    userID: userID,
                    date: cursor,
                    events: dayEvents,
                    calendar: calendar
                )
                days.append(record)
            } else {
                let existing = storedByDay[cursor]?.first
                let record = engine.upsertDailySummary(
                    existing: existing,
                    userID: userID,
                    date: cursor,
                    events: dayEvents,
                    calendar: calendar
                )
                days.append(record)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let review = engine.generateWeeklyReview(
            weekStart: normalizedWeekStart,
            weekEnd: normalizedWeekEnd,
            days: days,
            calendar: calendar
        )

        let data = try encoder.encode(review)
        return data
    }

    /// Export weekly review as a JSON file payload for host apps to share.
    ///
    /// - Returns: (data, filename, mimeType)
    public func exportWeeklyReviewFile(
        userID: UUID,
        weekStart: Date,
        weekEnd: Date
    ) throws -> (data: Data, filename: String, mimeType: String) {
        let data = try exportWeeklyReviewJSON(userID: userID, weekStart: weekStart, weekEnd: weekEnd)
        let s = formatISODate(weekStart)
        let e = formatISODate(weekEnd)
        let filename = "vow_weekly_review_\(s)_to_\(e).json"
        return (data: data, filename: filename, mimeType: "application/json")
    }

    /// Export all local life logging data as JSON.
    public func exportAllDataJSON(userID: UUID) throws -> Data {
        let events = try loadEvents(userID: userID)
        let dayRecords = try loadDayRecords(userID: userID)

        let envelope = ExportEnvelope(
            userID: userID,
            exportedAt: Date(),
            events: events,
            dayRecords: dayRecords
        )
        return try encoder.encode(envelope)
    }

    public func deleteAll(userID: UUID) throws {
        let p = paths(for: userID)
        if fileManager.fileExists(atPath: p.eventsURL.path) {
            try fileManager.removeItem(at: p.eventsURL)
        }
        if fileManager.fileExists(atPath: p.dayRecordsURL.path) {
            try fileManager.removeItem(at: p.dayRecordsURL)
        }
    }

    // MARK: - Internals

    private func formatISODate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    private func atomicWrite<T: Encodable>(_ value: T, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(value)

        // Write to a temp file then swap.
        let tmp = url.appendingPathExtension(".tmp")
        try data.write(to: tmp, options: [.atomic])
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: tmp, to: url)
    }
}
