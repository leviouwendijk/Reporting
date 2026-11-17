import DSL
import Foundation
import Search

/// Display forms shared by the document renderers.
enum ReportText {
    static func value(_ value: StructuredValue?) -> String {
        guard let value else { return "—" }
        switch value {
        case .text(let text): return text
        case .integer(let number): return String(number)
        case .decimal(let number): return NSDecimalNumber(decimal: number).stringValue
        case .date(let date): return ISO8601DateFormatter().string(from: date)
        case .boolean(let flag): return flag ? "yes" : "no"
        }
    }

    static func isNumeric(_ kind: StructuredValueKind) -> Bool {
        kind == .integer || kind == .decimal
    }

    static func coverage(_ coverage: ReportDataset.Coverage) -> String? {
        switch coverage {
        case .complete: return nil
        case .unknown: return "Coverage unknown; totals not verified."
        case .partial(let offset, let total):
            return "Partial data; offset \(offset), total \(total.map(String.init) ?? "?")."
        }
    }

    static func formatter(_ format: String, zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }

    static func range(_ start: Date, _ end: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let sameDay = calendar.isDate(start, inSameDayAs: end.addingTimeInterval(-1))
        let day = formatter("EEE d MMM HH:mm", zone: zone)
        return day.string(from: start) + " – " + (sameDay ? formatter("HH:mm", zone: zone) : day).string(from: end)
    }

    static func span(_ span: ReportBlock.Timeline.Span, zone: TimeZone, multiDay: Bool) -> String {
        let from = formatter(multiDay ? "EEE d MMM HH:mm" : "HH:mm", zone: zone).string(from: span.start)
        let to = formatter("HH:mm", zone: zone).string(from: span.end)
        return "\(from)–\(to)"
    }

    static func multiDay(_ timeline: ReportBlock.Timeline) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeline.zone
        return !calendar.isDate(timeline.start, inSameDayAs: timeline.end.addingTimeInterval(-1))
    }

    static func symbol(_ tone: ReportBlock.Callout.Tone) -> String {
        switch tone {
        case .info: "Note"
        case .success: "Done"
        case .warning: "Warning"
        case .failure: "Problem"
        }
    }
}

/// Markdown for pasting into notes, issues or mail.
public enum ReportMarkdown {
    public static func render(_ document: ReportDocument) -> String {
        var datasets: [String: ReportDataset] = [:]
        for dataset in document.datasets { datasets[dataset.id] = dataset }
        var sections = ["# " + inline(document.title)]
        for block in document.blocks {
            let section: String
            switch block {
            case .narrative(let content):
                section = markdown(content)
            case .facts(let facts):
                section = (facts.title.map { "**\(inline($0))**\n\n" } ?? "")
                    + facts.facts.map { "- **\(inline($0.label))**: \(inline($0.value))" }.joined(separator: "\n")
            case .callout(let callout):
                let heading = "> **\(inline(callout.title ?? ReportText.symbol(callout.tone)))**"
                let body = markdown(callout.content).split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.isEmpty ? ">" : "> " + $0 }
                section = ([heading, ">"] + body).joined(separator: "\n")
            case .table(let spec):
                section = datasets[spec.dataset].map { table(spec, $0) } ?? "*Missing dataset: \(spec.dataset)*"
            case .chart(let spec):
                guard let dataset = datasets[spec.dataset] else {
                    section = "*Missing dataset: \(spec.dataset)*"
                    break
                }
                section = table(.init(dataset: spec.dataset, columns: [spec.x, spec.y], title: spec.title ?? "\(spec.y) by \(spec.x)"), dataset)
            case .timeline(let timeline):
                section = self.timeline(timeline)
            case .graph(let graph):
                let labels = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.label) })
                section = (graph.title.map { "**\(inline($0))**\n\n" } ?? "")
                    + graph.edges.map { edge in
                        "- \(inline(labels[edge.source] ?? edge.source)) → \(inline(labels[edge.destination] ?? edge.destination))"
                            + (edge.label.map { " (\(inline($0)))" } ?? "")
                    }.joined(separator: "\n")
            }
            if !section.isEmpty { sections.append(section) }
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    static func table(_ spec: ReportBlock.Table, _ dataset: ReportDataset) -> String {
        let indices = spec.columns.compactMap(dataset.columnIndex)
        var lines: [String] = []
        if let title = spec.title { lines += ["**\(inline(title))**", ""] }
        if let note = ReportText.coverage(dataset.coverage) { lines += ["*\(note)*", ""] }
        lines.append("| " + indices.map { cell(dataset.columns[$0].name) }.joined(separator: " | ") + " |")
        lines.append("|" + indices.map { ReportText.isNumeric(dataset.columns[$0].kind) ? " ---: " : " --- " }.joined(separator: "|") + "|")
        for row in dataset.rows {
            lines.append("| " + indices.map { cell(ReportText.value(row.values[$0])) }.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    static func timeline(_ timeline: ReportBlock.Timeline) -> String {
        let zone = timeline.zone
        let multiDay = ReportText.multiDay(timeline)
        var lines: [String] = []
        if let title = timeline.title { lines += ["**\(inline(title))**", ""] }
        lines.append("*\(ReportText.range(timeline.start, timeline.end, zone: zone)) · \(zone.identifier)*")
        for lane in timeline.lanes where !lane.spans.isEmpty {
            lines += ["", "**\(inline(lane.label))**", ""]
            for span in lane.spans.sorted(by: { $0.start < $1.start }) {
                lines.append("- \(ReportText.span(span, zone: zone, multiDay: multiDay)) \(span.mark.rawValue)"
                    + (span.label.map { " · \(inline($0))" } ?? ""))
            }
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(_ content: StructuredContent, indent: String = "") -> String {
        switch content {
        case .collection(let items):
            return items.map { markdown($0, indent: indent) }.joined(separator: "\n\n")
        case .paragraph(let inlines):
            return indent + inlines.map(inline).joined()
        case .code(let language, let source):
            return "```\(language ?? "")\n\(source)\n```"
        case .quote(let inner):
            return markdown(inner).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
        case .list(let style, let items):
            return items.enumerated().map { index, item in
                let marker = style == .ordered ? "\(index + 1). " : "- "
                let body = markdown(item, indent: "").split(separator: "\n", omittingEmptySubsequences: false)
                return indent + marker + body.enumerated().map { line, text in
                    line == 0 ? String(text) : indent + "  " + text
                }.joined(separator: "\n")
            }.joined(separator: "\n")
        case .group(_, let title, let inner):
            let heading = title.map { "**" + $0.map(inline).joined() + "**\n\n" } ?? ""
            return heading + markdown(inner, indent: indent)
        case .table(let header, let rows):
            let head = "| " + header.map { cell(markdown($0)) }.joined(separator: " | ") + " |"
            let rule = "|" + header.map { _ in " --- " }.joined(separator: "|") + "|"
            let body = rows.map { "| " + $0.map { cell(markdown($0)) }.joined(separator: " | ") + " |" }
            return ([head, rule] + body).joined(separator: "\n")
        }
    }

    static func inline(_ value: StructuredContent.Inline) -> String {
        switch value {
        case .text(let text): return inline(text)
        case .code(let code): return "`\(code)`"
        case .emphasis(let inner): return "*" + inner.map(inline).joined() + "*"
        case .strong(let inner): return "**" + inner.map(inline).joined() + "**"
        }
    }

    static func inline(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    /// A table cell; line breaks inside it (several entries) become `<br>`.
    static func cell(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "|", with: "\\|") }
            .joined(separator: "<br>")
    }
}
