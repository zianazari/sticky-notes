import AppKit
import UniformTypeIdentifiers

enum AppAppearanceMode: String, CaseIterable {
    case system, light, dark
    var title: String { rawValue.capitalized }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    static var current: AppAppearanceMode {
        AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system
    }
}

struct Note: Codable {
    var id = UUID()
    var title = "Untitled note"
    var richText = Data()
    var isEmpty: Bool {
        if richText.isEmpty { return title == "Untitled note" || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let content = NSAttributedString(rtfd: richText, documentAttributes: nil) ?? NSAttributedString(rtf: richText, documentAttributes: nil) else { return false }
        var hasAttachment = false
        content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, _, stop in
            if value != nil { hasAttachment = true; stop.pointee = true }
        }
        return !hasAttachment && content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var groupID: UUID? = nil
    var color = 0
    var modified = Date()
    var columnCount: Int? = nil
    var keepAbove: Bool? = nil // Optional for compatibility with previously saved notes.
}
let palette: [NSColor] = [NSColor(red: 1, green: 0.93, blue: 0.64, alpha: 1), NSColor(red: 1, green: 0.79, blue: 0.82, alpha: 1), NSColor(red: 0.77, green: 0.91, blue: 0.78, alpha: 1), NSColor(red: 0.75, green: 0.87, blue: 1, alpha: 1), NSColor(red: 0.88, green: 0.80, blue: 1, alpha: 1)]

enum NoteColors {
    static var intensity: Double {
        guard let value = UserDefaults.standard.object(forKey: "colorIntensity") as? NSNumber else { return 0.5 }
        let number = value.doubleValue
        return number.isFinite ? min(1, max(0, number)) : 0.5
    }
    static func color(_ base: NSColor) -> NSColor {
        let amount = intensity
        if amount == 0.5 { return base }
        guard let rgb = base.usingColorSpace(.deviceRGB) else { return base }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(calibratedHue: hue, saturation: min(0.9, saturation * amount * 2), brightness: brightness, alpha: 1)
    }
    static func paper(_ index: Int, dark: Bool) -> NSColor {
        let tint = color(palette[min(max(index, 0), palette.count - 1)])
        if dark {
            let neutral = NSColor(calibratedWhite: 0.18, alpha: 1)
            return neutral.blended(withFraction: intensity * 0.22, of: tint) ?? neutral
        }
        return tint
    }
    static func card(_ base: NSColor, dark: Bool) -> NSColor {
        let tint = color(base)
        let fade = dark ? 0.77 : min(1, max(0, 1.16 * (1 - intensity)))
        return tint.blended(withFraction: fade, of: dark ? .black : .white) ?? tint
    }
}

func populateColors(_ popup: NSPopUpButton) {
    popup.removeAllItems()
    popup.addItems(withTitles: ["Yellow", "Rose", "Sage", "Sky", "Lavender"])
    for (index, item) in popup.itemArray.enumerated() {
        let color = NoteColors.color(palette[index])
        let image = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { rect in
            color.setFill()
            let swatch = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
            swatch.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke(); swatch.lineWidth = 0.5; swatch.stroke()
            return true
        }
        image.isTemplate = false
        item.image = image
    }
}
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"

struct NoteGroup: Codable, Equatable {
    var id = UUID()
    var name: String
}

final class Store {
    static let shared = Store()
    let url: URL
    var groupsURL: URL { url.deletingLastPathComponent().appendingPathComponent("groups.json") }
    var notes: [Note] = []
    var groups: [NoteGroup] = []
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StickyNotes/notes.json")) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                notes = try JSONDecoder().decode([Note].self, from: Data(contentsOf: url))
            }
            if FileManager.default.fileExists(atPath: groupsURL.path) {
                groups = try JSONDecoder().decode([NoteGroup].self, from: Data(contentsOf: groupsURL))
            }
        } catch { fatalError("Cannot read saved notes or groups; original files preserved: \(error)") }
    }
    func resolvedGroupID(for note: Note) -> UUID? {
        guard let id = note.groupID, groups.contains(where: { $0.id == id }) else { return nil }
        return id
    }
    func validName(_ name: String, excluding id: UUID? = nil) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80,
              !groups.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return nil }
        return clean
    }
    @discardableResult func createGroup(name: String) -> NoteGroup? {
        guard let name = validName(name) else { return nil }
        let group = NoteGroup(name: name); groups.append(group); return group
    }
    @discardableResult func renameGroup(id: UUID, name: String) -> Bool {
        guard let name = validName(name, excluding: id), let i = groups.firstIndex(where: { $0.id == id }) else { return false }
        groups[i].name = name; return true
    }
    func removeGroup(id: UUID) {
        // Group deletion never deletes note content. Orphaned IDs also display as Ungrouped.
        groups.removeAll { $0.id == id }
        for index in notes.indices where notes[index].groupID == id { notes[index].groupID = nil }
    }
    @discardableResult func moveNote(id: UUID, to groupID: UUID?) -> Bool {
        guard let i = notes.firstIndex(where: { $0.id == id }),
              groupID == nil || groups.contains(where: { $0.id == groupID }) else { return false }
        notes[i].groupID = groupID; return true
    }
    func write() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the existing note-array format so prior notes need no destructive migration.
        // If the second write fails, removed IDs resolve to Ungrouped on reopening.
        try JSONEncoder().encode(groups).write(to: groupsURL, options: .atomic)
        try JSONEncoder().encode(notes).write(to: url, options: .atomic)
    }
    func save() {
        do { try write() }
        catch { let alert = NSAlert(); alert.messageText = "Could not save notes"; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
}
func writingDirectionIcon(rightToLeft: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
        let path = NSBezierPath(); path.lineWidth = 1.5; path.lineCapStyle = .round; path.lineJoinStyle = .round
        // A directional arrow above text lines distinguishes direction from alignment.
        path.move(to: NSPoint(x: 3, y: 14)); path.line(to: NSPoint(x: 19, y: 14))
        let tip: CGFloat = rightToLeft ? 3 : 19
        let tail: CGFloat = rightToLeft ? 6 : 16
        path.move(to: NSPoint(x: tail, y: 17)); path.line(to: NSPoint(x: tip, y: 14)); path.line(to: NSPoint(x: tail, y: 11))
        for (y, length) in [(7.0, 16.0), (3.0, 11.0)] {
            let start = rightToLeft ? 19 - length : 3
            path.move(to: NSPoint(x: start, y: y)); path.line(to: NSPoint(x: start + length, y: y))
        }
        NSColor.black.setStroke(); path.stroke(); return true
    }
    image.isTemplate = true
    image.accessibilityDescription = rightToLeft ? "Write right to left" : "Write left to right"
    return image
}

func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
    let b = NSButton(title: title, target: target, action: action); b.bezelStyle = .rounded; return b
}
func row(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = 8; return s
}
func layout(_ stack: NSStackView, in view: NSView, topInset: CGFloat = 16) {
    stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)])
}
// Text attachments use the same selection and undo-aware deletion as ordinary text.
final class NoteTextView: NSTextView {
    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if !pastePlainText(board.string(forType: .string), richData: board.data(forType:)) {
            super.paste(sender)
        }
    }

    @discardableResult
    func pastePlainText(_ plainText: String?, richData: (NSPasteboard.PasteboardType) -> Data?) -> Bool {
        guard isEditable else { return false }
        // Use the plain representation when available. Some sources only
        // advertise rich text, so decode it and discard its attributes.
        let text = plainText ?? richClipboardText(readData: richData)
        guard let text, !text.isEmpty else { return false }
        let plain = text.replacingOccurrences(of: "\u{FFFC}", with: "")
        // Let AppKit handle image-only clipboard contents as attachments.
        if plain != text && plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        var attributes = typingAttributes
        attributes.removeValue(forKey: .attachment)
        breakUndoCoalescing()
        insertText(NSAttributedString(string: plain, attributes: attributes), replacementRange: selectedRange())
        breakUndoCoalescing()
        return true
    }

    private func richClipboardText(readData: (NSPasteboard.PasteboardType) -> Data?) -> String? {
        let richTypes: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.rtfd, .rtfd), (.rtf, .rtf), (.html, .html)
        ]
        for (type, documentType) in richTypes {
            if let data = readData(type),
               let content = try? NSAttributedString(data: data, options: [.documentType: documentType],
                                                      documentAttributes: nil),
               !content.string.isEmpty {
                return content.string
            }
        }
        return nil
    }

    var appearanceDidChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
    var didBecomeActive: ((NoteTextView) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { didBecomeActive?(self) }
        return accepted
    }
    // Foundation paragraph ranges include form-feed column breaks. List commands
    // must treat those breaks as boundaries without replacing the column break.
    func listParagraphRange(at location: Int) -> NSRange {
        let text = string as NSString
        var start = 0, end = 0, contentsEnd = 0
        text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                               for: NSRange(location: location, length: 0))
        let previousBreak = text.range(of: "\u{000c}", options: .backwards,
                                      range: NSRange(location: start, length: location - start))
        if previousBreak.location != NSNotFound { start = NSMaxRange(previousBreak) }
        let nextBreak = text.range(of: "\u{000c}", options: [],
                                  range: NSRange(location: location, length: max(0, contentsEnd - location)))
        if nextBreak.location != NSNotFound { contentsEnd = nextBreak.location }
        return NSRange(location: start, length: contentsEnd - start)
    }
    private static let listPrefix = try! NSRegularExpression(pattern: "^([\\t ]*)(?:•[\\t ]*|([0-9]+)\\.(?:[\\t ]+|$))")

    func insertBullet() { insertListMarker("• ") }
    func insertNumberedItem() { insertListMarker("1. ", numbered: true) }

    private func listMatch(in line: NSString) -> NSTextCheckingResult? {
        Self.listPrefix.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length))
    }

    private func insertListMarker(_ marker: String, numbered: Bool = false) {
        guard isEditable, !hasMarkedText() else { return }
        let text = string as NSString
        let selection = selectedRange()
        guard selection.location != NSNotFound, NSMaxRange(selection) <= text.length else { return }
        let paragraph = listParagraphRange(at: selection.location)
        var markerRange = NSRange(location: paragraph.location, length: 0)
        var marker = marker
        var number = 1
        var indent = ""
        if numbered {
            let line = text.substring(with: paragraph) as NSString
            let leadingSpace = line.range(of: "^[\\t ]*", options: .regularExpression)
            indent = line.substring(with: leadingSpace)
            markerRange.location += leadingSpace.length
            if let existing = listMatch(in: line) {
                if existing.range(at: 2).location != NSNotFound { return }
                markerRange.length = existing.range.length - leadingSpace.length
            }
            if let previousEnd = previousListLineEnd(before: paragraph.location, in: text) {
                let previousLine = text.substring(with: listParagraphRange(at: previousEnd)) as NSString
                if let previous = listMatch(in: previousLine), previous.range(at: 2).location != NSNotFound,
                   previousLine.substring(with: previous.range(at: 1)) == indent,
                   let previousNumber = Int(previousLine.substring(with: previous.range(at: 2))), previousNumber < Int.max {
                    number = previousNumber + 1
                }
            }
            marker = "\(number). "
        }
        editList(groupUndo: numbered) {
            insertText(marker, replacementRange: markerRange)
            let newMarkerEnd = markerRange.location + marker.utf16.count
            let offset = newMarkerEnd - NSMaxRange(markerRange)
            let start = max(newMarkerEnd, selection.location + offset)
            let end = max(start, NSMaxRange(selection) + offset)
            setSelectedRange(NSRange(location: start, length: end - start))
            if numbered { renumberFollowingItems(after: newMarkerEnd, number: number, indent: indent) }
        }
    }

    private func editList(groupUndo: Bool, changes: () -> Void) {
        breakUndoCoalescing()
        let undo = groupUndo ? undoManager : nil
        undo?.beginUndoGrouping()
        changes()
        breakUndoCoalescing()
        undo?.endUndoGrouping()
    }

    private func listLineBreakLength(at index: Int, in text: NSString) -> Int {
        guard index < text.length, let scalar = UnicodeScalar(text.character(at: index)),
              scalar.value != 0x0C, CharacterSet.newlines.contains(scalar) else { return 0 }
        return scalar.value == 0x0D && index + 1 < text.length && text.character(at: index + 1) == 0x0A ? 2 : 1
    }

    private func previousListLineEnd(before start: Int, in text: NSString) -> Int? {
        guard start > 0 else { return nil }
        if start > 1 && listLineBreakLength(at: start - 2, in: text) == 2 { return start - 2 }
        return listLineBreakLength(at: start - 1, in: text) == 1 ? start - 1 : nil
    }

    private func renumberFollowingItems(after location: Int, number: Int, indent: String) {
        let text = string as NSString
        let end = NSMaxRange(listParagraphRange(at: location))
        let separatorLength = listLineBreakLength(at: end, in: text)
        guard separatorLength > 0, number < Int.max else { return }
        renumberItems(startingAt: end + separatorLength, number: number + 1, indent: indent)
    }

    private func renumberItems(startingAt location: Int, number: Int, indent: String) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        var lineStart = location
        var nextNumber = number
        var changes: [(range: NSRange, digits: String)] = []
        while lineStart < text.length {
            let lineRange = listParagraphRange(at: lineStart)
            guard lineRange.location == lineStart else { break }
            let line = text.substring(with: lineRange) as NSString
            guard let match = listMatch(in: line), match.range(at: 2).location != NSNotFound,
                  line.substring(with: match.range(at: 1)) == indent else { break }
            let digits = String(nextNumber)
            let numberRange = match.range(at: 2)
            if line.substring(with: numberRange) != digits {
                changes.append((NSRange(location: lineRange.location + numberRange.location, length: numberRange.length), digits))
            }
            let lineEnd = NSMaxRange(lineRange)
            let separatorLength = listLineBreakLength(at: lineEnd, in: text)
            guard separatorLength > 0, nextNumber < Int.max else { break }
            lineStart = lineEnd + separatorLength
            nextNumber += 1
        }
        guard !changes.isEmpty else { return }
        let selection = selectedRange()
        guard shouldChangeText(inRanges: changes.map { NSValue(range: $0.range) },
                               replacementStrings: changes.map(\.digits)) else { return }
        func adjustedPosition(_ position: Int) -> Int {
            var shift = 0
            for change in changes {
                guard position > change.range.location else { break }
                let newLength = change.digits.utf16.count
                if position < NSMaxRange(change.range) {
                    return change.range.location + shift + min(position - change.range.location, newLength)
                }
                shift += newLength - change.range.length
            }
            return position + shift
        }
        storage.beginEditing()
        for change in changes.reversed() {
            storage.replaceCharacters(in: change.range, with: change.digits)
        }
        storage.endEditing()
        let start = adjustedPosition(selection.location)
        setSelectedRange(NSRange(location: start, length: adjustedPosition(NSMaxRange(selection)) - start))
        didChangeText()
    }

    override func deleteBackward(_ sender: Any?) {
        deleteWithListUpdate(adjacentOffset: -1) { super.deleteBackward(sender) }
    }

    override func deleteForward(_ sender: Any?) {
        deleteWithListUpdate(adjacentOffset: 0) { super.deleteForward(sender) }
    }

    override func delete(_ sender: Any?) {
        deleteWithListUpdate { super.delete(sender) }
    }

    override func cut(_ sender: Any?) {
        deleteWithListUpdate { super.cut(sender) }
    }

    private var updatingListDeletion = false

    private func deleteWithListUpdate(adjacentOffset: Int? = nil, action: () -> Void) {
        guard isEditable, !hasMarkedText(), !updatingListDeletion else { action(); return }
        let text = string as NSString
        var range = selectedRange()
        if range.length == 0, let adjacentOffset, range.location != NSNotFound {
            let index = range.location + adjacentOffset
            if (0..<text.length).contains(index) { range = text.rangeOfComposedCharacterSequence(at: index) }
        }
        updateListAfterDeleting(range, action: action)
    }

    private func updateListAfterDeleting(_ range: NSRange, action: () -> Void) {
        let text = string as NSString
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= text.length else {
            action()
            return
        }

        // Find the last affected marker and the first item that follows it.
        var affected = listParagraphRange(at: NSMaxRange(range) - 1)
        let line = text.substring(with: affected) as NSString
        guard let marker = listMatch(in: line), marker.range(at: 2).location != NSNotFound else { action(); return }
        let digits = marker.range(at: 2)
        let markerRange = NSRange(location: affected.location + digits.location, length: digits.length + 1)
        let end = NSMaxRange(affected)
        let separatorLength = listLineBreakLength(at: end, in: text)
        guard NSIntersectionRange(range, markerRange).length > 0, separatorLength > 0,
              end + separatorLength < text.length,
              let number = Int(line.substring(with: digits)) else { action(); return }
        let following = end + separatorLength
        let indent = line.substring(with: marker.range(at: 1))
        var firstNumber = number
        while range.location < affected.location,
              let previousEnd = previousListLineEnd(before: affected.location, in: text) {
            let previousRange = listParagraphRange(at: previousEnd)
            let previous = text.substring(with: previousRange) as NSString
            guard let match = listMatch(in: previous), match.range(at: 2).location != NSNotFound,
                  previous.substring(with: match.range(at: 1)) == indent else { break }
            let previousDigits = match.range(at: 2)
            let previousMarker = NSRange(location: previousRange.location + previousDigits.location, length: previousDigits.length + 1)
            guard NSIntersectionRange(range, previousMarker).length > 0,
                  let previousNumber = Int(previous.substring(with: previousDigits)) else { break }
            firstNumber = previousNumber
            affected = previousRange
        }

        let expectedLength = text.length - range.length
        updatingListDeletion = true
        defer { updatingListDeletion = false }
        editList(groupUndo: true) {
            action()
            let updated = string as NSString
            guard updated.length == expectedLength else { return }
            let nextStart = following - range.length
            // If part of the first marker still forms a numbered item, count it.
            if affected.location < nextStart {
                let remaining = updated.substring(with: listParagraphRange(at: affected.location)) as NSString
                if let match = listMatch(in: remaining), match.range(at: 2).location != NSNotFound {
                    guard firstNumber < Int.max else { return }
                    firstNumber += 1
                }
            }
            renumberItems(startingAt: nextStart, number: firstNumber, indent: indent)
        }
    }
    override func insertNewline(_ sender: Any?) {
        guard isEditable, !hasMarkedText() else { super.insertNewline(sender); return }
        let text = string as NSString
        let selection = selectedRange()
        guard selection.location != NSNotFound, NSMaxRange(selection) <= text.length else { return }
        let paragraphRange = listParagraphRange(at: selection.location)
        let start = paragraphRange.location, contentsEnd = NSMaxRange(paragraphRange)
        let paragraph = text.substring(with: paragraphRange) as NSString
        guard let match = listMatch(in: paragraph),
              selection.location >= start + match.range.length,
              NSMaxRange(selection) <= contentsEnd else { super.insertNewline(sender); return }
        let content = paragraph.substring(from: match.range.length)
        let isEmptyItem = content.trimmingCharacters(in: .whitespaces).isEmpty
        var nextPrefix = paragraph.substring(with: match.range)
        let numberRange = match.range(at: 2)
        var nextNumber: Int?
        if numberRange.location != NSNotFound && !isEmptyItem {
            guard let number = Int(paragraph.substring(with: numberRange)), number < Int.max else {
                super.insertNewline(sender)
                return
            }
            nextNumber = number + 1
            nextPrefix = (nextPrefix as NSString).replacingCharacters(in: numberRange, with: String(number + 1))
        }
        if isEmptyItem {
            // An empty item ends the list without leaving a marker behind.
            updateListAfterDeleting(paragraphRange) {
                editList(groupUndo: false) { insertText("", replacementRange: paragraphRange) }
            }
            return
        }
        editList(groupUndo: nextNumber != nil) {
            insertText("\n" + nextPrefix, replacementRange: selection)
            if let nextNumber {
                renumberFollowingItems(after: selectedRange().location, number: nextNumber,
                                       indent: paragraph.substring(with: match.range(at: 1)))
            }
        }
    }
    var prepareEmptyColumn: (() -> Bool)?
    var resizeOrigin: NSRect?
    var resizePreview: NSRect?
    func selectedImage() -> NSImage? {
        let range = selectedRange()
        guard range.length == 1, range.location < (textStorage?.length ?? 0),
              let attachment = textStorage?.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment else { return nil }
        if let image = (attachment.attachmentCell as? NSTextAttachmentCell)?.image { return image }
        if let data = attachment.fileWrapper?.regularFileContents { return NSImage(data: data) }
        return nil
    }
    @discardableResult func resizeSelectedImage(to width: CGFloat) -> Bool {
        guard width.isFinite, (20...2000).contains(width), let original = selectedImage(), original.size.width > 0 else { return false }
        let range = selectedRange()
        let image = original.copy() as! NSImage
        image.size = NSSize(width: width, height: original.size.height * width / original.size.width)
        // Persist the logical size in the image representations as well as its cell.
        for rep in image.representations { rep.size = image.size }
        guard let data = image.tiffRepresentation else { return false }
        let wrapper = FileWrapper(regularFileWithContents: data); wrapper.preferredFilename = "image-\(UUID().uuidString).tiff"
        let replacement = NSTextAttachment(fileWrapper: wrapper)
        replacement.attachmentCell = NSTextAttachmentCell(imageCell: image)
        let content = NSMutableAttributedString(attributedString: textStorage!.attributedSubstring(from: range))
        content.addAttribute(.attachment, value: replacement, range: NSRange(location: 0, length: 1))
        insertText(content, replacementRange: range)
        setSelectedRange(range)
        layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        needsDisplay = true
        return true
    }
    func selectedImageRect() -> NSRect? {
        guard selectedImage() != nil, let manager = layoutManager, let container = textContainer else { return nil }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: selectedRange(), actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }
    func resizeHandle(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.maxX - 12, y: rect.maxY - 12, width: 12, height: 12)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = resizePreview ?? selectedImageRect() else { return }
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)); outline.lineWidth = 2; outline.stroke()
        NSColor.controlAccentColor.setFill(); resizeHandle(rect).fill()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let original = resizeOrigin else { super.mouseDragged(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        let width = min(2000, max(20, point.x - original.minX))
        resizePreview = NSRect(origin: original.origin, size: NSSize(width: width, height: original.height * width / max(1, original.width)))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if resizeOrigin != nil {
            if let preview = resizePreview { resizeSelectedImage(to: preview.width) }
            resizeOrigin = nil; resizePreview = nil; needsDisplay = true
            return
        }
        super.mouseUp(with: event)
    }

    @discardableResult func insertImage(_ image: NSImage) -> Bool {
        guard image.isValid, image.size.width > 0, image.size.height > 0 else { return false }
        let copy = image.copy() as! NSImage
        let width = min(360, max(60, bounds.width - 32))
        if copy.size.width > width { copy.size = NSSize(width: width, height: copy.size.height * width / copy.size.width) }
        guard let data = copy.tiffRepresentation else { return false }
        let wrapper = FileWrapper(regularFileWithContents: data); wrapper.preferredFilename = "image-\(UUID().uuidString).tiff"
        let attachment = NSTextAttachment(fileWrapper: wrapper); attachment.attachmentCell = NSTextAttachmentCell(imageCell: copy)
        let content = NSMutableAttributedString(attachment: attachment)
        if let style = typingAttributes[.paragraphStyle] { content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length)) }
        insertText(content, replacementRange: selectedRange())
        return true
    }
    static let imageDragTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .png, .tiff] + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
    private var imageDragCache: (name: NSPasteboard.Name, changeCount: Int, images: [NSImage])?

    static func images(from items: [NSPasteboardItem]) -> [NSImage] {
        items.compactMap { item in
            // Prefer the original local file when the drag also includes a preview.
            if let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL,
               let image = NSImage(contentsOf: url), image.isValid { return image }
            for type in imageDragTypes where type != .fileURL {
                if let data = item.data(forType: type), let image = NSImage(data: data), image.isValid { return image }
            }
            return nil
        }
    }
    func droppedImages(_ sender: NSDraggingInfo) -> [NSImage] {
        let board = sender.draggingPasteboard
        if let cache = imageDragCache, cache.name == board.name, cache.changeCount == board.changeCount { return cache.images }
        let images = Self.images(from: board.pasteboardItems ?? [])
        imageDragCache = (board.name, board.changeCount, images)
        return images
    }
    private func acceptsImageDrop(_ sender: NSDraggingInfo) -> Bool {
        isEditable && sender.draggingSourceOperationMask.contains(.copy) && !droppedImages(sender).isEmpty
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if acceptsImageDrop(sender) { return .copy }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if acceptsImageDrop(sender) { return .copy }
        return super.draggingUpdated(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if acceptsImageDrop(sender) { return true }
        return super.prepareForDragOperation(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        imageDragCache = nil
        super.draggingExited(sender)
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        imageDragCache = nil
        super.concludeDragOperation(sender)
    }
    @discardableResult func insertDroppedImages(_ images: [NSImage], at point: NSPoint) -> Bool {
        guard isEditable, !images.isEmpty else { return false }
        breakUndoCoalescing()
        let undo = undoManager
        undo?.beginUndoGrouping()
        defer { undo?.endUndoGrouping(); breakUndoCoalescing() }
        // An unused second column needs its own insertion position before dropping.
        if prepareEmptyColumn?() != true {
            let index = min(characterIndexForInsertion(at: point), textStorage?.length ?? 0)
            setSelectedRange(NSRange(location: index, length: 0))
        }
        window?.makeFirstResponder(self)
        var inserted = false
        for image in images { if insertImage(image) { inserted = true } }
        return inserted
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard acceptsImageDrop(sender) else { return super.performDragOperation(sender) }
        let images = droppedImages(sender)
        defer { imageDragCache = nil }
        return insertDroppedImages(images, at: convert(sender.draggingLocation, from: nil))
    }

    func attachmentRange(at point: NSPoint) -> NSRange? {
        guard let manager = layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return nil }
        manager.ensureLayout(for: container)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: local, in: container)
        guard glyph < manager.numberOfGlyphs else { return nil }
        let character = manager.characterIndexForGlyph(at: glyph)
        guard character < storage.length,
              storage.attribute(.attachment, at: character, effectiveRange: nil) != nil,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
        return NSRange(location: character, length: 1)
    }
    override func mouseDown(with event: NSEvent) {
        if prepareEmptyColumn?() == true { return }
        let point = convert(event.locationInWindow, from: nil)
        if let rect = selectedImageRect(), resizeHandle(rect).insetBy(dx: -4, dy: -4).contains(point) {
            resizeOrigin = rect; resizePreview = rect
            return
        }
        needsDisplay = true
        if let range = attachmentRange(at: convert(event.locationInWindow, from: nil)) {
            window?.makeFirstResponder(self)
            setSelectedRange(range)
            return
        }
        super.mouseDown(with: event)
    }
}

// Two linked text containers share one attributed document and one layout manager.
final class FlowDocument: NSView {
    let primary: NoteTextView
    let secondary: NoteTextView
    var columns = 1
    var viewportHeight: CGFloat = 200
    private var arranging = false
    override var isFlipped: Bool { true }
    init(primary: NoteTextView) {
        self.primary = primary
        let container = NSTextContainer(containerSize: NSSize(width: 200, height: 200))
        primary.layoutManager!.addTextContainer(container)
        secondary = NoteTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)
        for view in [primary, secondary] {
            view.isRichText = true; view.isEditable = true; view.isSelectable = true; view.importsGraphics = true; view.allowsUndo = true
            view.isVerticallyResizable = false; view.isHorizontallyResizable = false
            view.autoresizingMask = []
            view.textContainerInset = NSSize(width: 8, height: 12)
            view.textContainer?.widthTracksTextView = false
            view.textContainer?.heightTracksTextView = false
            view.registerForDraggedTypes(NoteTextView.imageDragTypes)
            addSubview(view)
        }
        secondary.prepareEmptyColumn = { [weak self] in self?.prepareSecondaryInsertion() ?? false }
        secondary.isHidden = true
        autoresizingMask = [.width]
    }
    // Clicking an empty second column creates a real container break, like Word.
    // Both columns still edit the same attributed document.
    @discardableResult func prepareSecondaryInsertion() -> Bool {
        guard columns == 2, let manager = primary.layoutManager,
              let container = secondary.textContainer, let storage = primary.textStorage else { return false }
        manager.ensureLayout(for: container)
        guard manager.glyphRange(for: container).length == 0 else { return false }
        var attributes = primary.typingAttributes
        attributes.removeValue(forKey: .attachment)
        if attributes[.font] == nil { attributes[.font] = primary.font ?? NSFont.systemFont(ofSize: 17) }
        if !storage.string.hasSuffix("\u{000c}") {
            primary.insertText(NSAttributedString(string: "\u{000c}", attributes: attributes),
                               replacementRange: NSRange(location: storage.length, length: 0))
        }
        reflow()
        secondary.typingAttributes = attributes
        window?.makeFirstResponder(secondary)
        secondary.setSelectedRange(NSRange(location: storage.length, length: 0))
        secondary.needsDisplay = true
        return true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !arranging { reflow() }
    }
    func reflow() {
        guard !arranging, bounds.width > 30, let manager = primary.layoutManager else { return }
        arranging = true; defer { arranging = false }
        let two = columns == 2
        let gap: CGFloat = two ? 20 : 0
        let width = max(30, (bounds.width - gap) / CGFloat(two ? 2 : 1))
        let textWidth = max(10, width - 16)
        let first = primary.textContainer!, second = secondary.textContainer!
        func configure(_ height: CGFloat) {
            first.containerSize = NSSize(width: textWidth, height: height)
            second.containerSize = NSSize(width: textWidth, height: two ? height : 0)
            manager.ensureLayout(for: first)
            if two { manager.ensureLayout(for: second) }
        }
        var height = max(40, viewportHeight - 24)
        if two {
            func fits(_ h: CGFloat) -> Bool {
                configure(h)
                return NSMaxRange(manager.glyphRange(for: second)) >= manager.numberOfGlyphs
            }
            if !fits(height) {
                var low = height, high = height * 2
                while !fits(high) { high *= 2 }
                for _ in 0..<18 {
                    let middle = (low + high) / 2
                    if fits(middle) { high = middle } else { low = middle }
                }
                height = ceil(high) + 2
            }
            configure(height)
        } else {
            configure(10_000_000)
            height = max(height, ceil(manager.usedRect(for: first).height) + 24)
            configure(height)
        }
        secondary.isHidden = !two
        let rtl = primary.baseWritingDirection == .rightToLeft
        primary.frame = NSRect(x: two && rtl ? width + gap : 0, y: 0, width: width, height: height + 24)
        secondary.frame = NSRect(x: rtl ? 0 : width + gap, y: 0, width: width, height: height + 24)
        super.setFrameSize(NSSize(width: bounds.width, height: max(viewportHeight, height + 24)))
    }
}

final class NoteWindow: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let id: UUID
    let primaryEditor = NoteTextView()
    lazy var flow = FlowDocument(primary: primaryEditor)
    private weak var lastActiveEditor: NoteTextView?
    var editor: NoteTextView {
        if let active = window?.firstResponder as? NoteTextView,
           active === primaryEditor || active === flow.secondary { return active }
        if let lastActiveEditor, !lastActiveEditor.isHidden { return lastActiveEditor }
        return primaryEditor
    }
    let fontPicker = NSPopUpButton()
    let alignmentControl = NSSegmentedControl()
    let directionControl = NSSegmentedControl()
    let noteScroll = NSScrollView()
    let columns = NSPopUpButton()
    let colors = NSPopUpButton()
    let keepAboveToggle = NSButton(checkboxWithTitle: "Keep note above", target: nil, action: nil)
    init(note: Note) {
        id = note.id
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.appearance = AppAppearanceMode.current.appearance
        super.init(window: w); w.titlebarAppearsTransparent = true; w.titlebarSeparatorStyle = .none; w.delegate = self; w.title = note.title; w.center(); w.setFrameAutosaveName(note.id.uuidString)
        let scroll = noteScroll; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        editor.isRichText = true; editor.importsGraphics = true; editor.allowsUndo = true; editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.registerForDraggedTypes(NoteTextView.imageDragTypes)
        editor.textContainerInset = NSSize(width: 12, height: 16)
        editor.font = NSFont(name: UserDefaults.standard.string(forKey: "font") ?? "Helvetica", size: UserDefaults.standard.double(forKey: "size")) ?? .systemFont(ofSize: 17)
        editor.textColor = .black
        editor.alignment = UserDefaults.standard.bool(forKey: "rtl") ? .right : .left
        editor.baseWritingDirection = UserDefaults.standard.bool(forKey: "rtl") ? .rightToLeft : .leftToRight
        if let rich = (NSAttributedString(rtfd: note.richText, documentAttributes: nil) ?? NSAttributedString(rtf: note.richText, documentAttributes: nil)) { editor.textStorage?.setAttributedString(rich) }
        flow.columns = note.columnCount == 2 ? 2 : 1
        scroll.documentView = flow
        primaryEditor.delegate = self; flow.secondary.delegate = self
        for textView in [primaryEditor, flow.secondary] {
            textView.didBecomeActive = { [weak self] active in self?.lastActiveEditor = active; self?.syncFormattingControls() }
        }
        populateColors(colors); colors.selectItem(at: note.color); colors.target = self; colors.action = #selector(changeColor)
        let heading = NSPopUpButton(); heading.addItems(withTitles: ["Text", "H1", "H2", "H3"]); heading.target = self; heading.action = #selector(headingChanged(_:))
        fontPicker.addItem(withTitle: "System Font")
        fontPicker.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        fontPicker.widthAnchor.constraint(equalToConstant: 140).isActive = true
        fontPicker.cell?.lineBreakMode = .byTruncatingTail
        fontPicker.toolTip = "Font family"; fontPicker.setAccessibilityLabel("Font family")
        fontPicker.target = self; fontPicker.action = #selector(fontChanged(_:))
        alignmentControl.segmentCount = 3; alignmentControl.trackingMode = .selectOne
        for (index, symbol) in ["text.alignleft", "text.aligncenter", "text.alignright"].enumerated() {
            let label = ["Align left", "Align center", "Align right"][index]
            alignmentControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: index)
            alignmentControl.setToolTip(label, forSegment: index); alignmentControl.setWidth(28, forSegment: index)
        }
        alignmentControl.setAccessibilityLabel("Text alignment")
        alignmentControl.target = self; alignmentControl.action = #selector(alignmentChanged(_:))
        directionControl.segmentCount = 2; directionControl.trackingMode = .selectOne
        for index in 0..<2 {
            directionControl.setImage(writingDirectionIcon(rightToLeft: index == 1), forSegment: index)
            directionControl.setWidth(28, forSegment: index)
            directionControl.setToolTip(index == 0 ? "Write left to right" : "Write right to left", forSegment: index)
        }
        directionControl.setAccessibilityLabel("Writing direction")
        directionControl.target = self; directionControl.action = #selector(directionChanged(_:))
        let numberedList = button("1.", self, #selector(numberedItem))
        numberedList.toolTip = "Numbered list"
        numberedList.setAccessibilityLabel("Numbered list")
        let controls = row([heading, fontPicker, button("B", self, #selector(bold)), button("U", self, #selector(underline)), button("•", self, #selector(bullet)), numberedList])
        keepAboveToggle.state = note.keepAbove == true ? .on : .off
        keepAboveToggle.target = self; keepAboveToggle.action = #selector(changeKeepAbove)
        columns.addItems(withTitles: ["1 column", "2 columns"])
        columns.selectItem(at: flow.columns - 1)
        columns.target = self; columns.action = #selector(addColumns(_:))
        let footer = row([colors, button("Image", self, #selector(addImage)), keepAboveToggle])
        let insertControls = row([columns, alignmentControl, directionControl])
        let stack = NSStackView(views: [controls, insertControls, scroll, footer]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor, constant: -8),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        // Keep every control visible; shrink only the available editor space.
        let controlsSize = controls.fittingSize
        let footerSize = footer.fittingSize
        let minimumEditorHeight: CGFloat = 64
        NSLayoutConstraint.activate([
            controls.widthAnchor.constraint(greaterThanOrEqualToConstant: controlsSize.width),
            footer.widthAnchor.constraint(greaterThanOrEqualToConstant: footerSize.width),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumEditorHeight)
        ])
        let minimum = NSSize(width: ceil(max(controlsSize.width, footerSize.width, insertControls.fittingSize.width) + 16),
                             height: ceil(controlsSize.height + footerSize.height + insertControls.fittingSize.height + minimumEditorHeight + 34))
        w.contentMinSize = minimum
        let current = w.contentView!.bounds.size
        if current.width < minimum.width || current.height < minimum.height {
            w.setContentSize(NSSize(width: max(current.width, minimum.width), height: max(current.height, minimum.height)))
        }
        primaryEditor.appearanceDidChange = { [weak self] in self?.paint() }
        applyPreferences(); paint(); refreshFlow(); syncFormattingControls()
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyPreferences() { window?.level = keepAboveToggle.state == .on ? .floating : .normal; window?.alphaValue = UserDefaults.standard.double(forKey: "opacity"); paint() }
    func paint() {
        let dark = primaryEditor.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        refreshPaperColor()
        for view in [primaryEditor, flow.secondary] { view.textColor = dark ? .white : .black }
    }
    func refreshPaperColor() {
        let dark = primaryEditor.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let background = NoteColors.paper(colors.indexOfSelectedItem, dark: dark)
        window?.backgroundColor = background
        for view in [primaryEditor, flow.secondary] { view.backgroundColor = background }
    }
    func refreshColorIntensity() {
        let selectedColor = colors.indexOfSelectedItem
        populateColors(colors); colors.selectItem(at: selectedColor)
        refreshPaperColor()
    }
    @objc func changeKeepAbove() {
        applyPreferences()
        persist()
    }
    @objc func addImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        editor.insertImage(image); persist()
    }
    @objc func addColumns(_ popup: NSPopUpButton) {
        let selection = editor.selectedRange()
        // Remove the old table layout without deleting text, formatting or attachments.
        let storage = primaryEditor.textStorage!
        var styles: [(NSRange, NSParagraphStyle)] = []
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let old = value as? NSParagraphStyle, !old.textBlocks.isEmpty {
                let style = old.mutableCopy() as! NSMutableParagraphStyle
                style.textBlocks = []; styles.append((range, style))
            }
        }
        for (range, style) in styles { storage.addAttribute(.paragraphStyle, value: style, range: range) }
        for view in [primaryEditor, flow.secondary] {
            if let old = view.typingAttributes[.paragraphStyle] as? NSParagraphStyle {
                let style = old.mutableCopy() as! NSMutableParagraphStyle; style.textBlocks = []
                view.typingAttributes[.paragraphStyle] = style
            }
        }
        flow.columns = popup.indexOfSelectedItem == 1 ? 2 : 1
        if flow.columns == 1 {
            // Preserve text order and paragraph separation when removing column breaks.
            let string = storage.string as NSString
            for index in (0..<string.length).reversed() where string.character(at: index) == 12 {
                storage.replaceCharacters(in: NSRange(location: index, length: 1), with: "\n")
            }
        }
        refreshFlow()
        primaryEditor.setSelectedRange(selection)
        window?.makeFirstResponder(primaryEditor)
        persist()
    }
    func refreshFlow() {
        guard isWindowLoaded else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        flow.viewportHeight = max(64, noteScroll.contentSize.height)
        flow.setFrameSize(NSSize(width: max(40, noteScroll.contentSize.width), height: flow.frame.height))
    }
    func windowDidResize(_ notification: Notification) { refreshFlow() }
    @objc func changeColor() { paint(); persist() }
    func syncFormattingControls() {
        guard fontPicker.numberOfItems > 0 else { return }
        let active = editor
        let selection = active.selectedRange()
        let attributes = selection.length > 0 && selection.location < (active.textStorage?.length ?? 0)
            ? active.textStorage!.attributes(at: selection.location, effectiveRange: nil) : active.typingAttributes
        let font = attributes[.font] as? NSFont ?? active.font ?? .systemFont(ofSize: 17)
        let family = font.familyName ?? "System Font"
        fontPicker.selectItem(withTitle: fontPicker.item(withTitle: family) == nil ? "System Font" : family)
        let style = attributes[.paragraphStyle] as? NSParagraphStyle
        let alignment = style?.alignment ?? active.alignment
        alignmentControl.selectedSegment = alignment == .center ? 1 : alignment == .right ? 2 : 0
        let direction = style?.baseWritingDirection ?? active.baseWritingDirection
        directionControl.selectedSegment = direction == .rightToLeft ? 1 : 0
    }
    private func replaceFormatting(in active: NoteTextView, range: NSRange, with replacement: NSAttributedString) {
        let selection = active.selectedRange()
        guard active.shouldChangeText(in: range, replacementString: nil) else { return }
        active.breakUndoCoalescing()
        active.textStorage?.replaceCharacters(in: range, with: replacement)
        active.didChangeText()
        active.setSelectedRange(selection)
        active.breakUndoCoalescing()
    }
    @objc func fontChanged(_ sender: NSPopUpButton) {
        guard let family = sender.titleOfSelectedItem else { return }
        let active = editor
        window?.makeFirstResponder(active)
        let manager = NSFontManager.shared
        func convert(_ font: NSFont) -> NSFont {
            if family == "System Font" {
                return manager.convert(.systemFont(ofSize: font.pointSize), toHaveTrait: manager.traits(of: font))
            }
            return manager.convert(font, toFamily: family)
        }
        let selection = active.selectedRange()
        var typing = active.typingAttributes
        typing[.font] = convert(typing[.font] as? NSFont ?? active.font ?? .systemFont(ofSize: 17))
        if selection.length > 0, let storage = active.textStorage {
            let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: selection))
            replacement.enumerateAttribute(.font, in: NSRange(location: 0, length: replacement.length)) { value, range, _ in
                replacement.addAttribute(.font, value: convert(value as? NSFont ?? .systemFont(ofSize: 17)), range: range)
            }
            replaceFormatting(in: active, range: selection, with: replacement)
        }
        active.typingAttributes = typing
        syncFormattingControls(); persist()
    }
    func setParagraphStyle(_ change: (NSMutableParagraphStyle) -> Void) {
        let active = editor
        window?.makeFirstResponder(active)
        let selection = active.selectedRange()
        guard selection.location != NSNotFound, let storage = active.textStorage else { return }
        let first = active.listParagraphRange(at: selection.location)
        let last = active.listParagraphRange(at: selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location)
        let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var typing = active.typingAttributes
        let base = typing[.paragraphStyle] as? NSParagraphStyle ?? .default
        let typingStyle = base.mutableCopy() as! NSMutableParagraphStyle
        change(typingStyle); typing[.paragraphStyle] = typingStyle
        if range.length > 0 {
            let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            replacement.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: replacement.length)) { value, range, _ in
                let style = (value as? NSParagraphStyle ?? base).mutableCopy() as! NSMutableParagraphStyle
                change(style); replacement.addAttribute(.paragraphStyle, value: style, range: range)
            }
            replaceFormatting(in: active, range: range, with: replacement)
        }
        active.typingAttributes = typing
        refreshFlow(); syncFormattingControls(); persist()
    }
    @objc func alignmentChanged(_ sender: NSSegmentedControl) {
        let alignment: NSTextAlignment = [.left, .center, .right][max(0, min(2, sender.selectedSegment))]
        setParagraphStyle { $0.alignment = alignment }
    }
    @objc func directionChanged(_ sender: NSSegmentedControl) {
        let direction: NSWritingDirection = sender.selectedSegment == 1 ? .rightToLeft : .leftToRight
        setParagraphStyle {
            $0.baseWritingDirection = direction
            $0.alignment = direction == .rightToLeft ? .right : .left
        }
    }
    @objc func bold() {
        let range = editor.selectedRange()
        let current = (editor.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 17)
        let manager = NSFontManager.shared
        let newFont = manager.traits(of: current).contains(.boldFontMask) ? manager.convert(current, toNotHaveTrait: .boldFontMask) : manager.convert(current, toHaveTrait: .boldFontMask)
        if range.length > 0 { editor.textStorage?.addAttribute(.font, value: newFont, range: range) }
        editor.typingAttributes[.font] = newFont; persist()
    }
    @objc func underline() { editor.underline(self); persist() }
    @objc func left() { setParagraphStyle { $0.alignment = .left } }
    @objc func center() { setParagraphStyle { $0.alignment = .center } }
    @objc func right() { setParagraphStyle { $0.alignment = .right } }
    @objc func bullet() {
        let active = editor
        window?.makeFirstResponder(active)
        active.insertBullet()
    }
    @objc func numberedItem() {
        let active = editor
        window?.makeFirstResponder(active)
        active.insertNumberedItem()
    }
    @objc func headingChanged(_ sender: NSPopUpButton) {
        let size: CGFloat = [UserDefaults.standard.double(forKey: "size"), 30, 24, 20][sender.indexOfSelectedItem]
        let font = sender.indexOfSelectedItem == 0 ? NSFont.systemFont(ofSize: size) : NSFont.boldSystemFont(ofSize: size)
        let range = (editor.string as NSString).paragraphRange(for: editor.selectedRange())
        if range.length > 0 { editor.textStorage?.addAttribute(.font, value: font, range: range) }
        editor.typingAttributes[.font] = font; persist()
    }
    func textDidChange(_ notification: Notification) { refreshFlow(); syncFormattingControls(); persist() }
    func textViewDidChangeSelection(_ notification: Notification) { syncFormattingControls() }
    func persist() {
        guard let i = Store.shared.notes.firstIndex(where: { $0.id == id }) else { return }
        Store.shared.notes[i].columnCount = flow.columns
        Store.shared.notes[i].richText = editor.rtfd(from: NSRange(location: 0, length: editor.textStorage?.length ?? 0)) ?? Data()
        Store.shared.notes[i].title = String(editor.string.split(separator: "\n").first.map(String.init)?.prefix(70) ?? "Untitled note")
        Store.shared.notes[i].keepAbove = keepAboveToggle.state == .on
        Store.shared.notes[i].color = colors.indexOfSelectedItem; Store.shared.notes[i].modified = Date(); window?.title = Store.shared.notes[i].title
        Store.shared.save(); App.shared.reload()
    }
    func windowWillClose(_ notification: Notification) { persist() }
}
final class App: NSObject, NSApplicationDelegate {
    static let shared = App()
    var windows: [UUID: NoteWindow] = [:]
    var library: NSWindow!
    var libraryController: LibraryController!
    var settings: NSWindow?
    let appearancePicker = NSPopUpButton()
    let rtlToggle = NSButton(checkboxWithTitle: "Right-to-left for new notes", target: nil, action: nil)
    let opacity = NSSlider(value: 1, minValue: 0.25, maxValue: 1, target: nil, action: nil)
    let opacityLabel = NSTextField(labelWithString: "")
    let colorIntensity = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let colorIntensityLabel = NSTextField(labelWithString: "50%")
    let font = NSPopUpButton()
    let size = NSPopUpButton()
    let color = NSPopUpButton()
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["size": 17.0, "opacity": 1.0, "font": "Helvetica", "color": 0])
        applyAppearance()
        NSApp.setActivationPolicy(.regular)
        // Use the transparent source directly for the running Dock icon.
        if let url = Bundle.main.url(forResource: "DockIcon", withExtension: "png"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item); let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "About Sticky Notes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "All Notes", action: #selector(showLibrary), keyEquivalent: "l").target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit Sticky Notes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Dedicated native menu-bar entries, accessible from every note window.
        let newNoteItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let newNoteMenu = NSMenu(title: "File")
        newNoteMenu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "n").target = self
        newNoteItem.submenu = newNoteMenu; menu.addItem(newNoteItem)
        let editItem = NSMenuItem(); menu.addItem(editItem); let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = menu
        library = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        library.isReleasedWhenClosed = false; library.title = ""; library.titleVisibility = .hidden
        library.titlebarAppearsTransparent = true; library.titlebarSeparatorStyle = .none
        library.minSize = NSSize(width: 720, height: 420)
        libraryController = LibraryController()
        library.contentViewController = libraryController
        libraryController.installTitlebarControls(on: library)
        library.center(); library.setFrameAutosaveName("MyNotesLibrary")
        library.appearance = AppAppearanceMode.current.appearance
        showLibrary(); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showLibrary() { libraryController?.selectAllNotes(); library.makeKeyAndOrderFront(nil); reload() }
    func reload() { libraryController?.reload() }
    func open(_ n: Note) { if windows[n.id] == nil { windows[n.id] = NoteWindow(note: n) }; windows[n.id]?.showWindow(nil); windows[n.id]?.window?.makeKeyAndOrderFront(nil) }
    @objc func newNote() { var n = Note(); n.color = UserDefaults.standard.integer(forKey: "color"); n.groupID = libraryController?.currentGroupID; Store.shared.notes.insert(n, at: 0); Store.shared.save(); reload(); open(n) }
    @objc func deleteSelected() {
        guard let id = libraryController?.selectedNote?.id else { return }
        deleteNote(id: id)
    }
    func deleteNote(id: UUID) {
        guard let note = Store.shared.notes.first(where: { $0.id == id }) else { return }
        if !note.isEmpty {
            let alert = NSAlert(); alert.messageText = "Delete this note?"; alert.informativeText = note.title; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        windows[id]?.close(); windows.removeValue(forKey: id)
        Store.shared.notes.removeAll { $0.id == id }; Store.shared.save(); reload()
    }
    func configureAppearancePicker() {
        appearancePicker.removeAllItems()
        for mode in AppAppearanceMode.allCases {
            appearancePicker.addItem(withTitle: mode.title)
            appearancePicker.lastItem?.representedObject = mode.rawValue
        }
        appearancePicker.selectItem(withTitle: AppAppearanceMode.current.title)
        appearancePicker.setAccessibilityLabel("Appearance")
        appearancePicker.target = self; appearancePicker.action = #selector(appearanceChanged(_:))
    }
    @objc func appearanceChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String, let mode = AppAppearanceMode(rawValue: raw) else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
        applyAppearance()
    }
    func applyAppearance() {
        let appearance = AppAppearanceMode.current.appearance
        NSApp.appearance = appearance
        library?.appearance = appearance; settings?.appearance = appearance
        windows.values.forEach { $0.window?.appearance = appearance; $0.paint() }
        library?.contentView?.needsDisplay = true
    }
    func configureColorIntensity() {
        colorIntensity.doubleValue = NoteColors.intensity
        colorIntensity.isContinuous = true
        colorIntensity.setAccessibilityLabel("Color intensity")
        colorIntensity.toolTip = "Adjust note colors without changing window opacity"
        colorIntensity.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        colorIntensityLabel.alignment = .right
        colorIntensityLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        colorIntensityLabel.stringValue = "\(Int((NoteColors.intensity * 100).rounded()))%"
        colorIntensity.target = self; colorIntensity.action = #selector(colorIntensityChanged(_:))
    }
    @objc func colorIntensityChanged(_ sender: NSSlider) {
        UserDefaults.standard.set(min(1, max(0, sender.doubleValue)), forKey: "colorIntensity")
        colorIntensityLabel.stringValue = "\(Int((NoteColors.intensity * 100).rounded()))%"
        windows.values.forEach { $0.refreshColorIntensity() }
        libraryController?.refreshNoteColors()
        if color.numberOfItems > 0 {
            let selectedColor = color.indexOfSelectedItem
            populateColors(color); color.selectItem(at: selectedColor)
        }
    }
    @objc func showSettings() {
        if let settings { settings.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 410), styleMask: [.titled, .closable], backing: .buffered, defer: false); w.title = "Settings"; w.isReleasedWhenClosed = false; w.center(); settings = w
        w.appearance = AppAppearanceMode.current.appearance
        let d = UserDefaults.standard
        configureAppearancePicker(); configureColorIntensity()
        rtlToggle.state = d.bool(forKey: "rtl") ? .on : .off
        font.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted()); font.selectItem(withTitle: d.string(forKey: "font")!)
        size.addItems(withTitles: ["12", "14", "17", "20", "24", "28"]); size.selectItem(withTitle: String(Int(d.double(forKey: "size"))))
        populateColors(color); color.selectItem(at: d.integer(forKey: "color")); opacity.doubleValue = d.double(forKey: "opacity")
        for control: NSControl in [rtlToggle, font, size, color, opacity] { control.target = self; control.action = #selector(saveSettings) }
        let hint = NSTextField(wrappingLabelWithString: "Version \(appVersion)\n\nFont, direction and color apply to new notes. Opacity and color intensity apply to all notes. Keep note above is set separately on each note. Changes are saved automatically.")
        let stack = NSStackView(views: [row([NSTextField(labelWithString: "Appearance"), appearancePicker]), row([NSTextField(labelWithString: "Color intensity"), colorIntensity, colorIntensityLabel]), row([NSTextField(labelWithString: "Opacity"), opacity, opacityLabel]), row([NSTextField(labelWithString: "Font"), font, size]), row([NSTextField(labelWithString: "New note color"), color]), rtlToggle, hint]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18; layout(stack, in: w.contentView!); saveSettings(); w.makeKeyAndOrderFront(nil)
    }
    @objc func saveSettings() {
        let d = UserDefaults.standard; d.set(rtlToggle.state == .on, forKey: "rtl"); d.set(opacity.doubleValue, forKey: "opacity"); d.set(font.titleOfSelectedItem, forKey: "font"); d.set(Double(size.titleOfSelectedItem ?? "17")!, forKey: "size"); d.set(color.indexOfSelectedItem, forKey: "color"); opacityLabel.stringValue = "\(Int(opacity.doubleValue * 100))%"; windows.values.forEach { $0.applyPreferences() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showLibrary(); return true }
    func applicationWillTerminate(_ notification: Notification) { windows.values.forEach { $0.persist() } }
}
let app = NSApplication.shared
app.delegate = App.shared
app.run()
