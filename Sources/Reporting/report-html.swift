import DSL
import Foundation
import Search

/// A self-contained HTML page for a report: readable in a browser and
/// printable to A4 (WeasyPrint or a browser's print) without scripts.
public enum ReportHTML {
    public static func render(_ document: ReportDocument, generated: Date = Date()) -> String {
        var datasets: [String: ReportDataset] = [:]
        for dataset in document.datasets { datasets[dataset.id] = dataset }
        var body: [String] = ["<h1>\(escape(document.title))</h1>"]
        for block in document.blocks {
            switch block {
            case .narrative(let content):
                body.append("<div class=\"narrative\">\(html(content))</div>")
            case .facts(let facts):
                var rows = facts.facts.map { "<dt>\(escape($0.label))</dt><dd>\(escape($0.value))</dd>" }
                if let title = facts.title { rows.insert("<h2>\(escape(title))</h2>", at: 0) }
                body.append("<dl class=\"facts\">\(rows.joined())</dl>")
            case .callout(let callout):
                body.append("""
                <aside class="callout \(callout.tone.rawValue)"><strong>\(escape(callout.title ?? ReportText.symbol(callout.tone)))</strong>\(html(callout.content))</aside>
                """)
            case .table(let spec):
                body.append(datasets[spec.dataset].map { table(spec, $0) } ?? missing(spec.dataset))
            case .chart(let spec):
                body.append(datasets[spec.dataset].map { chart(spec, $0) } ?? missing(spec.dataset))
            case .timeline(let timeline):
                body.append(self.timeline(timeline))
            case .graph(let graph):
                let labels = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.label) })
                let items = graph.edges.map { edge in
                    "<li>\(escape(labels[edge.source] ?? edge.source)) → \(escape(labels[edge.destination] ?? edge.destination))"
                        + (edge.label.map { " <span class=\"muted\">(\(escape($0)))</span>" } ?? "") + "</li>"
                }
                body.append((graph.title.map { "<h2>\(escape($0))</h2>" } ?? "") + "<ul class=\"graph\">\(items.joined())</ul>")
            }
        }
        let stamp = ReportText.formatter("d MMM yyyy HH:mm", zone: .current).string(from: generated)
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(document.title))</title>
        <style>\(style)</style>
        </head>
        <body>
        <main>
        \(body.joined(separator: "\n"))
        <footer>Generated \(escape(stamp))</footer>
        </main>
        </body>
        </html>

        """
    }

    static func missing(_ dataset: String) -> String {
        "<p class=\"muted\">Missing dataset: \(escape(dataset))</p>"
    }

    static func table(_ spec: ReportBlock.Table, _ dataset: ReportDataset) -> String {
        let indices = spec.columns.compactMap(dataset.columnIndex)
        var parts: [String] = []
        if let title = spec.title { parts.append("<h2>\(escape(title))</h2>") }
        if let note = ReportText.coverage(dataset.coverage) { parts.append("<p class=\"muted\">\(escape(note))</p>") }
        let head = indices.map { index in
            "<th\(ReportText.isNumeric(dataset.columns[index].kind) ? " class=\"num\"" : "")>\(escape(dataset.columns[index].name))</th>"
        }.joined()
        let rows = dataset.rows.map { row in
            "<tr>" + indices.map { index in
                "<td\(ReportText.isNumeric(dataset.columns[index].kind) ? " class=\"num\"" : "")>\(escape(ReportText.value(row.values[index])))</td>"
            }.joined() + "</tr>"
        }.joined()
        parts.append("<table><thead><tr>\(head)</tr></thead><tbody>\(rows)</tbody></table>")
        return parts.joined()
    }

    /// Horizontal bars scaled to the largest magnitude; values stay exact.
    static func chart(_ spec: ReportBlock.Chart, _ dataset: ReportDataset) -> String {
        guard let x = dataset.columnIndex(spec.x), let y = dataset.columnIndex(spec.y) else { return "" }
        let numbers = dataset.rows.map { row -> Double? in
            switch row.values[y] {
            case .integer(let number)?: return Double(number)
            case .decimal(let number)?: return NSDecimalNumber(decimal: number).doubleValue
            default: return nil
            }
        }
        let largest = max(numbers.compactMap { $0.map(abs) }.max() ?? 0, .leastNonzeroMagnitude)
        let rows = zip(dataset.rows, numbers).map { row, number in
            let width = number.map { abs($0) / largest * 100 } ?? 0
            let negative = (number ?? 0) < 0 ? " negative" : ""
            return "<div class=\"bar-row\"><span>\(escape(ReportText.value(row.values[x])))</span>"
                + "<span class=\"bar\"><i class=\"\(negative)\" style=\"width:\(String(format: "%.1f", width))%\"></i></span>"
                + "<span class=\"num\">\(escape(ReportText.value(row.values[y])))</span></div>"
        }.joined()
        return "<h2>\(escape(spec.title ?? "\(spec.y) by \(spec.x)"))</h2><div class=\"bars\">\(rows)</div>"
    }

    static func timeline(_ timeline: ReportBlock.Timeline) -> String {
        let zone = timeline.zone
        let total = timeline.end.timeIntervalSince(timeline.start)
        let multiDay = ReportText.multiDay(timeline)
        func percent(_ date: Date) -> Double {
            min(100, max(0, date.timeIntervalSince(timeline.start) / total * 100))
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let step: TimeInterval = multiDay ? 86_400 : (total > 12 * 3600 ? 2 * 3600 : 3600)
        var tick = calendar.dateInterval(of: multiDay ? .day : .hour, for: timeline.start)?.start ?? timeline.start
        if tick < timeline.start { tick += multiDay ? 86_400 : 3600 }
        let label = ReportText.formatter(multiDay ? "EEE d" : "HH:mm", zone: zone)
        var ticks: [String] = []
        while tick < timeline.end {
            ticks.append("<span style=\"left:\(String(format: "%.2f", percent(tick)))%\">\(label.string(from: tick))</span>")
            tick += step
        }

        let lanes = timeline.lanes.map { lane -> String in
            let spans = lane.spans.filter { $0.end > timeline.start && $0.start < timeline.end }.map { span -> String in
                let left = percent(span.start)
                let width = max(0.4, percent(span.end) - left)
                let title = ReportText.span(span, zone: zone, multiDay: multiDay) + " " + span.mark.rawValue
                    + (span.label.map { " · \($0)" } ?? "")
                let text = span.mark == .highlight ? (span.label ?? "") : ""
                return "<i class=\"\(span.mark.rawValue)\" style=\"left:\(String(format: "%.2f", left))%;width:\(String(format: "%.2f", width))%\" title=\"\(escape(title))\">\(escape(text))</i>"
            }.joined()
            return "<div class=\"lane\"><span class=\"lane-label\">\(escape(lane.label))</span><span class=\"track\">\(spans)</span></div>"
        }.joined()

        let used = Set(timeline.lanes.flatMap { $0.spans.map(\.mark) })
        let legend = ReportBlock.Timeline.Mark.allCases.filter(used.contains).map {
            "<span><i class=\"\($0.rawValue)\"></i>\($0.rawValue)</span>"
        }.joined()

        let listed = timeline.lanes.filter { !$0.spans.isEmpty }.map { lane -> String in
            let items = lane.spans.sorted { $0.start < $1.start }.map { span in
                "<li><i class=\"\(span.mark.rawValue)\"></i>\(escape(ReportText.span(span, zone: zone, multiDay: multiDay))) "
                    + "<span class=\"muted\">\(span.mark.rawValue)</span>"
                    + (span.label.map { " · \(escape($0))" } ?? "") + "</li>"
            }.joined()
            return "<div><strong>\(escape(lane.label))</strong><ul>\(items)</ul></div>"
        }.joined()

        return """
        <section class="timeline">\(timeline.title.map { "<h2>\(escape($0))</h2>" } ?? "")\
        <p class="muted">\(escape(ReportText.range(timeline.start, timeline.end, zone: zone))) · \(escape(zone.identifier))</p>\
        <div class="axis"><span class="lane-label"></span><span class="ticks">\(ticks.joined())</span></div>\
        \(lanes)<p class="legend">\(legend)</p><div class="spans">\(listed)</div></section>
        """
    }

    static func html(_ content: StructuredContent) -> String {
        switch content {
        case .collection(let items):
            return items.map(html).joined()
        case .paragraph(let inlines):
            return "<p>" + inlines.map(inline).joined() + "</p>"
        case .code(_, let source):
            return "<pre><code>\(escape(source))</code></pre>"
        case .quote(let inner):
            return "<blockquote>\(html(inner))</blockquote>"
        case .list(let style, let items):
            let tag = style == .ordered ? "ol" : "ul"
            return "<\(tag)>" + items.map { "<li>\(html($0))</li>" }.joined() + "</\(tag)>"
        case .group(_, let title, let inner):
            return (title.map { "<h3>" + $0.map(inline).joined() + "</h3>" } ?? "") + html(inner)
        case .table(let header, let rows):
            let head = header.map { "<th>\(html($0))</th>" }.joined()
            let body = rows.map { "<tr>" + $0.map { "<td>\(html($0))</td>" }.joined() + "</tr>" }.joined()
            return "<table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>"
        }
    }

    static func inline(_ value: StructuredContent.Inline) -> String {
        switch value {
        case .text(let text): return escape(text)
        case .code(let code): return "<code>\(escape(code))</code>"
        case .emphasis(let inner): return "<em>" + inner.map(inline).joined() + "</em>"
        case .strong(let inner): return "<strong>" + inner.map(inline).joined() + "</strong>"
        }
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let style = """
    @page { size: A4; margin: 16mm 14mm; }
    :root { --ink:#1d1d1f; --muted:#6e6e73; --rule:#d2d2d7; --wash:#f5f5f7;
      --occupied:#3a3a3c; --reserved:#a1a1a6; --available:#b7dfc4; --highlight:#0a63c9; --transit:#e0a43a;
      --info:#0a63c9; --success:#1f8a4c; --warning:#b25e00; --failure:#c4302b; }
    * { box-sizing: border-box; }
    body { margin:0; background:#fff; color:var(--ink); font:14px/1.5 -apple-system, "Helvetica Neue", Arial, sans-serif; }
    main { max-width: 860px; margin: 0 auto; padding: 32px 16px; }
    h1 { font-size: 24px; margin: 0 0 20px; }
    h2 { font-size: 15px; margin: 24px 0 8px; }
    h3 { font-size: 14px; margin: 12px 0 4px; }
    p { margin: 8px 0; }
    .muted { color: var(--muted); }
    .facts { display:grid; grid-template-columns: max-content 1fr; gap: 4px 20px; margin: 0 0 16px; }
    .facts h2 { grid-column: 1 / -1; margin: 0; }
    .facts dt { color: var(--muted); }
    .facts dd { margin: 0; font-weight: 600; }
    .callout { border-left: 4px solid var(--info); background: var(--wash); padding: 8px 14px; margin: 14px 0; break-inside: avoid; }
    .callout.success { border-color: var(--success); } .callout.warning { border-color: var(--warning); } .callout.failure { border-color: var(--failure); }
    .callout > strong { display:block; }
    .callout ul { margin: 4px 0; padding-left: 18px; }
    table { border-collapse: collapse; width: 100%; margin: 6px 0 14px; font-variant-numeric: tabular-nums; break-inside: auto; }
    th, td { text-align: left; padding: 5px 8px; border-bottom: 1px solid var(--rule); vertical-align: top; }
    th { font-weight: 600; color: var(--muted); }
    .num { text-align: right; }
    .bars { display:grid; gap: 4px; }
    .bar-row { display:grid; grid-template-columns: minmax(80px, 25%) 1fr max-content; gap: 10px; align-items:center; }
    .bar { background: var(--wash); height: 12px; }
    .bar i { display:block; height:100%; background: var(--highlight); }
    .bar i.negative { background: var(--failure); }
    .timeline { break-inside: avoid; }
    .axis, .lane { display:grid; grid-template-columns: 130px 1fr; align-items:center; }
    .ticks, .track { position: relative; height: 22px; }
    .ticks span { position:absolute; transform: translateX(-50%); font-size: 11px; color: var(--muted); }
    .track { background: var(--wash); border-left: 1px solid var(--rule); border-right: 1px solid var(--rule); margin: 2px 0; height: 24px; }
    .lane-label { padding-right: 10px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .track i { position:absolute; top: 3px; bottom: 3px; border-radius: 3px; font-style: normal; font-size: 10px; color: #fff; overflow: hidden; white-space: nowrap; padding: 0 3px; line-height: 18px; }
    i.occupied { background: var(--occupied); } i.reserved { background: repeating-linear-gradient(45deg, var(--reserved) 0 4px, #c7c7cc 4px 8px); }
    i.available { background: var(--available); } i.highlight { background: var(--highlight); } i.transit { background: var(--transit); }
    .legend span { margin-right: 14px; font-size: 12px; color: var(--muted); }
    .legend i, .spans li i { display:inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 5px; vertical-align: -1px; }
    .spans { columns: 2; column-gap: 24px; font-size: 13px; margin-top: 8px; }
    .spans > div { break-inside: avoid; margin-bottom: 8px; }
    .spans ul { list-style: none; margin: 2px 0; padding: 0; }
    pre { background: var(--wash); padding: 10px; overflow-x: auto; }
    blockquote { margin: 8px 0; padding-left: 12px; border-left: 3px solid var(--rule); color: var(--muted); }
    footer { margin-top: 32px; font-size: 12px; color: var(--muted); }
    @media (max-width: 560px) { .axis, .lane { grid-template-columns: 84px 1fr; } .spans { columns: 1; } }
    """
}
