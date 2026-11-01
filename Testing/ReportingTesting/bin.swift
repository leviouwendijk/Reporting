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
