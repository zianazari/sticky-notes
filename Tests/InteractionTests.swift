// Route real mouse events through the card and its label hit areas.
var interactionNote = Note(); interactionNote.title = "Open this card"
let interactionText = NSAttributedString(string: "Open this card\nPreview text")
interactionNote.richText = interactionText.rtfd(from: NSRange(location: 0, length: interactionText.length), documentAttributes: [:])!
Store.shared.notes = [interactionNote]; Store.shared.groups = []
let interactionLibrary = LibraryController(); _ = interactionLibrary.view
interactionLibrary.setDisplayMode(.grid)
var openedIndexes: [IndexPath] = []
interactionLibrary.notesGrid.openItem = { openedIndexes.append($0) }
let interactionItem = interactionLibrary.collectionView(interactionLibrary.notesGrid, itemForRepresentedObjectAt: IndexPath(item: 0, section: 0)) as! NoteGridItem
let interactionCard = interactionItem.view as! NoteGridCard
let clickHost = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 210))
clickHost.addSubview(interactionCard)
interactionCard.frame = NSRect(x: 10, y: 10, width: 240, height: 180)
interactionCard.layoutSubtreeIfNeeded()
func cardMouseEvent(at point: NSPoint, clicks: Int) -> NSEvent {
    NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
}
for label in [interactionCard.title, interactionCard.preview, interactionCard.date] {
    let point = label.convert(NSPoint(x: label.bounds.midX, y: label.bounds.midY), to: clickHost)
    let hit = clickHost.hitTest(point)
    assert(hit === interactionCard, "Text labels must not swallow card clicks")
    let before = openedIndexes.count
    hit!.mouseDown(with: cardMouseEvent(at: point, clicks: 1))
    assert(openedIndexes.count == before && interactionLibrary.selectedNote!.id == interactionNote.id)
    hit!.mouseDown(with: cardMouseEvent(at: point, clicks: 2))
    assert(openedIndexes.count == before + 1 && openedIndexes.last! == IndexPath(item: 0, section: 0))
}
let blankCardPoint = NSPoint(x: interactionCard.frame.midX, y: interactionCard.frame.maxY - 5)
clickHost.hitTest(blankCardPoint)!.mouseDown(with: cardMouseEvent(at: blankCardPoint, clicks: 2))
assert(openedIndexes.count == 4)
let cardContext = interactionCard.menu(for: cardMouseEvent(at: blankCardPoint, clicks: 1))!
assert(cardContext.item(withTitle: "Delete")!.representedObject as? String == interactionNote.id.uuidString)
Store.shared.notes.removeAll(); interactionLibrary.reload()
interactionCard.mouseDown(with: cardMouseEvent(at: blankCardPoint, clicks: 2))
assert(openedIndexes.count == 4) // A stale card must never open a different note.

// Appearance choice applies to existing and new windows; System clears the override.
Store.shared.notes = [interactionNote]
let themeWindow = NoteWindow(note: interactionNote)
let themeLibraryWindow = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 960, height: 610), styleMask: [.titled], backing: .buffered, defer: false)
themeLibraryWindow.isReleasedWhenClosed = false; themeLibraryWindow.contentViewController = interactionLibrary
App.shared.library = themeLibraryWindow
App.shared.windows[interactionNote.id] = themeWindow
App.shared.configureAppearancePicker()
assert(App.shared.appearancePicker.itemTitles == ["System", "Light", "Dark"])
for mode in [AppAppearanceMode.dark, .light, .system] {
    App.shared.appearancePicker.selectItem(withTitle: mode.title)
    App.shared.appearanceChanged(App.shared.appearancePicker)
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    assert(AppAppearanceMode.current == mode)
    assert(UserDefaults.standard.string(forKey: "appearanceMode") == mode.rawValue)
    if mode == .system { assert(NSApp.appearance == nil && themeWindow.window!.appearance == nil && themeLibraryWindow.appearance == nil) }
    else {
        let expected: NSAppearance.Name = mode == .dark ? .darkAqua : .aqua
        assert(NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
        assert(themeLibraryWindow.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
        assert(themeWindow.window!.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
        assert(themeWindow.window!.backgroundColor == (mode == .dark ? NSColor(calibratedWhite: 0.18, alpha: 1) : palette[0]))
        let newThemeWindow = NoteWindow(note: interactionNote)
        assert(newThemeWindow.window!.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
        newThemeWindow.close()
    }
    App.shared.configureAppearancePicker()
    assert(App.shared.appearancePicker.titleOfSelectedItem == mode.title)
}
UserDefaults.standard.set("unknown", forKey: "appearanceMode")
assert(AppAppearanceMode.current == .system)
UserDefaults.standard.set("system", forKey: "appearanceMode")
App.shared.applyAppearance()
App.shared.windows.removeValue(forKey: interactionNote.id)
themeWindow.close(); themeLibraryWindow.close()
interactionLibrary.setDisplayMode(.list)
print("PASS: Grid single/double clicks on labels and card; context target; stale cards; Light/Dark/System modes and persistence; existing/new window appearance")
