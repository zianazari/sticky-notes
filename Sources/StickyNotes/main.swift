import AppKit
import UniformTypeIdentifiers

struct Note: Codable {
    var id = UUID()
    var title = "Untitled note"
    var richText = Data()
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

final class Store {
    static let shared = Store()
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StickyNotes/notes.json")
    var notes: [Note] = []
    init() {
        if FileManager.default.fileExists(atPath: url.path) {
            do { notes = try JSONDecoder().decode([Note].self, from: Data(contentsOf: url)) }
            catch { fatalError("Cannot read saved notes; original file preserved: \(error)") }
        }
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(notes).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(); alert.messageText = "Could not save notes"; alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
}
func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
    let b = NSButton(title: title, target: target, action: action); b.bezelStyle = .rounded; return b
}
func row(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = 8; return s
}
func layout(_ stack: NSStackView, in view: NSView) {
    stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)])
}
// Text attachments use the same selection and undo-aware deletion as ordinary text.
final class NoteTextView: NSTextView {
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

    func insertImage(_ image: NSImage) {
        let copy = image.copy() as! NSImage
        let width = min(360, max(60, bounds.width - 32))
        if copy.size.width > width { copy.size = NSSize(width: width, height: copy.size.height * width / copy.size.width) }
        guard let data = copy.tiffRepresentation else { return }
        let wrapper = FileWrapper(regularFileWithContents: data); wrapper.preferredFilename = "image-\(UUID().uuidString).tiff"
        let attachment = NSTextAttachment(fileWrapper: wrapper); attachment.attachmentCell = NSTextAttachmentCell(imageCell: copy)
        let content = NSMutableAttributedString(attachment: attachment)
        if let style = typingAttributes[.paragraphStyle] { content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length)) }
        insertText(content, replacementRange: selectedRange())
    }
    func droppedImages(_ sender: NSDraggingInfo) -> [NSImage] {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.compactMap { NSImage(contentsOf: $0) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !droppedImages(sender).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !droppedImages(sender).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let images = droppedImages(sender)
        guard !images.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        let index = min(characterIndexForInsertion(at: point), textStorage?.length ?? 0)
        setSelectedRange(NSRange(location: index, length: 0))
        window?.makeFirstResponder(self)
        for image in images { insertImage(image) }
        return true
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
            view.registerForDraggedTypes([.fileURL, .tiff, .png])
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
    var editor: NoteTextView {
        if let active = window?.firstResponder as? NoteTextView, active === flow.secondary { return active }
        return primaryEditor
    }
    let noteScroll = NSScrollView()
    let columns = NSPopUpButton()
    let colors = NSPopUpButton()
    let keepAboveToggle = NSButton(checkboxWithTitle: "Keep note above", target: nil, action: nil)
    init(note: Note) {
        id = note.id
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: w); w.titlebarAppearsTransparent = true; w.titlebarSeparatorStyle = .none; w.delegate = self; w.title = note.title; w.center(); w.setFrameAutosaveName(note.id.uuidString)
        let scroll = noteScroll; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        editor.isRichText = true; editor.importsGraphics = true; editor.allowsUndo = true; editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.registerForDraggedTypes([.fileURL, .tiff, .png])
        editor.textContainerInset = NSSize(width: 12, height: 16)
        editor.font = NSFont(name: UserDefaults.standard.string(forKey: "font") ?? "Helvetica", size: UserDefaults.standard.double(forKey: "size")) ?? .systemFont(ofSize: 17)
        editor.textColor = .black
        editor.alignment = UserDefaults.standard.bool(forKey: "rtl") ? .right : .left
        editor.baseWritingDirection = UserDefaults.standard.bool(forKey: "rtl") ? .rightToLeft : .leftToRight
        if let rich = (NSAttributedString(rtfd: note.richText, documentAttributes: nil) ?? NSAttributedString(rtf: note.richText, documentAttributes: nil)) { editor.textStorage?.setAttributedString(rich) }
        flow.columns = note.columnCount == 2 ? 2 : 1
        scroll.documentView = flow
        primaryEditor.delegate = self; flow.secondary.delegate = self
        populateColors(colors); colors.selectItem(at: note.color); colors.target = self; colors.action = #selector(changeColor)
        let heading = NSPopUpButton(); heading.addItems(withTitles: ["Text", "H1", "H2", "H3"]); heading.target = self; heading.action = #selector(headingChanged(_:))
        let controls = row([heading, button("Font", self, #selector(fontPanel)), button("B", self, #selector(bold)), button("U", self, #selector(underline)), button("•", self, #selector(bullet)), button("←", self, #selector(left)), button("→", self, #selector(right))])
        keepAboveToggle.state = note.keepAbove == true ? .on : .off
        keepAboveToggle.target = self; keepAboveToggle.action = #selector(changeKeepAbove)
        columns.addItems(withTitles: ["1 column", "2 columns"])
        columns.selectItem(at: flow.columns - 1)
        columns.target = self; columns.action = #selector(addColumns(_:))
        let footer = row([colors, button("Image", self, #selector(addImage)), keepAboveToggle])
        let insertControls = row([button("Resize image", self, #selector(resizeImage)), columns])
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
        applyPreferences(); paint(); refreshFlow()
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyPreferences() { window?.level = keepAboveToggle.state == .on ? .floating : .normal; window?.alphaValue = UserDefaults.standard.double(forKey: "opacity"); paint() }
    func paint() {
        let dark = UserDefaults.standard.bool(forKey: "dark")
        let c = dark ? NSColor(calibratedWhite: 0.18, alpha: 1) : palette[colors.indexOfSelectedItem]
        window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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
    @objc func resizeImage() {
        let range = editor.selectedRange()
        guard let original = editor.selectedImage(), original.size.width > 0 else {
            let alert = NSAlert(); alert.messageText = "Select an image first"; alert.informativeText = "Click the image in your note, then choose Resize image."; alert.runModal(); return
        }
        let alert = NSAlert(); alert.messageText = "Image width"; alert.informativeText = "Enter a width from 20 to 2000 points. Proportions are preserved."
        let field = NSTextField(string: String(Int(original.size.width))); field.frame = NSRect(x: 0, y: 0, width: 220, height: 26); alert.accessoryView = field
        alert.addButton(withTitle: "Resize"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let width = Double(field.stringValue), width.isFinite, (20...2000).contains(width) else {
            let error = NSAlert(); error.messageText = "Enter a number between 20 and 2000."; error.runModal(); return
        }
        editor.setSelectedRange(range)
        editor.resizeSelectedImage(to: width); persist()
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
    @objc func fontPanel() { window?.makeFirstResponder(editor); NSFontManager.shared.orderFrontFontPanel(self) }
    @objc func bold() {
        let range = editor.selectedRange()
        let current = (editor.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 17)
        let manager = NSFontManager.shared
        let newFont = manager.traits(of: current).contains(.boldFontMask) ? manager.convert(current, toNotHaveTrait: .boldFontMask) : manager.convert(current, toHaveTrait: .boldFontMask)
        if range.length > 0 { editor.textStorage?.addAttribute(.font, value: newFont, range: range) }
        editor.typingAttributes[.font] = newFont; persist()
    }
    @objc func underline() { editor.underline(self); persist() }
    @objc func left() { editor.alignLeft(self); editor.makeBaseWritingDirectionLeftToRight(self); persist() }
    @objc func right() { editor.alignRight(self); editor.makeBaseWritingDirectionRightToLeft(self); persist() }
    @objc func bullet() { editor.insertText("• ", replacementRange: NSRange(location: (editor.string as NSString).paragraphRange(for: editor.selectedRange()).location, length: 0)) }
    @objc func headingChanged(_ sender: NSPopUpButton) {
        let size: CGFloat = [UserDefaults.standard.double(forKey: "size"), 30, 24, 20][sender.indexOfSelectedItem]
        let font = sender.indexOfSelectedItem == 0 ? NSFont.systemFont(ofSize: size) : NSFont.boldSystemFont(ofSize: size)
        let range = (editor.string as NSString).paragraphRange(for: editor.selectedRange())
        if range.length > 0 { editor.textStorage?.addAttribute(.font, value: font, range: range) }
        editor.typingAttributes[.font] = font; persist()
    }
    func textDidChange(_ notification: Notification) { refreshFlow(); persist() }
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
final class App: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = App()
    var windows: [UUID: NoteWindow] = [:]
    var library: NSWindow!
    let table = NSTableView()
    var visibleNotes: [Note] { Store.shared.notes }
    let darkToggle = NSButton(checkboxWithTitle: "Dark appearance", target: nil, action: nil)
    var settings: NSWindow?
    let rtlToggle = NSButton(checkboxWithTitle: "Right-to-left for new notes", target: nil, action: nil)
    let opacity = NSSlider(value: 1, minValue: 0.25, maxValue: 1, target: nil, action: nil)
    let opacityLabel = NSTextField(labelWithString: "")
    let font = NSPopUpButton()
    let size = NSPopUpButton()
    let color = NSPopUpButton()
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["size": 17.0, "opacity": 1.0, "font": "Helvetica", "color": 0])
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
        library = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false); library.isReleasedWhenClosed = false; library.title = "Sticky Notes — \(appVersion)"; library.center()
        let title = NSTextField(labelWithString: "My Notes"); title.font = .boldSystemFont(ofSize: 28)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note")); table.headerView = nil; table.selectionHighlightStyle = .none; column.width = 560; table.addTableColumn(column); table.rowHeight = 76; table.intercellSpacing = NSSize(width: 0, height: 8); table.delegate = self; table.dataSource = self; table.target = self; table.action = nil; table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let stack = NSStackView(views: [title, row([button("+ New note", self, #selector(newNote)), button("Delete", self, #selector(deleteSelected))]), scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16; layout(stack, in: library.contentView!); scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        library.appearance = NSAppearance(named: UserDefaults.standard.bool(forKey: "dark") ? .darkAqua : .aqua)
        showLibrary(); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showLibrary() { library.makeKeyAndOrderFront(nil); reload() }
    func reload() { table.reloadData() }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleNotes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let n = visibleNotes[row]
        let card = NSView(); card.wantsLayer = true; card.layer?.cornerRadius = 8
        card.layer?.borderWidth = tableView.isRowSelected(row) ? 2 : 0
        card.layer?.borderColor = NSColor.controlAccentColor.cgColor
        card.layer?.backgroundColor = (UserDefaults.standard.bool(forKey: "dark") ? palette[n.color].blended(withFraction: 0.8, of: .black)! : palette[n.color]).cgColor
        let label = NSTextField(labelWithString: "\(n.title)\n\(n.modified.formatted(date: .abbreviated, time: .shortened))")
        label.font = .systemFont(ofSize: 14); label.textColor = UserDefaults.standard.bool(forKey: "dark") ? .white : .black; label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), label.centerYAnchor.constraint(equalTo: card.centerYAnchor)])
        return card
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        for index in 0..<table.numberOfRows {
            if let card = table.view(atColumn: 0, row: index, makeIfNecessary: false) {
                card.layer?.borderWidth = table.isRowSelected(index) ? 2 : 0
                card.layer?.borderColor = NSColor.controlAccentColor.cgColor
            }
        }
    }
    func open(_ n: Note) { if windows[n.id] == nil { windows[n.id] = NoteWindow(note: n) }; windows[n.id]?.showWindow(nil); windows[n.id]?.window?.makeKeyAndOrderFront(nil) }
    @objc func newNote() { var n = Note(); n.color = UserDefaults.standard.integer(forKey: "color"); Store.shared.notes.insert(n, at: 0); Store.shared.save(); reload(); open(n) }
    @objc func openSelected() { guard table.selectedRow >= 0 else { return }; open(visibleNotes[table.selectedRow]) }
    @objc func deleteSelected() {
        guard table.selectedRow >= 0 else { return }; let n = visibleNotes[table.selectedRow]
        let alert = NSAlert(); alert.messageText = "Delete this note?"; alert.informativeText = n.title; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete")
        if alert.runModal() == .alertSecondButtonReturn { windows[n.id]?.close(); windows.removeValue(forKey: n.id); Store.shared.notes.removeAll { $0.id == n.id }; Store.shared.save(); reload() }
    }
    @objc func showSettings() {
        if let settings { settings.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false); w.title = "Settings"; w.isReleasedWhenClosed = false; w.center(); settings = w
        let d = UserDefaults.standard
        darkToggle.state = d.bool(forKey: "dark") ? .on : .off
        rtlToggle.state = d.bool(forKey: "rtl") ? .on : .off
        font.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted()); font.selectItem(withTitle: d.string(forKey: "font")!)
        size.addItems(withTitles: ["12", "14", "17", "20", "24", "28"]); size.selectItem(withTitle: String(Int(d.double(forKey: "size"))))
        populateColors(color); color.selectItem(at: d.integer(forKey: "color")); opacity.doubleValue = d.double(forKey: "opacity")
        for control: NSControl in [darkToggle, rtlToggle, font, size, color, opacity] { control.target = self; control.action = #selector(saveSettings) }
        let hint = NSTextField(wrappingLabelWithString: "Version \(appVersion)\n\nFont, direction and color apply to new notes. Opacity applies to all open notes. Keep note above is set separately on each note. Changes are saved automatically.")
        let stack = NSStackView(views: [darkToggle, row([NSTextField(labelWithString: "Opacity"), opacity, opacityLabel]), row([NSTextField(labelWithString: "Font"), font, size]), row([NSTextField(labelWithString: "New note color"), color]), rtlToggle, hint]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18; layout(stack, in: w.contentView!); saveSettings(); w.makeKeyAndOrderFront(nil)
    }
    @objc func saveSettings() {
        let d = UserDefaults.standard; d.set(darkToggle.state == .on, forKey: "dark"); library.appearance = NSAppearance(named: darkToggle.state == .on ? .darkAqua : .aqua); reload(); d.set(rtlToggle.state == .on, forKey: "rtl"); d.set(opacity.doubleValue, forKey: "opacity"); d.set(font.titleOfSelectedItem, forKey: "font"); d.set(Double(size.titleOfSelectedItem ?? "17")!, forKey: "size"); d.set(color.indexOfSelectedItem, forKey: "color"); opacityLabel.stringValue = "\(Int(opacity.doubleValue * 100))%"; windows.values.forEach { $0.applyPreferences() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showLibrary(); return true }
    func applicationWillTerminate(_ notification: Notification) { windows.values.forEach { $0.persist() } }
}
let app = NSApplication.shared
app.delegate = App.shared
app.run()
