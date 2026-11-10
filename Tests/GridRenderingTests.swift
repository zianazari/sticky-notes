// A reused item must keep exactly one collection-owned view, not strand old cards.
let reuseItem = NoteGridItem()
let stableCard = reuseItem.view as! NoteGridCard
let reuseHost = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))
reuseHost.addSubview(stableCard)
var renderNotes: [Note] = []
for (index, title) in ["My task for today", "• طراحی فرانت"].enumerated() {
    var note = Note(); note.title = title; note.color = index == 0 ? 2 : 4
    let content = NSAttributedString(string: title + (index == 0 ? "\n• task 1\n• task 2\n• task 3\nMy tasks for tomorrow\n• task 1\n• task 2" : "\nمتن فارسی برای بررسی نمایش کارت\n• یادداشت اول\n• یادداشت دوم"))
    note.richText = content.rtfd(from: NSRange(location: 0, length: content.length), documentAttributes: [:])!
    renderNotes.append(note)
}
for index in 0..<20 {
    let note = renderNotes[index % 2]
    reuseItem.isSelected = true
    reuseItem.prepareForReuse()
    assert(!reuseItem.isSelected && !stableCard.selected && stableCard.clicked == nil)
    reuseItem.configure(note, clicked: { _ in }, contextMenu: { nil })
    assert(reuseItem.view === stableCard && stableCard.superview === reuseHost)
    assert(reuseHost.subviews.count == 1 && stableCard.subviews.count == 3)
    assert(stableCard.title.stringValue == note.title)
    assert(!stableCard.selected && stableCard.layer!.masksToBounds)
    stableCard.setFrameSize(NSSize(width: [200.0, 280.0, 220.0, 320.0][index % 4], height: 180))
    reuseHost.layoutSubtreeIfNeeded(); stableCard.layoutSubtreeIfNeeded()
    for label in [stableCard.title, stableCard.preview, stableCard.date] {
        assert(stableCard.bounds.contains(label.frame), "Text escaped its card after resize")
    }
}
// Repeated collection reloads/resizing must not leave more than one selected card.
Store.shared.notes = renderNotes
let renderLibrary = LibraryController(); _ = renderLibrary.view
let renderWindow = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 960, height: 610), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
renderWindow.isReleasedWhenClosed = false; renderWindow.contentViewController = renderLibrary
renderLibrary.setDisplayMode(.grid)
for index in 0..<10 {
    renderWindow.setContentSize(NSSize(width: index % 2 == 0 ? 720 : 1100, height: 610))
    renderLibrary.reload(); renderLibrary.view.layoutSubtreeIfNeeded()
    renderLibrary.notesGrid.layoutSubtreeIfNeeded()
    renderLibrary.notesTable.selectRowIndexes(IndexSet(integer: index % 2), byExtendingSelection: false)
    renderLibrary.updateSelection()
    assert(renderLibrary.notesGrid.visibleItems().count == 2)
    for item in renderLibrary.notesGrid.visibleItems() {
        let card = item.view as! NoteGridCard
        let selected = renderLibrary.notesGrid.indexPath(for: item)!.item == index % 2
        assert(card.selected == selected && item.isSelected == selected)
        assert(card.subviews.count == 3)
    }
}
// Render real AppKit cards for visual inspection after reuse and selection changes.
let previewHost = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 410))
previewHost.wantsLayer = true
for index in 0..<4 {
    let item = NoteGridItem()
    item.configure(renderNotes[index % 2], clicked: { _ in }, contextMenu: { nil })
    let card = item.view as! NoteGridCard
    card.frame = NSRect(x: 10 + (index % 2) * 285, y: 10 + (index / 2) * 200, width: 275, height: 190)
    card.selected = true; card.selected = index == 0
    previewHost.addSubview(card)
}
previewHost.layoutSubtreeIfNeeded()
if let bitmap = previewHost.bitmapImageRepForCachingDisplay(in: previewHost.bounds) {
    previewHost.cacheDisplay(in: previewHost.bounds, to: bitmap)
    if let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/grid-rendering-preview.png"))
    }
}
renderLibrary.setDisplayMode(.list); renderWindow.close()
print("PASS: stable card identity; no duplicated views; clipped content during resize; clean reuse and selection state")
