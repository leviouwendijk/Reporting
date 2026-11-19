import DSL
import Foundation

public extension ReportBlock {
    /// Labeled values read at a glance: a summary header, not a dataset.
    struct Facts: Sendable, Codable, Hashable {
        public struct Fact: Sendable, Codable, Hashable {
            public let label: String
            public let value: String

            public init(_ label: String, _ value: String) {
                self.label = label
                self.value = value
            }
        }

        public let title: String?
        public let facts: [Fact]

        public init(title: String? = nil, facts: [Fact]) {
            self.title = title
            self.facts = facts
        }
    }

    /// Content set apart by tone: a recommendation, a warning, a gap.
    struct Callout: Sendable, Codable, Hashable {
        public enum Tone: String, Sendable, Codable, Hashable, CaseIterable {
            case info
            case success
            case warning
            case failure
        }

        public let tone: Tone
        public let title: String?
        public let content: StructuredContent

        public init(tone: Tone, title: String? = nil, content: StructuredContent) {
            self.tone = tone
            self.title = title
            self.content = content
        }
    }

    /// Lanes of intervals over one window, such as participants' days.
    struct Timeline: Sendable, Codable, Hashable {
        /// What a span means; renderers give each a distinct mark.
        public enum Mark: String, Sendable, Codable, Hashable, CaseIterable {
            /// Taken: a commitment, a busy block.
            case occupied
            /// Held back; usable only by escalation.
            case reserved
            /// Offered or open for use.
            case available
            /// The subject of the report, such as a proposed slot.
            case highlight
            /// Time spent moving between places.
            case transit
        }

        public struct Span: Sendable, Codable, Hashable {
            public let start: Date
            public let end: Date
            public let mark: Mark
            public let label: String?

            public init(start: Date, end: Date, mark: Mark, label: String? = nil) {
                self.start = start
                self.end = end
                self.mark = mark
                self.label = label
            }
        }

        public struct Lane: Sendable, Codable, Hashable {
            public let label: String
            public let spans: [Span]

            public init(label: String, spans: [Span]) {
                self.label = label
                self.spans = spans
            }
        }

        public let title: String?
        public let start: Date
        public let end: Date
        /// Zone the axis is labeled in; the renderer's zone when absent.
        public let timeZone: String?
        public let lanes: [Lane]

        public init(
            title: String? = nil,
            start: Date,
            end: Date,
            timeZone: String? = nil,
            lanes: [Lane]
        ) {
            self.title = title
            self.start = start
            self.end = end
            self.timeZone = timeZone
            self.lanes = lanes
        }

        public var zone: TimeZone {
            timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        }

        var isValid: Bool {
            start < end && lanes.allSatisfy { $0.spans.allSatisfy { $0.start <= $0.end } }
        }
    }

    /// One calendar event as a card: what, when, where and who, and how it
    /// sits in its day. A tool shapes its card through the optional parts
    /// and `details`, not through its own renderer.
    struct Event: Sendable, Codable, Hashable {
        /// What the card announces; nil for an event shown as it stands.
        public enum Change: String, Sendable, Codable, Hashable, CaseIterable {
            case create
            case update
            case cancel
        }

        public struct Interval: Sendable, Codable, Hashable {
            public let start: Date
            public let end: Date

            public init(start: Date, end: Date) {
                self.start = start
                self.end = end
            }
        }

        public let title: String
        public let interval: Interval
        /// Zone the times read in; the renderer's zone when absent.
        public let timeZone: String?
        public let allDay: Bool
        public let change: Change?
        /// Where an updated event was before.
        public let previous: Interval?
        public let calendar: String?
        public let location: String?
        public let attendees: [String]
        public let notes: String?
        /// How it repeats, in words: `every week, 5 times`.
        public let recurrence: String?
        /// Notifications, in minutes before the start.
        public let alerts: [Int]
        /// Time set aside to get there, in minutes before the start.
        public let travelMinutes: Int?
        public let url: String?
        /// Attached files or links, by name.
        public let attachments: [String]
        /// Tool-specific lines under the standard ones, e.g. a client number.
        public let details: [Facts.Fact]
        /// Overlaps and other things to weigh before deciding.
        public let warnings: [String]
        /// The surrounding day, usually with this event as the highlight.
        public let context: Timeline?

        public init(
            title: String,
            interval: Interval,
            timeZone: String? = nil,
            allDay: Bool = false,
            change: Change? = nil,
            previous: Interval? = nil,
            calendar: String? = nil,
            location: String? = nil,
            attendees: [String] = [],
            notes: String? = nil,
            recurrence: String? = nil,
            alerts: [Int] = [],
            travelMinutes: Int? = nil,
            url: String? = nil,
            attachments: [String] = [],
            details: [Facts.Fact] = [],
            warnings: [String] = [],
            context: Timeline? = nil
        ) {
            self.title = title
            self.interval = interval
            self.timeZone = timeZone
            self.allDay = allDay
            self.change = change
            self.previous = previous
            self.calendar = calendar
            self.location = location
            self.attendees = attendees
            self.notes = notes
            self.recurrence = recurrence
            self.alerts = alerts
            self.travelMinutes = travelMinutes
            self.url = url
            self.attachments = attachments
            self.details = details
            self.warnings = warnings
            self.context = context
        }

        public var zone: TimeZone {
            timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        }
    }

    /// Nodes and directed edges; parallel edges and cycles are allowed.
    struct Graph: Sendable, Codable, Hashable {
        public struct Node: Sendable, Codable, Hashable {
            public let id: String
            public let label: String
            public let kind: String?

            public init(id: String, label: String, kind: String? = nil) {
                self.id = id
                self.label = label
                self.kind = kind
            }
        }

        public struct Edge: Sendable, Codable, Hashable {
            public let id: String
            public let source: String
            public let destination: String
            public let label: String?

            public init(id: String, source: String, destination: String, label: String? = nil) {
                self.id = id
                self.source = source
                self.destination = destination
                self.label = label
            }
        }

        /// An identified pointer at a node, or at something outside the graph.
        public struct Reference: Sendable, Codable, Hashable {
            public let id: String
            public let target: String

            public init(id: String, target: String) {
                self.id = id
                self.target = target
            }
        }

        public let title: String?
        public let nodes: [Node]
        public let edges: [Edge]
        public let references: [Reference]

        public init(
            title: String? = nil,
            nodes: [Node],
            edges: [Edge],
            references: [Reference] = []
        ) {
            self.title = title
            self.nodes = nodes
            self.edges = edges
            self.references = references
        }
    }
}

/// Display forms every renderer shares, so a card reads the same everywhere.
public extension ReportBlock.Event {
    var heading: String {
        switch change {
        case .create?: "New event"
        case .update?: "Changed event"
        case .cancel?: "Cancelled event"
        case nil: "Event"
        }
    }

    /// `Sun 29 Nov 10:00–11:30 · 1h 30m`, or `Sun 29 Nov · all day`.
    func when(_ interval: Interval) -> String {
        if allDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let day = ReportText.formatter("EEE d MMM", zone: zone)
            let last = interval.end.addingTimeInterval(-1)
            guard interval.end > interval.start,
                  !calendar.isDate(interval.start, inSameDayAs: last) else {
                return day.string(from: interval.start) + " · all day"
            }
            return day.string(from: interval.start) + " – " + day.string(from: last) + " · all day"
        }
        let length = Self.length(Int(interval.end.timeIntervalSince(interval.start) / 60))
        let range = ReportText.range(interval.start, interval.end, zone: zone)
            .replacingOccurrences(of: " – ", with: "–")
        return range + " · " + length
    }

    /// `45m`, `1h 30m`, `2d`.
    static func length(_ minutes: Int) -> String {
        if minutes >= 1440, minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes >= 60 { return "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)m") }
        return "\(minutes)m"
    }

    /// The labeled lines under the title, standard ones first.
    var lines: [ReportBlock.Facts.Fact] {
        var lines = [ReportBlock.Facts.Fact("when", when(interval))]
        if let previous { lines.append(.init("was", when(previous))) }
        if let calendar { lines.append(.init("calendar", calendar)) }
        if let location { lines.append(.init("where", location)) }
        if !attendees.isEmpty { lines.append(.init("with", attendees.joined(separator: ", "))) }
        if let recurrence { lines.append(.init("repeats", recurrence)) }
        if let travelMinutes { lines.append(.init("travel", Self.length(travelMinutes) + " before")) }
        if !alerts.isEmpty {
            lines.append(.init("alerts", alerts.sorted().map { $0 == 0 ? "at start" : Self.length($0) + " before" }.joined(separator: ", ")))
        }
        if let url { lines.append(.init("link", url)) }
        if !attachments.isEmpty { lines.append(.init("attached", attachments.joined(separator: ", "))) }
        if let notes { lines.append(.init("notes", notes)) }
        return lines + details
    }
}
