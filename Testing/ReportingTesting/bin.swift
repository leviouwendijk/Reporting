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

        Test("facts-callout-timeline-graph-roundtrip-and-guards") {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let document = try ReportDocument(
                title: "Proposal",
                datasets: [],
                blocks: [
                    .facts(.init(facts: [.init("when", "Tue 10:00")])),
                    .callout(.init(tone: .warning, content: .paragraph([.text("No location")]))),
                    .timeline(.init(start: start, end: start + 3600, timeZone: "Europe/Amsterdam", lanes: [
                        .init(label: "Levi", spans: [.init(start: start, end: start + 900, mark: .occupied)]),
                    ])),
                    .graph(.init(
                        nodes: [.init(id: "a", label: "A"), .init(id: "b", label: "B")],
                        edges: [.init(id: "ab", source: "a", destination: "b")]
                    )),
                ]
            )
            let restored = try JSONDecoder().decode(ReportDocument.self, from: JSONEncoder().encode(document))
            try Expect.equal(restored, document, "New blocks survive Codable roundtrip")

            try Expect.throwsError("Empty facts rejected") {
                _ = try ReportDocument(title: "x", datasets: [], blocks: [.facts(.init(facts: []))])
            }
            try Expect.throwsError("Timeline window must be ordered") {
                _ = try ReportDocument(title: "x", datasets: [], blocks: [
                    .timeline(.init(start: start, end: start, lanes: [])),
                ])
            }
            try Expect.throwsError("Edges must join known nodes") {
                _ = try ReportDocument(title: "x", datasets: [], blocks: [
                    .graph(.init(nodes: [.init(id: "a", label: "A")], edges: [.init(id: "e", source: "a", destination: "z")])),
                ])
            }
        }

        Test("markdown-and-html-exports") {
            let start = Date(timeIntervalSince1970: 1_763_449_200) // 2026-11-18 08:00 Amsterdam
            let dataset = try ReportDataset(
                id: "options",
                columns: [.init("option", kind: .text), .init("score", kind: .decimal)],
                rows: [.init(values: [.text("A | first"), .decimal(Decimal(string: "0.67")!)])],
                coverage: .complete
            )
            let document = try ReportDocument(
                title: "Plan <draft>",
                datasets: [dataset],
                blocks: [
                    .facts(.init(facts: [.init("Recommended", "Tue 10:00")])),
                    .narrative(.list(style: .unordered, items: [.paragraph([.strong([.text("morning")])])])),
                    .callout(.init(tone: .warning, title: "Gaps", content: .paragraph([.text("No location")]))),
                    .table(.init(dataset: "options", columns: ["option", "score"])),
                    .timeline(.init(start: start, end: start + 8 * 3600, timeZone: "Europe/Amsterdam", lanes: [
                        .init(label: "Levi", spans: [.init(start: start + 7200, end: start + 10800, mark: .highlight, label: "A")]),
                    ])),
                ]
            )
            let markdown = ReportMarkdown.render(document)
            try Expect.true(markdown.hasPrefix("# Plan <draft>"), "Markdown title")
            try Expect.true(markdown.contains("- **Recommended**: Tue 10:00"), "Facts as a list")
            try Expect.true(markdown.contains("- **morning**"), "Narrative Markdown")
            try Expect.true(markdown.contains("> **Gaps**"), "Callout as a quote")
            try Expect.true(markdown.contains("| A \\| first | 0.67 |"), "Table cells escaped")
            try Expect.true(markdown.contains("- 10:00–11:00 highlight · A"), "Timeline spans in the zone")

            let html = ReportHTML.render(document)
            try Expect.true(html.contains("<title>Plan &lt;draft&gt;</title>"), "HTML escapes")
            try Expect.true(html.contains("class=\"callout warning\""), "Callout tone")
            try Expect.true(html.contains("<td class=\"num\">0.67</td>"), "Numeric cells aligned")
            try Expect.true(html.contains("class=\"highlight\" style=\"left:25.00%;width:12.50%\""), "Span placed on the axis")
            try Expect.true(html.contains("@page { size: A4"), "Printable")
        }
    }
}
