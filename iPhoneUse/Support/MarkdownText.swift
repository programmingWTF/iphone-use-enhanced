import SwiftUI
import UIKit

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
                        if let task = item.task {
                            Image(systemName: task ? "checkmark.square.fill" : "square")
                                .font(.footnote)
                                .foregroundStyle(task ? Color.accentColor : Color.secondary)
                        } else {
                            Text("•").fontWeight(.bold).foregroundStyle(.secondary)
                        }
                        Text(item.text)
                    }
                    .padding(.leading, CGFloat(min(item.level, 4)) * 16)
                }
            }
        case .numbers(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.marker).monospacedDigit().foregroundStyle(.secondary)
                        Text(item.text)
                    }
                    .padding(.leading, CGFloat(min(item.level, 4)) * 16)
                }
            }
        case .code(let language, let code):
            MarkdownCodeBlock(language: language, code: code)
        case .math(let formula):
            Text(verbatim: formula)
                .font(.system(.callout, design: .serif))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
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

/// One rendered line of a list, already inline-parsed.
struct MarkdownListItem {
    /// Nesting depth, from the line's leading indentation.
    let level: Int
    /// nil for a plain bullet, true/false for a `- [x]` / `- [ ]` task item.
    let task: Bool?
    /// The text in front of the item, e.g. "1." for an ordered list.
    let marker: String
    let text: AttributedString
}

/// A single block of a Markdown document, already inline-parsed.
struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int, AttributedString)
        case paragraph(AttributedString)
        case bullets([MarkdownListItem])
        case numbers([MarkdownListItem])
        case code(String?, String)
        case math(String)
        case quote(AttributedString)
        case table([[AttributedString]])
        case rule
    }

    let id: Int
    let kind: Kind
}

/// A fenced code block with its language and a copy button, so a command or snippet can go straight
/// to the clipboard.
private struct MarkdownCodeBlock: View {
    let language: String?
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = code
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        withAnimation(.easeOut(duration: 0.15)) { copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(copied ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "已复制代码" : "复制代码")
            }
            .padding(.top, 6)
            .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(white: 0.5).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
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
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                i += 1
                continue
            }

            if line.hasPrefix("```") {
                let info = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                // Drop the trailing newline fences usually leave behind.
                while code.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { code.removeLast() }
                kinds.append(.code(info.isEmpty ? nil : info, code.joined(separator: "\n")))
                continue
            }

            if line.hasPrefix("$$") {
                var body: [String] = []
                let rest = String(line.dropFirst(2))
                if rest.count >= 2, rest.hasSuffix("$$") {
                    body.append(String(rest.dropLast(2)))
                    i += 1
                } else {
                    if !rest.trimmingCharacters(in: .whitespaces).isEmpty { body.append(rest) }
                    i += 1
                    while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasSuffix("$$") {
                        body.append(lines[i])
                        i += 1
                    }
                    if i < lines.count {
                        let tail = lines[i].trimmingCharacters(in: .whitespaces)
                        body.append(String(tail.dropLast(2)))
                        i += 1
                    }
                }
                kinds.append(.math(MathRenderer.plain(body.joined(separator: " "))))
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

            if bulletItem(raw: raw) != nil {
                var items: [MarkdownListItem] = []
                while i < lines.count, let next = bulletItem(raw: lines[i]) {
                    items.append(next)
                    i += 1
                }
                kinds.append(.bullets(items))
                continue
            }

            if numberedItem(raw: raw) != nil {
                var items: [MarkdownListItem] = []
                while i < lines.count, let next = numberedItem(raw: lines[i]) {
                    items.append(next)
                    i += 1
                }
                kinds.append(.numbers(items))
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

    // MARK: Lists

    private static func indentation(_ raw: String) -> Int {
        var width = 0
        for character in raw {
            if character == " " {
                width += 1
            } else if character == "\t" {
                width += 4
            } else {
                break
            }
        }
        return width
    }

    private static func bulletItem(raw: String) -> MarkdownListItem? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        var body: String?
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            body = String(line.dropFirst(marker.count))
            break
        }
        guard var content = body else { return nil }
        content = content.trimmingCharacters(in: .whitespaces)

        var task: Bool?
        if content.hasPrefix("[ ]") || content.hasPrefix("[]") {
            task = false
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if content.hasPrefix("[x]") || content.hasPrefix("[X]") {
            task = true
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }

        return MarkdownListItem(
            level: indentation(raw) / 2,
            task: task,
            marker: "•",
            text: inline(content)
        )
    }

    private static func numberedItem(raw: String) -> MarkdownListItem? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        var digits = 0
        for character in line {
            if character.isNumber { digits += 1 } else { break }
        }
        guard digits > 0 else { return nil }
        let rest = line.dropFirst(digits)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
        let body = rest.dropFirst()
        guard body.first == " " else { return nil }
        let text = body.trimmingCharacters(in: .whitespaces)
        return MarkdownListItem(
            level: indentation(raw) / 2,
            task: nil,
            marker: String(line.prefix(digits)) + ".",
            text: inline(text)
        )
    }

    // MARK: Inline

    /// Emphasis flags for one run of inline text.
    private struct InlineStyle: OptionSet {
        let rawValue: Int
        static let bold = InlineStyle(rawValue: 1 << 0)
        static let italic = InlineStyle(rawValue: 1 << 1)
        static let code = InlineStyle(rawValue: 1 << 2)
        static let strike = InlineStyle(rawValue: 1 << 3)
        static let math = InlineStyle(rawValue: 1 << 4)
    }

    /// Inline-only parse, so `**bold**`, `*italic*`, `***both***`, `` `code` ``, `~~strike~~`,
    /// `[links](…)` and `$x^2$` math work without swallowing block structure.
    ///
    /// Foundation's Markdown parser is deliberately not used here: it drops the emphasis inside
    /// Chinese text and cannot express task checkboxes, so the tiny grammar below is parsed by hand.
    /// ASCII punctuation that a backslash can escape, per CommonMark. A model that
    /// wants a literal `*` writes `\*`, exactly like on GitHub.
    private static let escapable = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    static func inline(_ source: String) -> AttributedString {
        let characters = Array(source)
        var result = AttributedString()
        var plain = ""

        func flushPlain() {
            guard !plain.isEmpty else { return }
            append(plain, style: [], link: nil, to: &result)
            plain = ""
        }

        var i = 0
        while i < characters.count {
            let character = characters[i]
            // Backslash escapes win over every inline rule: the escaped character is
            // taken literally and cannot open or close emphasis.
            if character == "\\", i + 1 < characters.count, escapable.contains(characters[i + 1]) {
                plain.append(characters[i + 1])
                i += 2
                continue
            }
            if character == "`" || character == "*" || character == "_"
                || character == "~" || character == "$" || character == "[" {
                if let token = match(characters, at: i) {
                    flushPlain()
                    append(token.text, style: token.style, link: token.link, to: &result)
                    i = token.next
                    continue
                }
            }
            plain.append(character)
            i += 1
        }
        flushPlain()
        return result
    }

    private struct InlineToken {
        let text: String
        let style: InlineStyle
        let link: String?
        let next: Int
    }

    private static func match(_ characters: [Character], at index: Int) -> InlineToken? {
        let character = characters[index]

        if character == "`" {
            var fence = 0
            while index + fence < characters.count, characters[index + fence] == "`" { fence += 1 }
            let closing = String(repeating: "`", count: fence)
            guard let end = find(closing, in: characters, from: index + fence), end > index + fence else {
                return nil
            }
            let inner = String(characters[(index + fence)..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return InlineToken(
                text: inner.replacingOccurrences(of: "\n", with: " "),
                style: [.code], link: nil, next: end + fence
            )
        }

        if character == "*" || character == "_" {
            return emphasis(characters, at: index, marker: character)
        }

        if character == "~" {
            guard has(characters, at: index, "~~"),
                  let end = find("~~", in: characters, from: index + 2), end > index + 2 else { return nil }
            return InlineToken(text: String(characters[(index + 2)..<end]),
                               style: [.strike], link: nil, next: end + 2)
        }

        if character == "$" {
            guard !has(characters, at: index, "$$"),
                  let end = find("$", in: characters, from: index + 1), end > index + 1 else { return nil }
            let source = String(characters[(index + 1)..<end])
            return InlineToken(text: MathRenderer.plain(source), style: [.math], link: nil, next: end + 1)
        }

        if character == "[" {
            guard let labelEnd = find("]", in: characters, from: index + 1),
                  labelEnd + 1 < characters.count, characters[labelEnd + 1] == "(",
                  let urlEnd = find(")", in: characters, from: labelEnd + 2) else { return nil }
            let label = String(characters[(index + 1)..<labelEnd])
            let url = String(characters[(labelEnd + 2)..<urlEnd])
            return InlineToken(text: label, style: [], link: url, next: urlEnd + 1)
        }

        return nil
    }

    /// `*` / `_` emphasis with CommonMark's flanking rules, so `2 * 3 * 4` and
    /// `snake_case` stay literal while `*italic*`, `**bold**` and `***both***` work.
    private static func emphasis(
        _ characters: [Character],
        at index: Int,
        marker: Character
    ) -> InlineToken? {
        let previous = index > 0 ? characters[index - 1] : nil
        func after(_ offset: Int) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }
        func isWord(_ character: Character) -> Bool { character.isLetter || character.isNumber }

        for run in [3, 2, 1] {
            guard has(characters, at: index, String(repeating: marker, count: run)),
                  let opener = after(run), !opener.isWhitespace else { continue }
            // Underscores are not emphasis inside a word: `snake_case_name` is literal.
            if marker == "_", let previous, isWord(previous) { continue }
            guard let end = find(
                String(repeating: marker, count: run),
                in: characters,
                from: index + run
            ), end > index + run else { continue }
            guard !characters[end - 1].isWhitespace else { continue }
            if marker == "_", let closer = after(end - index + run), isWord(closer) { continue }
            let inner = String(characters[(index + run)..<end])
            guard !inner.contains("\n") else { continue }
            let style: InlineStyle = run == 3 ? [.bold, .italic] : (run == 2 ? [.bold] : [.italic])
            return InlineToken(text: inner, style: style, link: nil, next: end + run)
        }
        return nil
    }

    private static func has(_ characters: [Character], at index: Int, _ literal: String) -> Bool {
        let target = Array(literal)
        guard index + target.count <= characters.count else { return false }
        return Array(characters[index..<(index + target.count)]) == target
    }

    private static func find(_ needle: String, in characters: [Character], from start: Int) -> Int? {
        let target = Array(needle)
        guard !target.isEmpty, start <= characters.count - target.count else { return nil }
        var i = start
        while i <= characters.count - target.count {
            if Array(characters[i..<(i + target.count)]) == target { return i }
            i += 1
        }
        return nil
    }

    private static func append(
        _ text: String,
        style: InlineStyle,
        link: String?,
        to result: inout AttributedString
    ) {
        guard !text.isEmpty else { return }
        var piece = AttributedString(text)
        var intents: InlinePresentationIntent = []
        if style.contains(.bold) { intents.insert(.stronglyEmphasized) }
        if style.contains(.italic) { intents.insert(.emphasized) }
        if style.contains(.code) { intents.insert(.code) }
        if style.contains(.strike) { intents.insert(.strikethrough) }
        if !intents.isEmpty { piece.inlinePresentationIntent = intents }
        if let link, let url = URL(string: link) { piece.link = url }
        result.append(piece)
    }

    // MARK: Leafs

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

    private static func startsBlock(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return true }
        if line.hasPrefix("```") || line.hasPrefix(">") || line.hasPrefix("$$") { return true }
        if heading(line) != nil || isRule(line) || line.hasPrefix(">") { return true }
        if bulletItem(raw: raw) != nil || numberedItem(raw: raw) != nil { return true }
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

// MARK: - LaTeX

/// Turns a small, deliberately limited subset of LaTeX into readable Unicode.
///
/// The app has no math typesetting engine and no way to ship fonts for one, so `$…$` formulas are
/// converted into their closest plain-text form: greek letters, symbols, `\frac`, `\sqrt` and
/// super/subscripts. Anything it does not recognise is left in place rather than dropped.
enum MathRenderer {
    private static let commands: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ",
        "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "ϕ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
        "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "times": "×", "div": "÷", "cdot": "·", "pm": "±", "mp": "∓", "ast": "∗",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠",
        "approx": "≈", "equiv": "≡", "sim": "∼", "propto": "∝", "infty": "∞",
        "sum": "∑", "prod": "∏", "int": "∫", "partial": "∂", "nabla": "∇", "prime": "′",
        "to": "→", "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒", "leftrightarrow": "↔",
        "forall": "∀", "exists": "∃", "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆",
        "cup": "∪", "cap": "∩", "emptyset": "∅", "angle": "∠", "perp": "⊥", "degree": "°",
        "ell": "ℓ", "ldots": "…", "dots": "…", "quad": " ", "qquad": "  ",
        "sin": "sin", "cos": "cos", "tan": "tan", "log": "log", "ln": "ln", "exp": "exp",
        "lim": "lim", "max": "max", "min": "min", "det": "det", "mod": "mod",
    ]

    /// Commands that take a braced argument and are handled before the symbol table runs.
    private static let structural: Set<String> = ["frac", "dfrac", "sqrt", "text", "mathrm", "mathbf", "mathit", "operatorname", "left", "right"]

    static func plain(_ source: String) -> String {
        var text = fractions(source)
        text = roots(text)
        text = scripts(text)
        text = symbols(text)
        text = text.replacingOccurrences(of: "{", with: "")
        text = text.replacingOccurrences(of: "}", with: "")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fractions(_ input: String) -> String {
        let characters = Array(input)
        var output = ""
        var i = 0
        while i < characters.count {
            let name = commandName(characters, at: i)
            if name == "frac" || name == "dfrac" {
                let start = i + 1 + name.count
                if let (numerator, afterNumerator) = group(characters, from: start),
                   let (denominator, afterDenominator) = group(characters, from: afterNumerator) {
                    let top = plain(numerator)
                    let bottom = plain(denominator)
                    output += (top.count == 1 ? top : "(\(top))") + "/" + (bottom.count == 1 ? bottom : "(\(bottom))")
                    i = afterDenominator
                    continue
                }
            }
            output.append(characters[i])
            i += 1
        }
        return output
    }

    private static func roots(_ input: String) -> String {
        let characters = Array(input)
        var output = ""
        var i = 0
        while i < characters.count {
            let name = commandName(characters, at: i)
            if name == "sqrt" {
                let start = i + 1 + name.count
                if let (body, after) = group(characters, from: start) {
                    let inner = plain(body)
                    output += "√" + (inner.count == 1 ? inner : "(\(inner))")
                    i = after
                    continue
                }
            }
            output.append(characters[i])
            i += 1
        }
        return output
    }

    private static func scripts(_ input: String) -> String {
        let characters = Array(input)
        var output = ""
        var i = 0
        while i < characters.count {
            let character = characters[i]
            if (character == "^" || character == "_"), i + 1 < characters.count {
                var content: String?
                var next = i + 1
                if characters[i + 1] == "{" {
                    if let (inner, after) = group(characters, from: i + 1) {
                        content = inner
                        next = after
                    }
                } else {
                    content = String(characters[i + 1])
                    next = i + 2
                }
                if let content {
                    output += character == "^" ? superscript(content) : subscriptText(content)
                    i = next
                    continue
                }
            }
            output.append(character)
            i += 1
        }
        return output
    }

    private static func symbols(_ input: String) -> String {
        let characters = Array(input)
        var output = ""
        var i = 0
        while i < characters.count {
            let name = commandName(characters, at: i)
            if !name.isEmpty {
                let after = i + 1 + name.count
                if structural.contains(name) {
                    // Its argument was already consumed (or follows as plain text): drop the command.
                    i = after
                    continue
                }
                if let symbol = commands[name] {
                    output += symbol
                    i = after
                    continue
                }
                output += name
                i = after
                continue
            }
            output.append(characters[i])
            i += 1
        }
        return output
    }

    private static func commandName(_ characters: [Character], at index: Int) -> String {
        guard index < characters.count, characters[index] == "\\" else { return "" }
        var name = ""
        var j = index + 1
        while j < characters.count, characters[j].isLetter {
            name.append(characters[j])
            j += 1
        }
        return name
    }

    /// Returns the braced group that starts at `index` and the index just past its closing brace.
    private static func group(_ characters: [Character], from index: Int) -> (String, Int)? {
        guard index < characters.count, characters[index] == "{" else { return nil }
        var depth = 0
        var j = index
        var body = ""
        while j < characters.count {
            let character = characters[j]
            if character == "{" {
                depth += 1
                if depth > 1 { body.append(character) }
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return (body, j + 1) }
                body.append(character)
            } else {
                body.append(character)
            }
            j += 1
        }
        return nil
    }

    private static let superscripts: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷",
        "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "°": "°",
    ]

    private static let subscripts: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇",
        "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ",
        "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ",
        "x": "ₓ",
    ]

    private static func superscript(_ content: String) -> String {
        var mapped = ""
        for character in content {
            guard let replacement = superscripts[character] else { return "^(" + content + ")" }
            mapped += replacement
        }
        return mapped.isEmpty ? "^" : mapped
    }

    private static func subscriptText(_ content: String) -> String {
        var mapped = ""
        for character in content {
            guard let replacement = subscripts[character] else { return "_(" + content + ")" }
            mapped += replacement
        }
        return mapped.isEmpty ? "_" : mapped
    }
}
