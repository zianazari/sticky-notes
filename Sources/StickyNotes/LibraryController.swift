import AppKit
import QuartzCore

enum GroupFilter: Equatable {
    case all, ungrouped, group(UUID)
}

final class LibrarySurface: NSView {
    var fill: NSColor = .windowBackgroundColor { didSet { needsDisplay = true } }
    var isSidebar = false
    override func draw(_ dirtyRect: NSRect) {
        if isSidebar {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSColor(calibratedWhite: dark ? 0.13 : 0.94, alpha: 1).setFill(); bounds.fill()
            NSColor.separatorColor.setFill()
            NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        } else { fill.setFill(); bounds.fill() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

class NoteCard: NSView {
    let title = NSTextField(labelWithString: "")
    let preview = NSTextField(labelWithString: "")
    let date = NSTextField(labelWithString: "")
    var tint: NSColor = .yellow
    var selected = false { didSet { needsDisplay = true } }
    init(note: Note, grid: Bool = false) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.masksToBounds = true
        layerContentsRedrawPolicy = .duringViewResize
        update(note)
        for field in [title, preview, date] { field.lineBreakMode = .byTruncatingTail; field.maximumNumberOfLines = 1; field.translatesAutoresizingMaskIntoConstraints = false; addSubview(field) }
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        if grid {
            title.maximumNumberOfLines = 2
            preview.maximumNumberOfLines = 5; preview.lineBreakMode = .byWordWrapping
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22), title.topAnchor.constraint(equalTo: topAnchor, constant: 16),
                title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                preview.leadingAnchor.constraint(equalTo: title.leadingAnchor), preview.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
                preview.trailingAnchor.constraint(equalTo: title.trailingAnchor), preview.bottomAnchor.constraint(lessThanOrEqualTo: date.topAnchor, constant: -10),
                date.leadingAnchor.constraint(equalTo: title.leadingAnchor), date.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
                date.trailingAnchor.constraint(lessThanOrEqualTo: title.trailingAnchor)
            ])
        } else {
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22), title.topAnchor.constraint(equalTo: topAnchor, constant: 17),
            title.trailingAnchor.constraint(lessThanOrEqualTo: date.leadingAnchor, constant: -16),
            preview.leadingAnchor.constraint(equalTo: title.leadingAnchor), preview.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            preview.trailingAnchor.constraint(lessThanOrEqualTo: date.leadingAnchor, constant: -16),
            date.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18), date.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        }
    }
    func update(_ note: Note) {
        tint = palette[min(max(note.color, 0), palette.count - 1)]
        title.stringValue = note.title; title.font = .systemFont(ofSize: 15, weight: .semibold)
        let text = note.richText.isEmpty ? "" : (NSAttributedString(rtfd: note.richText, documentAttributes: nil)?.string ?? NSAttributedString(rtf: note.richText, documentAttributes: nil)?.string ?? "")
        let lines = text.replacingOccurrences(of: "\u{fffc}", with: "Image").replacingOccurrences(of: "\u{000c}", with: "\n").split(separator: "\n").map(String.init)
        preview.stringValue = lines.dropFirst().joined(separator: "  ")
        if preview.stringValue.isEmpty { preview.stringValue = text.contains("\u{fffc}") ? "Image" : "" }
        preview.font = .systemFont(ofSize: 12); preview.textColor = .secondaryLabelColor
        let formatter = DateFormatter(); formatter.doesRelativeDateFormatting = true
        if Calendar.current.isDateInToday(note.modified) { formatter.dateStyle = .none; formatter.timeStyle = .short }
        else { formatter.dateStyle = .short; formatter.timeStyle = .none }
        date.stringValue = formatter.string(from: note.modified); date.font = .systemFont(ofSize: 12); date.textColor = .secondaryLabelColor
        setAccessibilityLabel(note.title)
        needsDisplay = true
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        // Clear the previous layer contents, including old selection outlines.
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 3), xRadius: 11, yRadius: 11)
        (tint.blended(withFraction: dark ? 0.77 : 0.58, of: dark ? .black : .white) ?? tint).setFill(); card.fill()
        tint.blended(withFraction: 0.18, of: .gray)?.setFill()
        NSBezierPath(roundedRect: NSRect(x: 10, y: 14, width: 4, height: bounds.height - 28), xRadius: 2, yRadius: 2).fill()
        if selected { NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke(); card.lineWidth = 1.3; card.stroke() }
    }
}

// Keep the single column inside the visible area, including after sidebar toggles.
final class LibraryScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let table = documentView as? NSTableView, let column = table.tableColumns.first else { return }
        let width = max(1, contentView.bounds.width)
        if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        if abs(column.width - width) > 0.5 { column.width = width }
    }
}

final class GroupCell: NSView {
    let nameField = NSTextField(labelWithString: "")
    let countField = NSTextField(labelWithString: "")
    let folderImage = NSImageView()
    private var hoverTracking: NSTrackingArea?
    var actionsButton: NSButton? { didSet { updateStyle() } }
    var hovered = false { didSet { updateStyle() } }
    var selected = false { didSet { updateStyle() } }
    func updateStyle() {
        actionsButton?.isHidden = !hovered
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = dark ? NSColor.systemYellow : NSColor(calibratedRed: 0.68, green: 0.43, blue: 0, alpha: 1)
        nameField.textColor = selected ? accent : .labelColor
        nameField.font = .systemFont(ofSize: 16, weight: selected ? .medium : .regular)
        folderImage.contentTintColor = selected ? accent : .labelColor
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverTracking = area
        if let window { hovered = window.isKeyWindow && bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateStyle() }
    override func draw(_ dirtyRect: NSRect) {
        if selected {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.055)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 9, yRadius: 9).fill()
        }
    }
}

enum LibraryDisplayMode: String { case list, grid }

// Handle clicks on the whole card, including its text labels. Collection-view
// item subviews do not reliably forward double-clicks to the collection itself.
final class NoteGridCard: NoteCard {
    var clicked: ((Int) -> Void)?
    var contextMenu: (() -> NSMenu?)?
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { clicked?(event.clickCount) }
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu?() }
}

final class NoteGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("NoteGridItem")
    override func loadView() { view = NoteGridCard(note: Note(), grid: true) }
    override var isSelected: Bool { didSet { (view as? NoteCard)?.selected = isSelected } }
    override func prepareForReuse() {
        super.prepareForReuse()
        isSelected = false
        let card = view as! NoteGridCard
        card.clicked = nil; card.contextMenu = nil
    }
    func configure(_ note: Note, clicked: @escaping (Int) -> Void, contextMenu: @escaping () -> NSMenu?) {
        // Keep the collection-owned root view stable across reloads and reuse.
        // Replacing it leaves the old card attached with stale geometry/content.
        let card = view as! NoteGridCard
        card.update(note)
        card.clicked = clicked; card.contextMenu = contextMenu
        card.selected = isSelected
    }
}

final class NoteGridLayout: NSCollectionViewFlowLayout {
    func updateItemSize(for width: CGFloat) {
        guard width > 1 else { return }
        let columns = max(1, Int((width + 12) / 212))
        let size = NSSize(width: floor((width - CGFloat(columns - 1) * 12) / CGFloat(columns)), height: 180)
        if itemSize != size { itemSize = size; invalidateLayout() }
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != collectionView?.bounds.width || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
}

final class NoteGridScrollView: NSScrollView {
    private var isTilingGrid = false
    override func tile() {
        guard !isTilingGrid else { return }
        isTilingGrid = true; defer { isTilingGrid = false }
        super.tile()
        guard let collection = documentView as? NoteGridView, contentView.bounds.width > 1 else { return }
        let width = contentView.bounds.width
        (collection.collectionViewLayout as? NoteGridLayout)?.updateItemSize(for: width)
        if collection.frame.width != width {
            collection.setFrameSize(NSSize(width: width, height: collection.frame.height))
        }
    }
}

final class NoteGridView: NSCollectionView {
    override func setFrameSize(_ newSize: NSSize) {
        // Set item dimensions before AppKit caches layout attributes for this width.
        (collectionViewLayout as? NoteGridLayout)?.updateItemSize(for: newSize.width)
        super.setFrameSize(newSize)
    }
    var openItem: ((IndexPath) -> Void)?
    var itemMenu: ((IndexPath) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        return itemMenu?(index)
    }
}

final class LibraryController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSTextFieldDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let notesTable = NSTableView()
    let groupsTable = NSTableView()
    let notesGrid = NoteGridView()
    let gridLayout = NoteGridLayout()
    let gridScroll = NoteGridScrollView()
    var listScroll: NSScrollView!
    let viewPicker = NSSegmentedControl()
    var displayMode: LibraryDisplayMode = .list
    private var syncingSelection = false
    let heading = NSTextField(labelWithString: "My Notes")
    let countLabel = NSTextField(labelWithString: "0 notes")
    let emptyLabel = NSTextField(labelWithString: "No notes yet")
    let sidebar = LibrarySurface()
    let main = LibrarySurface()
    let restoreSidebar = NSButton()
    var sidebarWidth: NSLayoutConstraint!
    var mainWithSidebar: NSLayoutConstraint!
    var sidebarLeading: NSLayoutConstraint!
    var isSidebarAnimating = false
    private var sidebarTimer: Timer?
    let sidebarAnimationDuration: TimeInterval = 0.48
    deinit { sidebarTimer?.invalidate() }
    var filter: GroupFilter = .all
    var filters: [GroupFilter] = [.all, .ungrouped]
    var notes: [Note] = []
    var editingGroupID: UUID?
    weak var editingField: NSTextField?
    var isReloading = false
    var isSidebarVisible = true
    var currentGroupID: UUID? { if case .group(let id) = filter { return id }; return nil }
    var selectedNote: Note? { notes.indices.contains(notesTable.selectedRow) ? notes[notesTable.selectedRow] : nil }
    private func icon(_ symbol: String, label: String, action: Selector) -> NSButton {
        let control = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        control.isBordered = false; control.toolTip = label; control.setAccessibilityLabel(label)
        control.imageScaling = .scaleProportionallyDown
        control.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        control.widthAnchor.constraint(equalToConstant: 26).isActive = true
        control.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return control
    }
    override func loadView() {
        view = LibrarySurface(frame: NSRect(x: 0, y: 0, width: 960, height: 610))
        for panel in [sidebar, main] { panel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(panel) }
        view.wantsLayer = true; view.layer?.masksToBounds = true
        sidebar.isSidebar = true; main.fill = .textBackgroundColor
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 260)
        mainWithSidebar = main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor)
        sidebarLeading = sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        NSLayoutConstraint.activate([sidebarLeading, sidebar.topAnchor.constraint(equalTo: view.topAnchor), sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor), sidebarWidth,
            mainWithSidebar, main.topAnchor.constraint(equalTo: view.topAnchor), main.trailingAnchor.constraint(equalTo: view.trailingAnchor), main.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        let groupTitle = NSTextField(labelWithString: "Groups"); groupTitle.font = .systemFont(ofSize: 13, weight: .semibold); groupTitle.textColor = .secondaryLabelColor
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let groupHeader = row([spacer, icon("folder.badge.plus", label: "New group", action: #selector(newGroup)), icon("sidebar.left", label: "Toggle sidebar", action: #selector(toggleSidebar))])
        groupHeader.spacing = 6
        let groupScroll = setupTable(groupsTable, rowHeight: 40)
        groupsTable.action = #selector(groupClicked); groupsTable.target = self
        let context = NSMenu(); context.delegate = self; groupsTable.menu = context
        let groupStack = NSStackView(views: [groupHeader, groupTitle, groupScroll]); groupStack.orientation = .vertical; groupStack.alignment = .leading; groupStack.spacing = 6
        layout(groupStack, in: sidebar, topInset: 6)
        groupHeader.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true
        groupScroll.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true
        heading.font = .systemFont(ofSize: 27, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 13); countLabel.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [heading, countLabel]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 5
        restoreSidebar.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Show sidebar")
        restoreSidebar.isBordered = false; restoreSidebar.target = self; restoreSidebar.action = #selector(toggleSidebar); restoreSidebar.toolTip = "Show sidebar"
        restoreSidebar.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        restoreSidebar.widthAnchor.constraint(equalToConstant: 26).isActive = true
        restoreSidebar.isHidden = true
        let newNote = button("New note", App.shared, #selector(App.newNote))
        newNote.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        newNote.imagePosition = .imageLeading
        newNote.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        viewPicker.segmentCount = 2; viewPicker.trackingMode = .selectOne
        for (index, symbol) in ["list.bullet", "square.grid.2x2"].enumerated() {
            let label = index == 0 ? "List view" : "Grid view"
            viewPicker.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: index)
            viewPicker.setToolTip(label, forSegment: index); viewPicker.setWidth(32, forSegment: index)
        }
        viewPicker.setAccessibilityLabel("Notes view")
        viewPicker.target = self; viewPicker.action = #selector(changeDisplayMode(_:))
        heading.lineBreakMode = .byTruncatingTail
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let flexible = NSView()
        let header = row([restoreSidebar, titles, flexible, viewPicker, newNote]); header.spacing = 12; header.detachesHiddenViews = true
        let noteScroll = setupTable(notesTable, rowHeight: 80)
        listScroll = noteScroll
        configureGrid()
        notesTable.doubleAction = #selector(openNote); notesTable.target = self
        notesTable.action = nil
        let noteContext = NSMenu(); noteContext.delegate = self; notesTable.menu = noteContext
        let noteArea = NSView()
        for scroll in [noteScroll, gridScroll] {
            scroll.translatesAutoresizingMaskIntoConstraints = false; noteArea.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: noteArea.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: noteArea.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: noteArea.topAnchor), scroll.bottomAnchor.constraint(equalTo: noteArea.bottomAnchor)
            ])
        }
        emptyLabel.font = .systemFont(ofSize: 15); emptyLabel.textColor = .secondaryLabelColor; emptyLabel.translatesAutoresizingMaskIntoConstraints = false; noteArea.addSubview(emptyLabel)
        NSLayoutConstraint.activate([noteScroll.leadingAnchor.constraint(equalTo: noteArea.leadingAnchor), noteScroll.trailingAnchor.constraint(equalTo: noteArea.trailingAnchor), noteScroll.topAnchor.constraint(equalTo: noteArea.topAnchor), noteScroll.bottomAnchor.constraint(equalTo: noteArea.bottomAnchor), emptyLabel.centerXAnchor.constraint(equalTo: noteArea.centerXAnchor), emptyLabel.centerYAnchor.constraint(equalTo: noteArea.centerYAnchor)])
        let stack = NSStackView(views: [header, noteArea]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 22
        layout(stack, in: main)
        for item in [header, noteArea] { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        noteArea.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        isSidebarVisible = !UserDefaults.standard.bool(forKey: "librarySidebarHidden")
        applySidebarVisibility()
        setDisplayMode(LibraryDisplayMode(rawValue: UserDefaults.standard.string(forKey: "libraryDisplayMode") ?? "") ?? .list)
        reload()
    }
    private func configureGrid() {
        gridLayout.minimumInteritemSpacing = 12; gridLayout.minimumLineSpacing = 12
        gridLayout.itemSize = NSSize(width: 200, height: 180)
        notesGrid.collectionViewLayout = gridLayout
        notesGrid.isSelectable = true; notesGrid.allowsMultipleSelection = false
        notesGrid.backgroundColors = [.clear]
        notesGrid.autoresizingMask = [.width]
        notesGrid.register(NoteGridItem.self, forItemWithIdentifier: NoteGridItem.identifier)
        notesGrid.dataSource = self; notesGrid.delegate = self
        notesGrid.openItem = { [weak self] index in
            guard let self, self.notes.indices.contains(index.item) else { return }
            App.shared.open(self.notes[index.item])
        }
        notesGrid.itemMenu = { [weak self] index in
            guard let self, self.notes.indices.contains(index.item) else { return nil }
            self.notesTable.selectRowIndexes(IndexSet(integer: index.item), byExtendingSelection: false)
            self.updateSelection()
            return self.noteMenu(for: self.notes[index.item])
        }
        gridScroll.documentView = notesGrid
        gridScroll.hasVerticalScroller = true; gridScroll.hasHorizontalScroller = false
        gridScroll.autohidesScrollers = true; gridScroll.drawsBackground = false
    }
    override func viewDidLayout() { super.viewDidLayout(); updateGridLayout() }
    func updateGridLayout() {
        guard isViewLoaded else { return }
        gridLayout.updateItemSize(for: gridScroll.contentView.bounds.width)
    }
    @objc func changeDisplayMode(_ sender: NSSegmentedControl) {
        setDisplayMode(sender.selectedSegment == 1 ? .grid : .list)
    }
    func setDisplayMode(_ mode: LibraryDisplayMode) {
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "libraryDisplayMode")
        guard isViewLoaded else { return }
        viewPicker.selectedSegment = mode == .grid ? 1 : 0
        listScroll.isHidden = mode == .grid; gridScroll.isHidden = mode == .list
        updateSelection(); view.layoutSubtreeIfNeeded(); updateGridLayout()
        if let row = notes.indices.contains(notesTable.selectedRow) ? notesTable.selectedRow : nil {
            if mode == .grid { notesGrid.scrollToItems(at: [IndexPath(item: row, section: 0)], scrollPosition: .nearestVerticalEdge) }
            else { notesTable.scrollRowToVisible(row) }
        }
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { notes.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NoteGridItem.identifier, for: indexPath) as! NoteGridItem
        let id = notes[indexPath.item].id
        item.configure(notes[indexPath.item], clicked: { [weak self] clicks in
            guard let self, let index = self.notes.firstIndex(where: { $0.id == id }) else { return }
            self.view.window?.makeFirstResponder(self.notesGrid)
            self.notesTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            self.updateSelection()
            if clicks == 2 { self.notesGrid.openItem?(IndexPath(item: index, section: 0)) }
        }, contextMenu: { [weak self] in
            guard let self, let index = self.notes.firstIndex(where: { $0.id == id }) else { return nil }
            return self.notesGrid.itemMenu?(IndexPath(item: index, section: 0))
        })
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { syncGridSelection() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { syncGridSelection() }
    private func syncGridSelection() {
        guard !isReloading, !syncingSelection else { return }
        if let index = notesGrid.selectionIndexPaths.first, notes.indices.contains(index.item) {
            notesTable.selectRowIndexes(IndexSet(integer: index.item), byExtendingSelection: false)
        } else { notesTable.deselectAll(nil) }
        updateSelection()
    }
    private func setupTable(_ table: NSTableView, rowHeight: CGFloat) -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")); column.resizingMask = .autoresizingMask; column.minWidth = 0; column.width = 1; table.addTableColumn(column)
        table.autoresizingMask = [.width]; table.style = .plain
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.headerView = nil; table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 3); table.selectionHighlightStyle = .none; table.backgroundColor = .clear
        table.delegate = self; table.dataSource = self; table.allowsEmptySelection = true; table.focusRingType = .none
        let scroll = LibraryScrollView(); scroll.documentView = table; scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        return scroll
    }
    func selectAllNotes() { filter = .all; if isViewLoaded { reload() } }
    func reload() {
        guard isViewLoaded, editingGroupID == nil else { return }
        let selectedID = selectedNote?.id
        if case .group(let id) = filter, !Store.shared.groups.contains(where: { $0.id == id }) { filter = .all }
        isReloading = true
        filters = [.all, .ungrouped] + Store.shared.groups.map { .group($0.id) }
        notes = Store.shared.notes.filter { matches($0, filter: filter) }
        heading.stringValue = filter == .all ? "My Notes" : name(for: filter)
        countLabel.stringValue = "\(notes.count) \(notes.count == 1 ? "note" : "notes")"
        notesTable.reloadData(); notesGrid.reloadData(); groupsTable.reloadData()
        if let id = selectedID, let index = notes.firstIndex(where: { $0.id == id }) { notesTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else { notesTable.deselectAll(nil) }
        if let index = filters.firstIndex(of: filter) { groupsTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        emptyLabel.isHidden = !notes.isEmpty
        emptyLabel.stringValue = filter == .all ? "Create your first note" : "No notes in this group"
        isReloading = false; updateSelection()
    }
    func matches(_ note: Note, filter: GroupFilter) -> Bool {
        switch filter {
        case .all: return true
        case .ungrouped: return Store.shared.resolvedGroupID(for: note) == nil
        case .group(let id): return Store.shared.resolvedGroupID(for: note) == id
        }
    }
    func name(for filter: GroupFilter) -> String {
        switch filter {
        case .all: return "All Notes"
        case .ungrouped: return "Ungrouped"
        case .group(let id): return Store.shared.groups.first(where: { $0.id == id })?.name ?? "Group"
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === notesTable ? notes.count : filters.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === notesTable { let card = NoteCard(note: notes[row]); card.selected = tableView.isRowSelected(row); return card }
        let item = filters[row]
        let cell = GroupCell(); cell.selected = item == filter
        let image = cell.folderImage
        image.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)!
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.widthAnchor.constraint(equalToConstant: 24).isActive = true
        image.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let label = cell.nameField
        label.stringValue = name(for: item); label.font = .systemFont(ofSize: 16)
        label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let total = Store.shared.notes.filter { matches($0, filter: item) }.count
        let count = cell.countField
        count.stringValue = "\(total)"; count.textColor = .secondaryLabelColor; count.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        count.alignment = .right
        count.setAccessibilityLabel("\(total) notes")
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.widthAnchor.constraint(equalToConstant: max(38, (String(Store.shared.notes.count) as NSString).size(withAttributes: [.font: count.font!]).width + 4)).isActive = true
        var views: [NSView] = [image, label, count]
        if case .group(let id) = item {
            label.identifier = NSUserInterfaceItemIdentifier(id.uuidString); label.delegate = self
            let more = icon("ellipsis", label: "Actions for \(name(for: item))", action: #selector(groupActions(_:)))
            more.contentTintColor = .labelColor
            more.identifier = NSUserInterfaceItemIdentifier(id.uuidString); views.append(more)
            cell.actionsButton = more
        }
        for item in views { item.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(item); item.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
            count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10)
        ])
        if let more = cell.actionsButton {
            more.trailingAnchor.constraint(equalTo: count.leadingAnchor, constant: -4).isActive = true
            label.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -4).isActive = true
        } else { label.trailingAnchor.constraint(equalTo: count.leadingAnchor, constant: -8).isActive = true }
        cell.updateStyle()
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading else { return }
        if notification.object as? NSTableView === groupsTable {
            guard filters.indices.contains(groupsTable.selectedRow) else { return }
            filter = filters[groupsTable.selectedRow]; reload()
        } else { updateSelection() }
    }
    func updateSelection() {
        guard !syncingSelection else { return }
        syncingSelection = true; defer { syncingSelection = false }
        let indexes: Set<IndexPath> = selectedNote == nil ? [] : [IndexPath(item: notesTable.selectedRow, section: 0)]
        if notesGrid.selectionIndexPaths != indexes { notesGrid.selectionIndexPaths = indexes }
        for item in notesGrid.visibleItems() {
            item.isSelected = notesGrid.indexPath(for: item).map { indexes.contains($0) } ?? false
        }
        for index in 0..<notesTable.numberOfRows { (notesTable.view(atColumn: 0, row: index, makeIfNecessary: false) as? NoteCard)?.selected = notesTable.isRowSelected(index) }
        for index in 0..<groupsTable.numberOfRows { (groupsTable.view(atColumn: 0, row: index, makeIfNecessary: false) as? GroupCell)?.selected = groupsTable.isRowSelected(index) }
    }
    @objc func groupClicked() { /* Selection delegate handles mouse and keyboard navigation. */ }
    @objc func openNote() { guard notesTable.clickedRow >= 0, let note = selectedNote else { return }; App.shared.open(note) }
    @objc func toggleSidebar() {
        guard !isSidebarAnimating else { return }
        finishGroupEditing()
        isSidebarVisible.toggle()
        UserDefaults.standard.set(!isSidebarVisible, forKey: "librarySidebarHidden")
        applySidebarVisibility(animated: true)
    }
    func applySidebarVisibility(animated: Bool = false) {
        sidebarTimer?.invalidate(); sidebarTimer = nil
        isSidebarAnimating = false
        view.layoutSubtreeIfNeeded()
        sidebar.isHidden = false
        restoreSidebar.isHidden = isSidebarVisible
        let target: CGFloat = isSidebarVisible ? 0 : -sidebarWidth.constant
        if animated && view.window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animateSidebar(to: target)
        } else {
            sidebarLeading.constant = target
            view.layoutSubtreeIfNeeded()
            sidebar.isHidden = !isSidebarVisible
        }
    }
    // Animate the layout itself so opening and closing follow the same path.
    func animateSidebar(to target: CGFloat) {
        sidebarTimer?.invalidate()
        sidebar.isHidden = false
        let start = sidebarLeading.constant
        let startedAt = CACurrentMediaTime()
        isSidebarAnimating = true
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (CACurrentMediaTime() - startedAt) / self.sidebarAnimationDuration)
            let eased = progress * progress * (3 - 2 * progress)
            self.sidebarLeading.constant = start + (target - start) * eased
            self.view.layoutSubtreeIfNeeded()
            if progress >= 1 {
                timer.invalidate(); self.sidebarTimer = nil
                self.sidebar.isHidden = !self.isSidebarVisible
                self.isSidebarAnimating = false
            }
        }
        sidebarTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    @objc func newGroup() {
        finishGroupEditing()
        var name = "New Group"
        var suffix = 2
        while Store.shared.validName(name) == nil { name = "New Group \(suffix)"; suffix += 1 }
        guard let group = Store.shared.createGroup(name: name) else { return }
        Store.shared.save()
        beginGroupEditing(group.id)
    }
    func beginGroupEditing(_ id: UUID) {
        finishGroupEditing()
        filter = .group(id)
        if !isSidebarVisible { toggleSidebar() }
        reload()
        guard let row = filters.firstIndex(of: .group(id)) else { return }
        groupsTable.scrollRowToVisible(row)
        view.layoutSubtreeIfNeeded()
        guard let cell = groupsTable.view(atColumn: 0, row: row, makeIfNecessary: true) as? GroupCell else { return }
        let field = cell.nameField
        editingGroupID = id; editingField = field
        field.isEditable = true; field.isSelectable = true
        field.isBezeled = true; field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.lineBreakMode = .byClipping
        field.selectText(nil)
    }
    func finishGroupEditing(cancel: Bool = false) {
        guard let id = editingGroupID else { return }
        let name = editingField?.stringValue ?? ""
        editingGroupID = nil
        let field = editingField; editingField = nil
        field?.isEditable = false; field?.isSelectable = false
        if !cancel, Store.shared.renameGroup(id: id, name: name) { Store.shared.save() }
        reload()
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === editingField else { return }
        finishGroupEditing()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === editingField else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishGroupEditing(cancel: true); view.window?.makeFirstResponder(groupsTable); return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard Store.shared.validName(textView.string, excluding: editingGroupID) != nil else {
                editingField?.toolTip = "Use a unique name with 1–80 characters."
                NSSound.beep(); return true
            }
            editingField?.stringValue = textView.string
            finishGroupEditing(); view.window?.makeFirstResponder(groupsTable); return true
        }
        return false
    }
    func groupMenu(id: UUID?) -> NSMenu {
        let menu = NSMenu()
        if let id {
            for (title, action, symbol) in [("Rename group…", #selector(renameGroup(_:)), "pencil"), ("Delete group…", #selector(deleteGroup(_:)), "trash")] {
                let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self; item.representedObject = id.uuidString; item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menu.addItem(.separator())
        }
        let item = menu.addItem(withTitle: "New group…", action: #selector(newGroup), keyEquivalent: ""); item.target = self; item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
        return menu
    }
    @objc func groupActions(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let id = UUID(uuidString: value) else { return }
        groupMenu(id: id).popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === notesTable.menu {
            let row = notesTable.clickedRow
            menu.removeAllItems()
            guard notes.indices.contains(row) else { return }
            let note = notes[row]
            notesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            for item in noteMenu(for: note).items { menu.addItem(item.copy() as! NSMenuItem) }
            return
        }
        let row = groupsTable.clickedRow
        let id: UUID? = filters.indices.contains(row) ? { if case .group(let id) = filters[row] { return id }; return nil }() : nil
        menu.removeAllItems()
        for item in groupMenu(id: id).items { menu.addItem(item.copy() as! NSMenuItem) }
    }
    @objc func renameGroup(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value), Store.shared.groups.contains(where: { $0.id == id }) else { return }
        beginGroupEditing(id)
    }
    @objc func deleteGroup(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value), let group = Store.shared.groups.first(where: { $0.id == id }) else { return }
        if Store.shared.notes.contains(where: { $0.groupID == id }) {
            let alert = NSAlert(); alert.messageText = "Delete “\(group.name)”?"; alert.informativeText = "Its notes will be moved to Ungrouped. No notes will be deleted."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete group")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        Store.shared.removeGroup(id: id); Store.shared.save()
        if filter == .group(id) { filter = .ungrouped }; reload()
    }
    func noteMenu(for note: Note) -> NSMenu {
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Note in New Window", action: #selector(openContextNote(_:)), keyEquivalent: "")
        open.target = self; open.representedObject = note.id.uuidString
        open.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(.separator())
        let new = menu.addItem(withTitle: "New Note", action: #selector(App.newNote), keyEquivalent: "")
        new.target = App.shared; new.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        menu.addItem(.separator())
        let move = menu.addItem(withTitle: "Move to", action: nil, keyEquivalent: "")
        move.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        move.submenu = moveMenu(for: note)
        let delete = menu.addItem(withTitle: "Delete", action: #selector(deleteContextNote(_:)), keyEquivalent: "")
        delete.target = self; delete.representedObject = note.id.uuidString
        delete.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        return menu
    }
    @objc func openContextNote(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value), let note = Store.shared.notes.first(where: { $0.id == id }) else { return }
        App.shared.open(note)
    }
    @objc func deleteContextNote(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        App.shared.deleteNote(id: id)
    }
    func moveMenu(for note: Note) -> NSMenu {
        let menu = NSMenu()
        let destinations: [(String, UUID?)] = [("Ungrouped", nil)] + Store.shared.groups.map { ($0.name, Optional($0.id)) }
        for (name, id) in destinations {
            let item = menu.addItem(withTitle: name, action: #selector(moveNote(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = ["note": note.id.uuidString, "group": id?.uuidString ?? ""]
            item.state = Store.shared.resolvedGroupID(for: note) == id ? .on : .off
        }
        if Store.shared.groups.isEmpty { menu.addItem(.separator()); let item = menu.addItem(withTitle: "New group…", action: #selector(newGroup), keyEquivalent: ""); item.target = self }
        return menu
    }
    @objc func moveNote(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [String: String], let noteID = UUID(uuidString: values["note"] ?? "") else { return }
        let groupID = UUID(uuidString: values["group"] ?? "")
        if Store.shared.moveNote(id: noteID, to: groupID) { Store.shared.save(); reload() }
    }
}
