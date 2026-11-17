import DSL
import Search

/// A reusable report description, independent of terminal or HTML layout.
public struct ReportDocument: Sendable, Codable, Hashable {
    public enum Failure: Error, Sendable, Equatable {
        case duplicateDataset(String)
        case unknownDataset(String)
        case unknownColumn(dataset: String, column: String)
        case invalidChartMeasure(String)
        case emptyBlock(Int)
        case invalidTimeline(Int)
        case invalidGraph(Int)
    }

    public let title: String
    public let datasets: [ReportDataset]
    public let blocks: [ReportBlock]

    public init(
        title: String,
        datasets: [ReportDataset],
        blocks: [ReportBlock]
    ) throws {
        var byID: [String: ReportDataset] = [:]
        for dataset in datasets {
            guard byID.updateValue(dataset, forKey: dataset.id) == nil else {
                throw Failure.duplicateDataset(dataset.id)
            }
        }
        for (index, block) in blocks.enumerated() {
            switch block {
            case .narrative:
                break
            case .facts(let facts):
                guard !facts.facts.isEmpty else { throw Failure.emptyBlock(index) }
            case .callout:
                break
            case .timeline(let timeline):
                guard timeline.start < timeline.end,
                      timeline.lanes.allSatisfy({ $0.spans.allSatisfy { $0.start <= $0.end } }) else {
                    throw Failure.invalidTimeline(index)
                }
            case .graph(let graph):
                var nodes: Set<String> = []
                for node in graph.nodes {
                    guard nodes.insert(node.id).inserted else { throw Failure.invalidGraph(index) }
                }
                var edges: Set<String> = []
                for edge in graph.edges {
                    guard edges.insert(edge.id).inserted,
                          nodes.contains(edge.source),
                          nodes.contains(edge.destination) else {
                        throw Failure.invalidGraph(index)
                    }
                }
            case .table(let table):
                guard let dataset = byID[table.dataset] else {
                    throw Failure.unknownDataset(table.dataset)
                }
                for column in table.columns {
                    guard dataset.columnIndex(column) != nil else {
                        throw Failure.unknownColumn(dataset: table.dataset, column: column)
                    }
                }
            case .chart(let chart):
                guard let dataset = byID[chart.dataset] else {
                    throw Failure.unknownDataset(chart.dataset)
                }
                for column in [chart.x, chart.y] {
                    guard dataset.columnIndex(column) != nil else {
                        throw Failure.unknownColumn(dataset: chart.dataset, column: column)
                    }
                }
                guard let yIndex = dataset.columnIndex(chart.y),
                      [.integer, .decimal].contains(dataset.columns[yIndex].kind) else {
                    throw Failure.invalidChartMeasure(chart.y)
                }
            }
        }
        self.title = title
        self.datasets = datasets
        self.blocks = blocks
    }
}

public enum ReportBlock: Sendable, Codable, Hashable {
    case narrative(StructuredContent)
    case table(Table)
    case chart(Chart)
    case facts(Facts)
    case callout(Callout)
    case timeline(Timeline)
    case graph(Graph)

    public struct Table: Sendable, Codable, Hashable {
        public let dataset: String
        public let columns: [String]
        public let title: String?

        public init(
            dataset: String,
            columns: [String],
            title: String? = nil
        ) {
            self.dataset = dataset
            self.columns = columns
            self.title = title
        }
    }

    public struct Chart: Sendable, Codable, Hashable {
        public enum Kind: String, Sendable, Codable, Hashable {
            case bar
            case line
        }

        public let dataset: String
        public let kind: Kind
        public let x: String
        public let y: String
        public let title: String?

        public init(
            dataset: String,
            kind: Kind,
            x: String,
            y: String,
            title: String? = nil
        ) {
            self.dataset = dataset
            self.kind = kind
            self.x = x
            self.y = y
            self.title = title
        }
    }
}
