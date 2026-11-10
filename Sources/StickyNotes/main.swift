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

func populateColors(_ popup: NSPopUpButton) {
    popup.removeAllItems()
    popup.addItems(withTitles: ["Yellow", "Rose", "Sage", "Sky", "Lavender"])
    for (index, item) in popup.itemArray.enumerated() {
        let color = palette[index]
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
    func insertBullet() {
        guard isEditable, !hasMarkedText() else { return }
        let selection = selectedRange()
        guard selection.location != NSNotFound, NSMaxRange(selection) <= (string as NSString).length else { return }
        let paragraph = listParagraphRange(at: selection.location)
        breakUndoCoalescing()
        insertText("• ", replacementRange: NSRange(location: paragraph.location, length: 0))
        setSelectedRange(NSRange(location: selection.location + 2, length: selection.length))
        breakUndoCoalescing()
    }
    override func insertNewline(_ sender: Any?) {
        guard isEditable, !hasMarkedText() else { super.insertNewline(sender); return }
        let text = string as NSString
        let selection = selectedRange()
        guard selection.location != NSNotFound, NSMaxRange(selection) <= text.length else { return }
        let paragraphRange = listParagraphRange(at: selection.location)
        let start = paragraphRange.location, contentsEnd = NSMaxRange(paragraphRange)
        let paragraph = text.substring(with: paragraphRange) as NSString
        let prefixRange = paragraph.range(of: "^[\\t ]*•[\\t ]*", options: .regularExpression)
        guard prefixRange.location == 0,
              selection.location >= start + prefixRange.length,
              NSMaxRange(selection) <= contentsEnd else { super.insertNewline(sender); return }
        let prefix = paragraph.substring(with: prefixRange)
        let content = paragraph.substring(from: prefixRange.length)
        breakUndoCoalescing()
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // An empty item ends the list without leaving a stray bullet behind.
            insertText("", replacementRange: NSRange(location: start, length: contentsEnd - start))
        } else {
            // A single editor operation preserves typing style, undo, and autosave.
            insertText("\n" + prefix, replacementRange: selection)
        }
        breakUndoCoalescing()
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
        for (index, label) in ["LTR", "RTL"].enumerated() {
            directionControl.setLabel(label, forSegment: index); directionControl.setWidth(34, forSegment: index)
            directionControl.setToolTip(index == 0 ? "Write left to right" : "Write right to left", forSegment: index)
        }
        directionControl.setAccessibilityLabel("Writing direction")
        directionControl.target = self; directionControl.action = #selector(directionChanged(_:))
        let controls = row([heading, fontPicker, button("B", self, #selector(bold)), button("U", self, #selector(underline)), button("•", self, #selector(bullet))])
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
        let c = dark ? NSColor(calibratedWhite: 0.18, alpha: 1) : palette[colors.indexOfSelectedItem]
        window?.backgroundColor = c
        for view in [primaryEditor, flow.secondary] { view.backgroundColor = c; view.textColor = dark ? .white : .black }
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
        setParagraphStyle { $0.baseWritingDirection = direction }
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
        library = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        library.isReleasedWhenClosed = false; library.title = ""; library.titleVisibility = .hidden
        library.titlebarAppearsTransparent = true; library.titlebarSeparatorStyle = .none
        library.minSize = NSSize(width: 720, height: 420)
        libraryController = LibraryController()
        library.contentViewController = libraryController
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
    @objc func showSettings() {
        if let settings { settings.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false); w.title = "Settings"; w.isReleasedWhenClosed = false; w.center(); settings = w
        w.appearance = AppAppearanceMode.current.appearance
        let d = UserDefaults.standard
        configureAppearancePicker()
        rtlToggle.state = d.bool(forKey: "rtl") ? .on : .off
        font.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted()); font.selectItem(withTitle: d.string(forKey: "font")!)
        size.addItems(withTitles: ["12", "14", "17", "20", "24", "28"]); size.selectItem(withTitle: String(Int(d.double(forKey: "size"))))
        populateColors(color); color.selectItem(at: d.integer(forKey: "color")); opacity.doubleValue = d.double(forKey: "opacity")
        for control: NSControl in [rtlToggle, font, size, color, opacity] { control.target = self; control.action = #selector(saveSettings) }
        let hint = NSTextField(wrappingLabelWithString: "Version \(appVersion)\n\nFont, direction and color apply to new notes. Opacity applies to all open notes. Keep note above is set separately on each note. Changes are saved automatically.")
        let stack = NSStackView(views: [row([NSTextField(labelWithString: "Appearance"), appearancePicker]), row([NSTextField(labelWithString: "Opacity"), opacity, opacityLabel]), row([NSTextField(labelWithString: "Font"), font, size]), row([NSTextField(labelWithString: "New note color"), color]), rtlToggle, hint]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18; layout(stack, in: w.contentView!); saveSettings(); w.makeKeyAndOrderFront(nil)
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
