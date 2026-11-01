import Foundation
import Search

/// A source identity retained independently of a particular visual renderer.
public struct ReportSource: Sendable, Codable, Hashable {
    public let namespace: String
    public let identifier: String

    public init(
        namespace: String,
        identifier: String
    ) {
        self.namespace = namespace
        self.identifier = identifier
    }
}

public struct ReportDataset: Sendable, Codable, Hashable {
    public struct Row: Sendable, Codable, Hashable {
        public let values: [StructuredValue?]
        public let sources: [ReportSource]

        public init(
            values: [StructuredValue?],
            sources: [ReportSource] = []
        ) {
            self.values = values
            self.sources = sources
        }
    }

    public enum Failure: Error, Sendable, Equatable {
        case emptyName
        case duplicateColumn(String)
        case invalidColumn(String)
        case invalidRow(Int)
        case invalidSource(Int)
    }

    public let id: String
    public let columns: [StructuredField]
    public let rows: [Row]

    public init(
        id: String,
        columns: [StructuredField],
        rows: [Row]
    ) throws {
        guard !id.isEmpty else {
            throw Failure.emptyName
        }
        var names: Set<String> = []
        for column in columns {
            guard !column.name.isEmpty, !column.multiple else {
                throw Failure.invalidColumn(column.name)
            }
            guard names.insert(column.name).inserted else {
                throw Failure.duplicateColumn(column.name)
            }
        }
        for (index, row) in rows.enumerated() {
            guard row.values.count == columns.count,
                  zip(row.values, columns).allSatisfy({ value, column in
                      value == nil || value?.kind == column.kind
                  }) else {
                throw Failure.invalidRow(index)
            }
            guard row.sources.allSatisfy({
                !$0.namespace.isEmpty && !$0.identifier.isEmpty
            }) else {
                throw Failure.invalidSource(index)
            }
        }
        self.id = id
        self.columns = columns
        self.rows = rows
    }

    /// Indexed lookup for renderers; never changes the authoritative row values.
    public func columnIndex(
        _ name: String
    ) -> Int? {
        columns.firstIndex(where: { $0.name == name })
    }
}
