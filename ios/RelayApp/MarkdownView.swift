import SwiftUI

/// Markdown for issue and approval bodies.
///
/// The board's descriptions are Markdown, written by agents and by people,
/// and the phone should show them the way the board does. Foundation
/// already parses the inline half — emphasis, inline code and links — into
/// an `AttributedString`, and SwiftUI makes the links in one tappable. What
/// Foundation will not do is split a document into blocks, so that is what
/// this does: headings, code fences, lists, quotes and tables are found
/// here, and the text inside each block goes to Foundation.
///
/// Tables are rendered as a monospaced block rather than a grid. A grid
/// that reflows on a narrow screen turns a six-column table into
/// unreadable slivers, and a monospaced block keeps the shape of the table
/// while staying legible.
struct MarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var blocks: [MarkdownBlock] {
        MarkdownDocument(source).blocks
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            MarkdownInline(source: text)
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let text):
            MarkdownInline(source: text)
                .font(.callout)

        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 2)
                MarkdownInline(source: text)
                    .font(.callout)
                    .italic()
            }
            .fixedSize(horizontal: false, vertical: true)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        MarkdownInline(source: item)
                            .font(.callout)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        MarkdownInline(source: item)
                            .font(.callout)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .table(let rows):
            tableView(rows)

        case .rule:
            Divider()
        }
    }

    private func tableView(_ rows: [[String]]) -> some View {
        let columnCount = rows.map(\.count).max() ?? 0
        let widths = (0..<columnCount).map { column in
            rows.map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
        }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                MarkdownInline(source: row.padded(widths: widths))
                    .font(.system(.caption, design: .monospaced))
                if index == 0 {
                    Divider().padding(.vertical, 2)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.weight(.bold)
        case 2: return .headline
        case 3: return .subheadline.weight(.semibold)
        default: return .callout.weight(.semibold)
        }
    }
}

/// One run of Markdown text, rendered by Foundation's own parser.
struct MarkdownInline: View {
    let source: String
    var font: Font?

    var body: some View {
        Text(attributed)
            .font(font)
            .tint(Color.accentColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: source, options: options) {
            return parsed
        }
        return AttributedString(source)
    }
}

// MARK: - Parsing

/// A block of Markdown.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(String)
    case quote(String)
    case bullet([String])
    case numbered([String])
    case table([[String]])
    case rule
}

/// A Markdown document, split into blocks.
struct MarkdownDocument {
    let blocks: [MarkdownBlock]

    init(_ source: String) {
        blocks = MarkdownDocument.parse(source)
    }

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A fenced code block. The fence is three backticks or three
            // tildes; the language after the fence is ignored, because the
            // phone does not highlight anything.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence) { break }
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            // A heading.
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                if hashes <= 6, trimmed.dropFirst(hashes).hasPrefix(" ") {
                    flushParagraph()
                    let text = String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: hashes, text: text))
                    index += 1
                    continue
                }
            }

            // A horizontal rule.
            if trimmed.count >= 3,
               trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            // A block quote.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quote.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            // A pipe table: a header row followed by a separator row.
            if trimmed.contains("|"), index + 1 < lines.count {
                let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
                let isSeparator = separator.contains("|")
                    && separator.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " })
                if isSeparator {
                    flushParagraph()
                    var rows: [[String]] = [cells(from: line)]
                    index += 2
                    while index < lines.count {
                        let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                        guard candidate.contains("|") else { break }
                        rows.append(cells(from: lines[index]))
                        index += 1
                    }
                    blocks.append(.table(rows))
                    continue
                }
            }

            // A bullet list.
            if bulletItem(line) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, let item = bulletItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.bullet(items))
                continue
            }

            // A numbered list.
            if numberedItem(line) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, let item = numberedItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.numbered(items))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    /// The text of a bullet item, or nil if the line is not one.
    static func bulletItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The text of a numbered item, or nil if the line is not one.
    static func numberedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let digits = trimmed[trimmed.startIndex..<dot]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) else { return nil }
        let rest = trimmed[trimmed.index(after: dot)...]
        guard rest.hasPrefix(" ") else { return nil }
        return String(rest).trimmingCharacters(in: .whitespaces)
    }

    /// The cells of a pipe row.
    static func cells(from line: String) -> [String] {
        var parts = line.trimmingCharacters(in: .whitespaces)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        if let first = parts.first, first.isEmpty { parts.removeFirst() }
        if let last = parts.last, last.isEmpty { parts.removeLast() }
        return parts
    }
}

private extension Array where Element == String {
    /// Pad each cell to the column width so the table keeps its shape.
    func padded(widths: [Int]) -> String {
        enumerated()
            .map { index, cell in
                let width = index < widths.count ? widths[index] : cell.count
                return cell.padding(toLength: width, withPad: " ", startingAt: 0)
            }
            .joined(separator: " | ")
    }
}
