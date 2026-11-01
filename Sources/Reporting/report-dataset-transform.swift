import Foundation
import Search
import Math

/// Pure, deterministic transforms over in-memory report datasets.
public enum ReportDatasetTransform {
    public enum Failure: Error, Equatable, Sendable {
        case incompleteDataset
        case emptyMeasures
        case unknownColumn(String)
        case duplicateOutput(String)
        case invalidMeasure(String)
        case nonNumericColumn(String)
        case missingNumericValue(column: String, row: Int)
    }

    public enum Aggregation: String, Sendable, Codable, Hashable {
        case count
        case sum
    }

    public struct Measure: Sendable, Codable, Hashable {
        public let name: String
        public let operation: Aggregation
        public let source: String?

        public init(name: String, operation: Aggregation, source: String? = nil) {
            self.name = name
            self.operation = operation
            self.source = source
        }
    }

    private struct PreparedMeasure {
        let measure: Measure
        let sourceIndex: Int?
    }

    private struct GroupKey: Hashable {
        let values: [StructuredValue?]
    }

    private struct Accumulator {
        var count: Int64 = 0
        var sums: [Decimal]
        var sources: [ReportSource] = []
        var seenSources: Set<ReportSource> = []
    }

    /// Aggregate only complete datasets. Preserve first-seen group order.
    public static func group(
        _ dataset: ReportDataset,
        by dimensions: [String],
        measures: [Measure],
        id: String
    ) throws -> ReportDataset {
        guard dataset.coverage == .complete else { throw Failure.incompleteDataset }
        guard !measures.isEmpty else { throw Failure.emptyMeasures }

        var used: Set<String> = []
        let dimensionIndices = try dimensions.map { name -> Int in
            guard used.insert(name).inserted else { throw Failure.duplicateOutput(name) }
            guard let index = dataset.columnIndex(name) else { throw Failure.unknownColumn(name) }
            return index
        }
        let prepared = try measures.map { measure -> PreparedMeasure in
            guard !measure.name.isEmpty, used.insert(measure.name).inserted else {
                throw Failure.duplicateOutput(measure.name)
            }
            switch measure.operation {
            case .count:
                guard measure.source == nil else { throw Failure.invalidMeasure(measure.name) }
                return .init(measure: measure, sourceIndex: nil)
            case .sum:
                guard let source = measure.source else { throw Failure.invalidMeasure(measure.name) }
                guard let index = dataset.columnIndex(source) else { throw Failure.unknownColumn(source) }
                guard [.decimal, .integer].contains(dataset.columns[index].kind) else {
                    throw Failure.nonNumericColumn(source)
                }
                return .init(measure: measure, sourceIndex: index)
            }
        }

        var groups: [GroupKey: Accumulator] = [:]
        var order: [GroupKey] = []
        for (rowIndex, row) in dataset.rows.enumerated() {
            let key = GroupKey(values: dimensionIndices.map { row.values[$0] })
            if groups[key] == nil {
                groups[key] = .init(sums: Array(repeating: .zero, count: prepared.count))
                order.append(key)
            }
            var accumulator = groups[key]!
            accumulator.count += 1
            for (measureIndex, item) in prepared.enumerated() {
                guard let sourceIndex = item.sourceIndex else { continue }
                let column = dataset.columns[sourceIndex].name
                guard let value = row.values[sourceIndex],
                      let number = numeric(value) else {
                    throw Failure.missingNumericValue(column: column, row: rowIndex)
                }
                accumulator.sums[measureIndex] = try DecimalArithmetic.unquantized(
                    .add, lhs: accumulator.sums[measureIndex], rhs: number
                )
            }
            for source in row.sources where accumulator.seenSources.insert(source).inserted {
                accumulator.sources.append(source)
            }
            groups[key] = accumulator
        }

        let resultColumns = dimensionIndices.map { dataset.columns[$0] } + prepared.map { item in
            StructuredField(item.measure.name, kind: item.measure.operation == .count ? .integer : .decimal)
        }
        let resultRows = order.map { key -> ReportDataset.Row in
            let accumulator = groups[key]!
            let values = prepared.enumerated().map { index, item -> StructuredValue? in
                switch item.measure.operation {
                case .count: .integer(accumulator.count)
                case .sum: .decimal(accumulator.sums[index])
                }
            }
            return .init(values: key.values + values, sources: accumulator.sources)
        }
        return try ReportDataset(id: id, columns: resultColumns, rows: resultRows, coverage: .complete)
    }

    /// Row-wise percentage. Rate 21 means 21%; coverage remains unchanged.
    public static func percentage(
        _ dataset: ReportDataset,
        baseColumn: String,
        rate: Decimal,
        outputColumn: String,
        scale: Int,
        mode: DecimalArithmetic.RoundingMode = .plain,
        id: String
    ) throws -> ReportDataset {
        guard dataset.columnIndex(outputColumn) == nil, !outputColumn.isEmpty else {
            throw Failure.duplicateOutput(outputColumn)
        }
        guard let baseIndex = dataset.columnIndex(baseColumn) else {
            throw Failure.unknownColumn(baseColumn)
        }
        guard [.decimal, .integer].contains(dataset.columns[baseIndex].kind) else {
            throw Failure.nonNumericColumn(baseColumn)
        }
        let rows = try dataset.rows.enumerated().map { index, row -> ReportDataset.Row in
            guard let value = row.values[baseIndex], let base = numeric(value) else {
                throw Failure.missingNumericValue(column: baseColumn, row: index)
            }
            let product = try DecimalArithmetic.unquantized(.multiply, lhs: base, rhs: rate)
            let raw = try DecimalArithmetic.unquantized(.divide, lhs: product, rhs: 100)
            let rounded = try DecimalArithmetic.round(raw, scale: scale, mode: mode)
            return .init(values: row.values + [.decimal(rounded)], sources: row.sources)
        }
        return try ReportDataset(
            id: id,
            columns: dataset.columns + [.init(outputColumn, kind: .decimal)],
            rows: rows,
            coverage: dataset.coverage
        )
    }

    private static func numeric(_ value: StructuredValue) -> Decimal? {
        switch value {
        case .decimal(let number): number
        case .integer(let number): Decimal(number)
        default: nil
        }
    }
}
