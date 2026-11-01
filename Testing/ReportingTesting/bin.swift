import DSL
import Foundation
import Reporting
import Search
import Testing

private enum ReportingTestFailure: Error {
    case failed
}

@main
struct ReportingTestingMain {
    static func main() async throws {
        let reporter = PlainTextTestReporter()
        let result = await TestRunner.run(
            ReportingTestSuite.suite,
            sink: reporter
        )
        let output = await reporter.rendered()
        if !output.isEmpty {
            print(output)
        }
        if result.isFailure {
            throw ReportingTestFailure.failed
        }
    }
}

enum ReportingTestSuite {
    static let suite = TestSuite("reporting", title: "Reusable structured reports") {
        Test("typed-data-and-provenance-roundtrip") {
            let dataset = try ReportDataset(
                id: "monthly-vat",
                columns: [
                    .init("month", kind: .text),
                    .init("vat", kind: .decimal),
                ],
                rows: [
                    .init(
                        values: [.text("2026-07"), .decimal(Decimal(string: "21.01")!)],
                        sources: [.init(namespace: "accounting.entry", identifier: "2445")]
                    ),
                ]
            )
            let document = try ReportDocument(
                title: "VAT review",
                datasets: [dataset],
                blocks: [
                    .narrative(.paragraph([.text("Verified totals") ])),
                    .table(.init(dataset: "monthly-vat", columns: ["month", "vat"])),
                    .chart(.init(dataset: "monthly-vat", kind: .bar, x: "month", y: "vat")),
                ]
            )
            let serialized = try JSONEncoder().encode(document)
            let restored = try JSONDecoder().decode(ReportDocument.self, from: serialized)
            try Expect.equal(restored, document, "Schema and values survive Codable roundtrip")
            try Expect.equal(restored.datasets[0].rows[0].sources[0].identifier, "2445", "Provenance retained")
        }

        Test("grouped-sums-counts-and-provenance") {
            let dataset = try ReportDataset(
                id: "source",
                columns: [
                    .init("month", kind: .text),
                    .init("amount", kind: .decimal),
                ],
                rows: [
                    .init(values: [.text("jan"), .decimal(Decimal(10))], sources: [.init(namespace: "entry", identifier: "1")]),
                    .init(values: [.text("jan"), .decimal(Decimal(15))], sources: [.init(namespace: "entry", identifier: "2")]),
                    .init(values: [.text("feb"), .decimal(Decimal(8))], sources: [.init(namespace: "entry", identifier: "3")]),
                ],
                coverage: .complete
            )
            let grouped = try ReportDatasetTransform.group(
                dataset,
                by: ["month"],
                measures: [
                    .init(name: "count", operation: .count),
                    .init(name: "total", operation: .sum, source: "amount"),
                ],
                id: "monthly"
            )
            try Expect.equal(grouped.coverage, .complete, "Complete source gives complete aggregate")
            try Expect.equal(grouped.rows.count, 2, "Two groups in first-seen order")
            try Expect.equal(grouped.rows[0].values[0], StructuredValue.text("jan"), "First group")
            try Expect.equal(grouped.rows[0].values[1], StructuredValue.integer(2), "Row count")
            try Expect.equal(grouped.rows[0].values[2], StructuredValue.decimal(25), "Exact sum")
            try Expect.equal(grouped.rows[0].sources.map(\.identifier), ["1", "2"], "Provenance preserved")

            let derived = try ReportDatasetTransform.percentage(
                grouped, baseColumn: "total", rate: 21,
                outputColumn: "vat", scale: 2, id: "monthly-vat"
            )
            try Expect.equal(derived.rows[0].values[3], StructuredValue.decimal(Decimal(string: "5.25")!), "VAT on first group")
            try Expect.equal(derived.rows[1].values[3], StructuredValue.decimal(Decimal(string: "1.68")!), "VAT on second group")
            try Expect.equal(derived.rows[0].sources, grouped.rows[0].sources, "Derivation preserves evidence")
            let restored = try JSONDecoder().decode(ReportDataset.self, from: JSONEncoder().encode(derived))
            try Expect.equal(restored, derived, "Roundtrip preserves coverage and measures")
        }

        Test("partial-data-and-null-numeric-guards") {
            let columns: [StructuredField] = [.init("amount", kind: .decimal)]
            let partial = try ReportDataset(
                id: "page", columns: columns,
                rows: [.init(values: [.decimal(5)])],
                coverage: .partial(offset: 0, total: 10)
            )
            try Expect.throwsError("Reject partial aggregates") {
                _ = try ReportDatasetTransform.group(partial, by: [], measures: [.init(name: "sum", operation: .sum, source: "amount")], id: "invalid")
            }
            let defaultUnknown = try ReportDataset(id: "unknown", columns: columns, rows: [])
            try Expect.throwsError("Reject unknown coverage") {
                _ = try ReportDatasetTransform.group(defaultUnknown, by: [], measures: [.init(name: "count", operation: .count)], id: "invalid")
            }
            let derivedPartial = try ReportDatasetTransform.percentage(
                partial, baseColumn: "amount", rate: 21,
                outputColumn: "vat", scale: 2, id: "partial-vat"
            )
            try Expect.equal(derivedPartial.coverage, partial.coverage, "Row-wise derivation keeps partial label")

            let missing = try ReportDataset(
                id: "missing", columns: columns,
                rows: [.init(values: [nil])], coverage: .complete
            )
            try Expect.throwsError("Null is not implicitly zero") {
                _ = try ReportDatasetTransform.group(missing, by: [], measures: [.init(name: "sum", operation: .sum, source: "amount")], id: "invalid")
            }
            try Expect.throwsError("Reject duplicate column name") {
                _ = try ReportDatasetTransform.percentage(
                    partial, baseColumn: "amount", rate: 21,
                    outputColumn: "amount", scale: 2, id: "invalid"
                )
            }
        }

        Test("legacy-datasets-default-to-unverified-coverage") {
            let dataset = try ReportDataset(
                id: "legacy", columns: [.init("value", kind: .integer)],
                rows: [.init(values: [.integer(1)])]
            )
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dataset)) as! [String: Any]
            json.removeValue(forKey: "coverage")
            let decoded = try JSONDecoder().decode(
                ReportDataset.self,
                from: JSONSerialization.data(withJSONObject: json)
            )
            try Expect.equal(decoded.coverage, .unknown, "Missing historical coverage is never assumed complete")
        }

        Test("reject-invalid-columns-and-visual-references") {
            try Expect.throwsError("Mismatched row kind") {
                _ = try ReportDataset(
                    id: "broken",
                    columns: [.init("amount", kind: .decimal)],
                    rows: [.init(values: [.text("not a number")])]
                )
            }
            let dataset = try ReportDataset(
                id: "values",
                columns: [.init("label", kind: .text)],
                rows: [.init(values: [.text("a")])]
            )
            try Expect.throwsError("Missing column") {
                _ = try ReportDocument(
                    title: "broken",
                    datasets: [dataset],
                    blocks: [.table(.init(dataset: "values", columns: ["absent"]))]
                )
            }
            try Expect.throwsError("Text cannot be numeric measure") {
                _ = try ReportDocument(
                    title: "broken",
                    datasets: [dataset],
                    blocks: [.chart(.init(dataset: "values", kind: .line, x: "label", y: "label"))]
                )
            }
        }
    }
}
