import SwiftUI

/// Markdown for the agent's replies.
///
/// `Text(AttributedString(markdown:))` only understands inline styles, so headings, lists, tables
/// and fenced code all collapse into one paragraph. This view splits a reply into blocks first and
/// styles each block, then parses the inline emphasis inside it.
struct MarkdownText: View {
    let text: String

    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                content(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func content(for block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let line):
            Text(line)
                .font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, 2)
        case .paragraph(let line):
            Text(line)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").fontWeight(.bold).foregroundStyle(.secondary)
                        Text(item)
                    }
                }
            }
        case .numbers(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(item)
                    }
                }
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(.footnote, design: .monospaced))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.5).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .quote(let line):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Color(white: 0.5).opacity(0.4))
                    .frame(width: 3)
                Text(line).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.caption)
                                .fontWeight(index == 0 ? .semibold : .regular)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        case .rule:
            Divider()
        }
    }
}

/// A single block of a Markdown document, already inline-parsed.
struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int, AttributedString)
        case paragraph(AttributedString)
        case bullets([AttributedString])
        case numbers([AttributedString])
        case code(String)
        case quote(AttributedString)
        case table([[AttributedString]])
        case rule
    }

    let id: Int
    let kind: Kind
}

// MARK: - Parsing

extension MarkdownBlock {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var kinds: [Kind] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                i += 1
                continue
            }

            if line.hasPrefix("```") {
                i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                // Drop the trailing newline fences usually leave behind.
                while code.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { code.removeLast() }
                kinds.append(.code(code.joined(separator: "\n")))
                continue
            }

            if let (level, title) = heading(line) {
                kinds.append(.heading(level, inline(title)))
                i += 1
                continue
            }

            if isRule(line) {
                kinds.append(.rule)
                i += 1
                continue
            }

            if line.hasPrefix(">") {
                var quoted: [String] = []
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix(">") else { break }
                    quoted.append(String(next.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                kinds.append(.quote(inline(quoted.joined(separator: " "))))
                continue
            }

            if let rows = table(at: i, in: lines) {
                kinds.append(.table(rows.rows.map { $0.map(inline) }))
                i = rows.next
                continue
            }

            if bulletText(line) != nil {
                var items: [String] = []
                while i < lines.count, let item = bulletText(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    i += 1
                }
                kinds.append(.bullets(items.map(inline)))
                continue
            }

            if numberedText(line) != nil {
                var items: [String] = []
                while i < lines.count, let item = numberedText(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    i += 1
                }
                kinds.append(.numbers(items.map(inline)))
                continue
            }

            var paragraph: [String] = []
            while i < lines.count, !startsBlock(lines[i]) {
                paragraph.append(lines[i].trimmingCharacters(in: .whitespaces))
                i += 1
            }
            if paragraph.isEmpty {
                i += 1
                continue
            }
            kinds.append(.paragraph(inline(paragraph.joined(separator: " "))))
        }

        return kinds.enumerated().map { MarkdownBlock(id: $0.offset, kind: $0.element) }
    }

    /// Inline-only parse, so `**bold**`, `*italic*`, `` `code` ``, `[links](…)` and `~~strike~~` work
    /// without swallowing block structure.
    static func inline(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    private static func heading(_ line: String) -> (Int, String)? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let marks: Set<Character> = ["-", "*", "_"]
        guard let first = line.first, marks.contains(first) else { return false }
        return line.allSatisfy { $0 == first || $0 == " " }
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedText(_ line: String) -> String? {
        var digits = 0
        for character in line {
            if character.isNumber { digits += 1 } else { break }
        }
        guard digits > 0 else { return nil }
        let rest = line.dropFirst(digits)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
        let body = rest.dropFirst()
        guard body.first == " " else { return nil }
        return body.trimmingCharacters(in: .whitespaces)
    }

    private static func startsBlock(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return true }
        if line.hasPrefix("```") || line.hasPrefix(">") { return true }
        if heading(line) != nil || isRule(line) { return true }
        if bulletText(line) != nil || numberedText(line) != nil { return true }
        return false
    }

    private static func table(at index: Int, in lines: [String]) -> (rows: [[String]], next: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard header.contains("|"), isTableSeparator(separator) else { return nil }

        var rows: [[String]] = [cells(header)]
        var i = index + 2
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard line.contains("|"), !line.isEmpty else { break }
            rows.append(cells(line))
            i += 1
        }
        // Every row should line up with the header once short rows are padded.
        let width = rows.map(\.count).max() ?? 0
        rows = rows.map { row in
            row.count >= width ? row : row + Array(repeating: "", count: width - row.count)
        }
        return (rows, i)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("-") else { return false }
        let allowed: Set<Character> = ["|", "-", ":", " "]
        return line.allSatisfy { allowed.contains($0) } && line.contains("|")
    }

    private static func cells(_ line: String) -> [String] {
        var parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first?.isEmpty == true { parts.removeFirst() }
        if parts.last?.isEmpty == true { parts.removeLast() }
        return parts
    }
}
