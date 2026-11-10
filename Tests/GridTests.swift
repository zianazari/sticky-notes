// List and Grid share filtering, selection, and context-menu note identities.
UserDefaults.standard.set("list", forKey: "libraryDisplayMode")
let gridGroup = NoteGroup(name: "Grid tests")
Store.shared.groups = [gridGroup]
Store.shared.notes = (0..<12).map { index in
    var note = Note(); note.title = "Note \(index) with a longer title"; note.color = index % 5
    note.groupID = index < 3 ? gridGroup.id : nil
    let text = NSAttributedString(string: "\(note.title)\nA preview with enough text to wrap onto multiple lines in a compact grid card.")
    note.richText = text.rtfd(from: NSRange(location: 0, length: text.length), documentAttributes: [:])!
    return note
}
let gridLibrary = LibraryController(); _ = gridLibrary.view
let gridHost = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 960, height: 610), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
gridHost.isReleasedWhenClosed = false; gridHost.contentViewController = gridLibrary
gridLibrary.isSidebarVisible = true; gridLibrary.applySidebarVisibility()
assert(gridLibrary.displayMode == .list && gridLibrary.gridScroll.isHidden)
gridLibrary.notesTable.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
let gridSelectedID = gridLibrary.selectedNote!.id
gridLibrary.setDisplayMode(.grid)
assert(gridLibrary.listScroll.isHidden && !gridLibrary.gridScroll.isHidden)
assert(gridLibrary.viewPicker.selectedSegment == 1)
assert(gridLibrary.selectedNote!.id == gridSelectedID)
assert(gridLibrary.notesGrid.selectionIndexPaths == [IndexPath(item: 4, section: 0)])
assert(gridLibrary.notesGrid.numberOfItems(inSection: 0) == 12)
func verifyGridGeometry() {
    gridLibrary.view.layoutSubtreeIfNeeded(); gridLibrary.updateGridLayout()
    gridLibrary.notesGrid.layoutSubtreeIfNeeded()
    let viewport = gridLibrary.gridScroll.contentSize.width
    let attributes = (0..<gridLibrary.notes.count).map {
        gridLibrary.gridLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!
    }
    assert(attributes[0].frame.minY == attributes[1].frame.minY)
    assert(attributes[1].frame.minX > attributes[0].frame.maxX)
    for item in attributes { assert(item.frame.maxX <= viewport + 1 && item.frame.minX >= 0) }
    assert(attributes.last!.frame.minY > attributes[0].frame.minY)
}
for width in [720.0, 960.0, 1200.0] {
    gridHost.setContentSize(NSSize(width: width, height: 610))
    verifyGridGeometry()
}
gridLibrary.isSidebarVisible = false; gridLibrary.applySidebarVisibility(); verifyGridGeometry()
gridLibrary.isSidebarVisible = true; gridLibrary.applySidebarVisibility(); verifyGridGeometry()
let newGridSelection: Set<IndexPath> = [IndexPath(item: 6, section: 0)]
gridLibrary.notesGrid.selectionIndexPaths = newGridSelection
gridLibrary.collectionView(gridLibrary.notesGrid, didSelectItemsAt: newGridSelection)
assert(gridLibrary.selectedNote!.id == gridLibrary.notes[6].id)
gridLibrary.setDisplayMode(.list)
assert(gridLibrary.notesTable.selectedRow == 6)
gridLibrary.setDisplayMode(.grid)
let gridContext = gridLibrary.notesGrid.itemMenu!(IndexPath(item: 2, section: 0))!
assert(gridContext.item(withTitle: "Delete")!.representedObject as? String == gridLibrary.notes[2].id.uuidString)
assert(gridLibrary.selectedNote!.id == gridLibrary.notes[2].id)
assert(gridContext.item(withTitle: "Move to")!.submenu != nil)
let secondLibrary = LibraryController(); _ = secondLibrary.view
assert(secondLibrary.displayMode == .grid && secondLibrary.listScroll.isHidden)
gridLibrary.filter = .group(gridGroup.id); gridLibrary.reload()
assert(gridLibrary.notesGrid.numberOfItems(inSection: 0) == 3)
assert(gridLibrary.selectedNote != nil)
let groupMove = gridLibrary.moveMenu(for: gridLibrary.notes[2]).item(withTitle: "Ungrouped")!
gridLibrary.moveNote(groupMove)
assert(gridLibrary.notesGrid.numberOfItems(inSection: 0) == 2)
assert(gridLibrary.selectedNote == nil && gridLibrary.notesGrid.selectionIndexPaths.isEmpty)
Store.shared.notes.removeAll { $0.groupID == gridGroup.id }; gridLibrary.reload()
assert(gridLibrary.notesGrid.numberOfItems(inSection: 0) == 0 && !gridLibrary.emptyLabel.isHidden)
gridLibrary.setDisplayMode(.list)
assert(!gridLibrary.emptyLabel.isHidden)
gridHost.close()
print("PASS: List/Grid switch and persistence; adaptive grid geometry; selection; group filtering; context-menu targets; move and empty states")
