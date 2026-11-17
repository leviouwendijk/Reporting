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
