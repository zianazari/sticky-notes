// Compiled with the application declarations by run-library-tests.py.
import QuartzCore
let application = NSApplication.shared
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/group-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let file = root.appendingPathComponent("notes.json")
let legacy = "[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"Existing note\",\"richText\":\"\",\"color\":0,\"modified\":0}]"
try Data(legacy.utf8).write(to: file)
let store = Store(url: file)
assert(store.notes.count == 1 && store.groups.isEmpty)
let original = store.notes[0]
let work = store.createGroup(name: " Work ")!
let personal = store.createGroup(name: "Personal")!
assert(work.name == "Work")
assert(store.createGroup(name: "work") == nil)
assert(store.createGroup(name: "  ") == nil)
assert(store.moveNote(id: original.id, to: work.id))
assert(!store.moveNote(id: original.id, to: UUID()))
assert(store.renameGroup(id: work.id, name: "Projects"))
assert(!store.renameGroup(id: work.id, name: "PERSONAL"))
try store.write()
let restored = Store(url: file)
assert(restored.groups.count == 2)
assert(restored.resolvedGroupID(for: restored.notes[0]) == work.id)
assert(restored.groups.first!.name == "Projects")
restored.removeGroup(id: work.id)
try restored.write()
let afterDelete = Store(url: file)
assert(afterDelete.notes.count == 1 && afterDelete.notes[0].title == original.title)
assert(afterDelete.notes[0].richText == original.richText)
assert(afterDelete.resolvedGroupID(for: afterDelete.notes[0]) == nil)
assert(afterDelete.groups == [personal])
var orphan = original; orphan.groupID = UUID()
assert(afterDelete.resolvedGroupID(for: orphan) == nil)
// UI checks use the isolated Store.shared path supplied by the test runner.
Store.shared.notes = [original]; Store.shared.groups = []
let library = LibraryController(); _ = library.view
library.view.setFrameSize(NSSize(width: 960, height: 610)); library.view.layoutSubtreeIfNeeded()
let group = Store.shared.createGroup(name: "Work")!
library.reload()
assert(library.filters.count == 3 && library.notes.count == 1)
library.filter = .group(group.id); library.reload()
assert(library.notes.isEmpty && !library.emptyLabel.isHidden)
assert(library.selectedNote == nil)
Store.shared.moveNote(id: original.id, to: group.id); library.reload()
assert(library.notes.count == 1 && library.heading.stringValue == "Work")
library.notesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
library.updateSelection()
assert(library.selectedNote?.id == original.id)
assert(library.notesTable.action == nil && library.notesTable.doubleAction != nil)
library.reload(); assert(library.selectedNote?.id == original.id)
library.isSidebarVisible = false; library.applySidebarVisibility(); library.view.layoutSubtreeIfNeeded()
assert(library.sidebar.isHidden && !library.restoreSidebar.isHidden)
assert(library.sidebarLeading.constant == -260 && library.mainWithSidebar.isActive)
library.isSidebarVisible = true; library.applySidebarVisibility(); library.view.layoutSubtreeIfNeeded()
assert(!library.sidebar.isHidden && library.restoreSidebar.isHidden)
let menu = library.groupMenu(id: group.id)
assert(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Rename group…", "Delete group…", "New group…"])
Store.shared.removeGroup(id: group.id); library.filter = .ungrouped; library.reload()
assert(library.notes.count == 1)
print("PASS: legacy notes; create/rename/delete groups; duplicate names; membership and persistence; content preservation; filtering/counts; selection/double click; sidebar toggle and menus")

// Regressions: controls must fit within the sidebar at all supported window widths.
func assertSidebarFits() {
    library.view.layoutSubtreeIfNeeded()
    let scroll = library.groupsTable.enclosingScrollView!
    scroll.tile()
    library.groupsTable.layoutSubtreeIfNeeded()
    let width = scroll.contentView.bounds.width
    assert(width > 150)
    assert(abs(library.groupsTable.tableColumns[0].width - width) < 1)
    var alignedCountX: CGFloat?
    for index in library.filters.indices {
        let cell = library.groupsTable.view(atColumn: 0, row: index, makeIfNecessary: true) as! GroupCell
        cell.layoutSubtreeIfNeeded()
        let countFrame = cell.countField.convert(cell.countField.bounds, to: library.groupsTable)
        assert(countFrame.maxX <= width + 1 && countFrame.minX >= 0)
        if let x = alignedCountX { assert(abs(x - countFrame.maxX) < 0.5) }
        alignedCountX = countFrame.maxX
        assert(cell.countField.stringValue == String(Store.shared.notes.filter { library.matches($0, filter: library.filters[index]) }.count))
        if let more = cell.actionsButton {
            let actionFrame = more.convert(more.bounds, to: library.groupsTable)
            assert(actionFrame.maxX <= width + 1 && actionFrame.minX >= 0)
            assert(more.action != nil)
            cell.hovered = false; assert(more.isHidden)
            cell.hovered = true; assert(!more.isHidden)
            cell.hovered = false; assert(more.isHidden)
        }
    }
}
library.newGroup()
let firstNewID = library.currentGroupID!
assert(Store.shared.groups.last!.name == "New Group")
assert(library.editingGroupID == firstNewID && library.editingField!.isEditable)
library.editingField!.stringValue = "Research"
library.finishGroupEditing()
assert(Store.shared.groups.last!.name == "Research")
library.newGroup(); library.finishGroupEditing(cancel: true)
assert(Store.shared.groups.last!.name == "New Group")
library.newGroup()
assert(Store.shared.groups.last!.name == "New Group 2")
library.editingField!.stringValue = "Research"
library.finishGroupEditing()
assert(Store.shared.groups.last!.name == "New Group 2")
library.beginGroupEditing(firstNewID)
library.editingField!.stringValue = "Discard this edit"
library.finishGroupEditing(cancel: true)
assert(Store.shared.groups.first!.name == "Research")
for width in [720.0, 960.0, 1200.0] {
    library.view.setFrameSize(NSSize(width: width, height: 610))
    assertSidebarFits()
}
library.toggleSidebar(); library.toggleSidebar(); assertSidebarFits()
let persistedGroups = Store(url: Store.shared.url).groups
assert(persistedGroups == Store.shared.groups)
print("PASS: sidebar column width; visible counts/actions; inline group creation/rename/cancel; unique default names; persistence")

// Context actions retain the clicked note's ID, even if another note is selected.
let emptyNote = Note()
var whitespaceNote = Note()
whitespaceNote.richText = NSAttributedString(string: " \n\t").rtf(from: NSRange(location: 0, length: 3), documentAttributes: [:])!
var textNote = Note()
textNote.richText = NSAttributedString(string: "Keep me").rtf(from: NSRange(location: 0, length: 7), documentAttributes: [:])!
var imageNote = Note()
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let testImage = NSImage(size: NSSize(width: 10, height: 10)); testImage.addRepresentation(bitmap)
let wrapper = FileWrapper(regularFileWithContents: testImage.tiffRepresentation!); wrapper.preferredFilename = "image.tiff"
let attachment = NSTextAttachment(fileWrapper: wrapper)
attachment.attachmentCell = NSTextAttachmentCell(imageCell: testImage)
let imageContent = NSAttributedString(attachment: attachment)
imageNote.richText = imageContent.rtfd(from: NSRange(location: 0, length: imageContent.length), documentAttributes: [:])!
var unknownNote = Note(); unknownNote.richText = Data([0, 1, 2, 3])
assert(emptyNote.isEmpty && whitespaceNote.isEmpty)
assert(!textNote.isEmpty && !imageNote.isEmpty && !unknownNote.isEmpty)
Store.shared.notes += [emptyNote, whitespaceNote, textNote, imageNote]
library.selectAllNotes()
App.shared.libraryController = library
library.notesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
let contextMenu = library.noteMenu(for: emptyNote)
assert(contextMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Open Note in New Window", "New Note", "Move to", "Delete"])
let destinations = contextMenu.item(withTitle: "Move to")!.submenu!
assert(destinations.items.first!.title == "Ungrouped")
let researchDestination = destinations.items.first { $0.title == "Research" }!
library.moveNote(researchDestination)
assert(Store.shared.notes.first { $0.id == emptyNote.id }!.groupID == firstNewID)
library.deleteContextNote(contextMenu.item(withTitle: "Delete")!)
assert(!Store.shared.notes.contains { $0.id == emptyNote.id })
assert(Store.shared.notes.contains { $0.id == original.id })
App.shared.deleteNote(id: whitespaceNote.id)
assert(!Store.shared.notes.contains { $0.id == whitespaceNote.id })
let emptyGroup = Store.shared.createGroup(name: "Delete without a prompt")!
let deleteEmptyGroup = library.groupMenu(id: emptyGroup.id).item(withTitle: "Delete group…")!
library.deleteGroup(deleteEmptyGroup)
assert(!Store.shared.groups.contains { $0.id == emptyGroup.id })
assertSidebarFits()
print("PASS: count alignment; context menus and exact note targets; empty-note/group deletion; text/image preservation")
// Hidden windows settle immediately; visible windows use the animated path.
let animationWindow = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 960, height: 610), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
animationWindow.isReleasedWhenClosed = false
animationWindow.contentViewController = library
library.isSidebarVisible = true; library.applySidebarVisibility()
library.toggleSidebar()
assert(!library.isSidebarAnimating && library.sidebar.isHidden)
assert(abs(library.main.frame.minX) < 1)
library.toggleSidebar()
assert(!library.isSidebarAnimating && !library.sidebar.isHidden)
assert(abs(library.main.frame.minX - 260) < 1)
assertSidebarFits()
animationWindow.close()
print("PASS: sidebar final layout in a hidden window")

// Exercise the same timer-driven slide in both directions, without showing a window.
library.isSidebarVisible = true; library.applySidebarVisibility()
library.isSidebarVisible = false; library.animateSidebar(to: -260)
RunLoop.current.run(until: Date().addingTimeInterval(0.18))
assert(library.isSidebarAnimating && !library.sidebar.isHidden)
assert(library.sidebarLeading.constant < 0 && library.sidebarLeading.constant > -260)
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
assert(!library.isSidebarAnimating && library.sidebar.isHidden && library.sidebarLeading.constant == -260)
library.isSidebarVisible = true; library.animateSidebar(to: 0)
RunLoop.current.run(until: Date().addingTimeInterval(0.18))
assert(library.isSidebarAnimating && !library.sidebar.isHidden)
assert(library.sidebarLeading.constant > -260 && library.sidebarLeading.constant < 0)
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
assert(!library.isSidebarAnimating && !library.sidebar.isHidden && library.sidebarLeading.constant == 0)
UserDefaults.standard.register(defaults: ["size": 17.0, "opacity": 1.0])
UserDefaults.standard.set(true, forKey: "dark") // Legacy preference must no longer override system appearance.
let themedNote = NoteWindow(note: textNote)
assert(themedNote.window!.appearance == nil)
themedNote.primaryEditor.appearance = NSAppearance(named: .aqua)
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
assert(themedNote.window!.backgroundColor == palette[0])
themedNote.primaryEditor.appearance = NSAppearance(named: .darkAqua)
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
assert(themedNote.window!.backgroundColor == NSColor(calibratedWhite: 0.18, alpha: 1))
assert(themedNote.primaryEditor.string == "Keep me")
let hoverCell = GroupCell(); hoverCell.actionsButton = NSButton()
assert(hoverCell.actionsButton!.isHidden)
hoverCell.hovered = true; assert(!hoverCell.actionsButton!.isHidden)
hoverCell.hovered = false; assert(hoverCell.actionsButton!.isHidden)
hoverCell.appearance = NSAppearance(named: .darkAqua); hoverCell.selected = true
assert(hoverCell.nameField.textColor == .systemYellow)
themedNote.close()
print("PASS: hover-only actions; both animation directions and intermediate positions; system appearance colors; selected group styling")
