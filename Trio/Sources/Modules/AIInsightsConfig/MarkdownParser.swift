import Foundation
import SwiftUI
import UIKit

/// Native markdown parser that converts markdown text to attributed strings
/// for both SwiftUI display and PDF generation with consistent styling.
enum MarkdownParser {
    // MARK: - Styling Configuration

    struct Style {
        let bodyFont: UIFont
        let bodyColor: UIColor
        let h1Font: UIFont
        let h2Font: UIFont
        let h3Font: UIFont
        let headerColor: UIColor
        let boldFont: UIFont
        let italicFont: UIFont
        let bulletIndent: CGFloat
        let lineSpacing: CGFloat
        let paragraphSpacing: CGFloat

        static let `default` = Style(
            bodyFont: .systemFont(ofSize: 14),
            bodyColor: .label,
            h1Font: .boldSystemFont(ofSize: 22),
            h2Font: .boldSystemFont(ofSize: 18),
            h3Font: .boldSystemFont(ofSize: 15),
            headerColor: .label,
            boldFont: .boldSystemFont(ofSize: 14),
            italicFont: .italicSystemFont(ofSize: 14),
            bulletIndent: 20,
            lineSpacing: 4,
            paragraphSpacing: 12
        )

        static let pdf = Style(
            bodyFont: .systemFont(ofSize: 11),
            bodyColor: .black,
            h1Font: .boldSystemFont(ofSize: 16),
            h2Font: .boldSystemFont(ofSize: 14),
            h3Font: .boldSystemFont(ofSize: 12),
            headerColor: .black,
            boldFont: .boldSystemFont(ofSize: 11),
            italicFont: .italicSystemFont(ofSize: 11),
            bulletIndent: 15,
            lineSpacing: 3,
            paragraphSpacing: 8
        )
    }

    // MARK: - Public API

    /// Parse markdown text into NSAttributedString for UIKit/PDF rendering
    static func parseToNSAttributedString(_ markdown: String, style: Style = .default) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")

        var inTable = false
        var tableLines: [String] = []

        for (index, line) in lines.enumerated() {
            // Check if we're starting or continuing a table
            if line.contains("|") && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                inTable = true
                tableLines.append(line)
                continue
            } else if inTable {
                // End of table, process it
                let tableAttr = parseTable(tableLines, style: style)
                result.append(tableAttr)
                result.append(NSAttributedString(string: "\n"))
                tableLines.removeAll()
                inTable = false
            }

            let parsedLine = parseLine(line, style: style)
            result.append(parsedLine)

            // Add newline if not the last line
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        // Handle any remaining table
        if !tableLines.isEmpty {
            let tableAttr = parseTable(tableLines, style: style)
            result.append(tableAttr)
        }

        return result
    }

    /// Parse markdown text into SwiftUI Text view with basic formatting
    @available(iOS 15.0, *)
    static func parseToSwiftUIText(_ markdown: String) -> Text {
        // Use iOS 15+ AttributedString markdown support for basic formatting
        // For more complex rendering, we fall back to a custom approach
        do {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
            let attributed = try AttributedString(markdown: markdown, options: options)
            return Text(attributed)
        } catch {
            return Text(markdown)
        }
    }

    // MARK: - Private Parsing Methods

    private static func parseLine(_ line: String, style: Style) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Headers
        if trimmed.hasPrefix("### ") {
            return parseHeader(String(trimmed.dropFirst(4)), font: style.h3Font, style: style)
        } else if trimmed.hasPrefix("## ") {
            return parseHeader(String(trimmed.dropFirst(3)), font: style.h2Font, style: style)
        } else if trimmed.hasPrefix("# ") {
            return parseHeader(String(trimmed.dropFirst(2)), font: style.h1Font, style: style)
        }

        // Bullet points
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return parseBullet(String(trimmed.dropFirst(2)), style: style)
        }

        // Numbered lists
        if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            let content = String(trimmed[match.upperBound...])
            let number = String(trimmed[..<match.upperBound])
            return parseNumberedItem(number: number, content: content, style: style)
        }

        // Regular paragraph with inline formatting
        return parseInlineFormatting(line, style: style)
    }

    private static func parseHeader(_ text: String, font: UIFont, style: Style) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = style.lineSpacing
        paragraphStyle.paragraphSpacingBefore = style.paragraphSpacing

        // Parse inline formatting within the header
        let inlineFormatted = parseInlineFormattingToMutable(text, baseFont: font, style: style)

        // Apply header-specific attributes to the entire string
        let range = NSRange(location: 0, length: inlineFormatted.length)
        inlineFormatted.addAttributes([
            .paragraphStyle: paragraphStyle,
            .foregroundColor: style.headerColor
        ], range: range)

        return inlineFormatted
    }

    private static func parseBullet(_ text: String, style: Style) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = style.lineSpacing
        paragraphStyle.headIndent = style.bulletIndent
        paragraphStyle.firstLineHeadIndent = 0

        let result = NSMutableAttributedString()

        // Bullet character
        let bullet = NSAttributedString(
            string: "  \u{2022} ",
            attributes: [
                .font: style.bodyFont,
                .foregroundColor: style.bodyColor
            ]
        )
        result.append(bullet)

        // Content with inline formatting
        let content = parseInlineFormattingToMutable(text, baseFont: style.bodyFont, style: style)
        content.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: content.length))
        result.append(content)

        return result
    }

    private static func parseNumberedItem(number: String, content: String, style: Style) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = style.lineSpacing
        paragraphStyle.headIndent = style.bulletIndent
        paragraphStyle.firstLineHeadIndent = 0

        let result = NSMutableAttributedString()

        // Number
        let numberAttr = NSAttributedString(
            string: "  \(number)",
            attributes: [
                .font: style.bodyFont,
                .foregroundColor: style.bodyColor
            ]
        )
        result.append(numberAttr)

        // Content with inline formatting
        let contentAttr = parseInlineFormattingToMutable(content, baseFont: style.bodyFont, style: style)
        contentAttr.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: contentAttr.length))
        result.append(contentAttr)

        return result
    }

    private static func parseInlineFormatting(_ text: String, style: Style) -> NSAttributedString {
        return parseInlineFormattingToMutable(text, baseFont: style.bodyFont, style: style)
    }

    private static func parseInlineFormattingToMutable(_ text: String, baseFont: UIFont, style: Style) -> NSMutableAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = style.lineSpacing

        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: style.bodyColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        // Process bold (**text** or __text__)
        applyPattern(to: result, pattern: #"\*\*(.+?)\*\*"#, font: style.boldFont)
        applyPattern(to: result, pattern: #"__(.+?)__"#, font: style.boldFont)

        // Process italic (*text* or _text_) - must be done after bold
        applyPattern(to: result, pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, font: style.italicFont)
        applyPattern(to: result, pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, font: style.italicFont)

        // Clean up markdown symbols
        cleanMarkdownSymbols(in: result)

        return result
    }

    private static func applyPattern(to attrString: NSMutableAttributedString, pattern: String, font: UIFont) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }

        let string = attrString.string
        let range = NSRange(location: 0, length: string.utf16.count)

        let matches = regex.matches(in: string, options: [], range: range)

        // Apply formatting in reverse order to preserve ranges
        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                let contentRange = match.range(at: 1)
                if let swiftRange = Range(contentRange, in: string) {
                    attrString.addAttribute(.font, value: font, range: contentRange)
                }
            }
        }
    }

    private static func cleanMarkdownSymbols(in attrString: NSMutableAttributedString) {
        // Remove markdown formatting symbols while preserving the styled text
        let patterns = [
            #"\*\*(.+?)\*\*"#,
            #"__(.+?)__"#,
            #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
            #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }

            var string = attrString.string
            var offset = 0

            let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count))

            for match in matches {
                let fullRange = NSRange(location: match.range.location - offset, length: match.range.length)
                if match.numberOfRanges >= 2 {
                    let contentRange = match.range(at: 1)
                    if let swiftContentRange = Range(contentRange, in: string) {
                        let content = String(string[swiftContentRange])
                        attrString.replaceCharacters(in: fullRange, with: content)
                        offset += match.range.length - content.count
                        string = attrString.string
                    }
                }
            }
        }
    }

    // MARK: - Table Parsing

    private static func parseTable(_ lines: [String], style: Style) -> NSAttributedString {
        guard lines.count >= 2 else { return NSAttributedString() }

        let result = NSMutableAttributedString()

        // Parse header row
        let headerCells = parseTableRow(lines[0])

        // Skip separator row (index 1) and parse data rows
        let dataRows = lines.dropFirst(2).map { parseTableRow($0) }

        // Calculate column widths based on content
        var maxWidths = headerCells.map { $0.count }
        for row in dataRows {
            for (index, cell) in row.enumerated() where index < maxWidths.count {
                maxWidths[index] = max(maxWidths[index], cell.count)
            }
        }

        // Render header
        let headerText = formatTableRow(headerCells, widths: maxWidths)
        let headerAttr = NSAttributedString(
            string: headerText + "\n",
            attributes: [
                .font: style.boldFont,
                .foregroundColor: style.bodyColor
            ]
        )
        result.append(headerAttr)

        // Render separator
        let separator = maxWidths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "+")
        let separatorAttr = NSAttributedString(
            string: separator + "\n",
            attributes: [
                .font: style.bodyFont,
                .foregroundColor: UIColor.gray
            ]
        )
        result.append(separatorAttr)

        // Render data rows
        for row in dataRows {
            let rowText = formatTableRow(row, widths: maxWidths)
            let rowAttr = NSAttributedString(
                string: rowText + "\n",
                attributes: [
                    .font: style.bodyFont,
                    .foregroundColor: style.bodyColor
                ]
            )
            result.append(rowAttr)
        }

        return result
    }

    private static func parseTableRow(_ line: String) -> [String] {
        return line
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.allSatisfy { $0 == "-" || $0 == ":" } }
    }

    private static func formatTableRow(_ cells: [String], widths: [Int]) -> String {
        var formatted: [String] = []
        for (index, cell) in cells.enumerated() {
            let width = index < widths.count ? widths[index] : cell.count
            formatted.append(cell.padding(toLength: width, withPad: " ", startingAt: 0))
        }
        return "| " + formatted.joined(separator: " | ") + " |"
    }
}

// MARK: - SwiftUI View for Markdown Rendering

@available(iOS 15.0, *)
struct MarkdownText: View {
    let content: String

    var body: some View {
        // Try native markdown first
        if let attributed = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(content)
        }
    }
}

// MARK: - SwiftUI View for Rich Markdown (including tables)

struct RichMarkdownView: View {
    let content: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(parseBlocks(), id: \.id) { block in
                    renderBlock(block)
                }
            }
        }
    }

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentText = ""
        var inTable = false
        var tableLines: [String] = []
        var blockId = 0

        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for table
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if !inTable {
                    // Save any pending text
                    if !currentText.isEmpty {
                        blocks.append(MarkdownBlock(id: blockId, type: .text, content: currentText))
                        blockId += 1
                        currentText = ""
                    }
                    inTable = true
                }
                tableLines.append(line)
            } else {
                if inTable {
                    // End table
                    blocks.append(MarkdownBlock(id: blockId, type: .table, content: tableLines.joined(separator: "\n")))
                    blockId += 1
                    tableLines.removeAll()
                    inTable = false
                }
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }
        }

        // Handle remaining content
        if inTable && !tableLines.isEmpty {
            blocks.append(MarkdownBlock(id: blockId, type: .table, content: tableLines.joined(separator: "\n")))
        } else if !currentText.isEmpty {
            blocks.append(MarkdownBlock(id: blockId, type: .text, content: currentText))
        }

        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.type {
        case .text:
            if #available(iOS 15.0, *) {
                MarkdownText(content: block.content)
                    .textSelection(.enabled)
            } else {
                Text(block.content)
            }
        case .table:
            TableView(content: block.content)
        }
    }
}

struct MarkdownBlock: Identifiable {
    let id: Int
    let type: BlockType
    let content: String

    enum BlockType {
        case text
        case table
    }
}

struct TableView: View {
    let content: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let rows = parseTable()

        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                        Text(rows[rowIndex][colIndex])
                            .font(rowIndex == 0 ? .caption.bold() : .caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                rowIndex == 0
                                    ? Color.secondary.opacity(0.2)
                                    : (rowIndex % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
                            )
                    }
                }
                if rowIndex == 0 {
                    Divider()
                }
            }
        }
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func parseTable() -> [[String]] {
        let lines = content.components(separatedBy: "\n")
        var rows: [[String]] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip separator rows
            if trimmed.contains("---") || trimmed.contains("===") {
                continue
            }

            let cells = trimmed
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        return rows
    }
}
