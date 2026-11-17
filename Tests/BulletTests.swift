// Automatic list continuation uses real text views and the shared two-column document.
func assertBulletReturn(_ source: String, selection: NSRange? = nil, expected: String, caret: Int? = nil) {
    let editor = NoteTextView()
    editor.isRichText = true
    editor.string = source
    editor.setSelectedRange(selection ?? NSRange(location: (source as NSString).length, length: 0))
    editor.insertNewline(nil)
    assert(editor.string == expected, "Unexpected Enter result: \(editor.string.debugDescription)")
    if let caret { assert(editor.selectedRange() == NSRange(location: caret, length: 0)) }
}
assertBulletReturn("• First item", expected: "• First item\n• ", caret: 15)
assertBulletReturn("Notes\n• خرید نان 🥖", expected: "Notes\n• خرید نان 🥖\n• ")
assertBulletReturn("\t  • Item", expected: "\t  • Item\n\t  • ")
assertBulletReturn("• ", expected: "", caret: 0)
assertBulletReturn("• First\n• \t", expected: "• First\n")
assertBulletReturn("• \nNext", selection: NSRange(location: 2, length: 0), expected: "\nNext")
assertBulletReturn("Plain text", expected: "Plain text\n")
assertBulletReturn("Text • inline", expected: "Text • inline\n")
assertBulletReturn("• First\nPlain", expected: "• First\nPlain\n")
assertBulletReturn("• Hello world", selection: NSRange(location: 8, length: 0), expected: "• Hello \n• world", caret: 11)
assertBulletReturn("• Hello world", selection: NSRange(location: 2, length: 5), expected: "• \n•  world")
assertBulletReturn("• First", selection: NSRange(location: 0, length: 0), expected: "\n• First")
assertBulletReturn("• First\nSecond", selection: NSRange(location: 2, length: 12), expected: "• \n")

let listPrimary = NoteTextView()
listPrimary.isRichText = true
let listFlow = FlowDocument(primary: listPrimary)
let rtlStyle = NSMutableParagraphStyle(); rtlStyle.baseWritingDirection = .rightToLeft; rtlStyle.alignment = .right
let listFont = NSFont.boldSystemFont(ofSize: 19)
let listAttributes: [NSAttributedString.Key: Any] = [.font: listFont, .paragraphStyle: rtlStyle, .underlineStyle: NSUnderlineStyle.single.rawValue]
listPrimary.textStorage!.setAttributedString(NSAttributedString(string: "• یادداشت", attributes: listAttributes))
listFlow.columns = 2
listFlow.secondary.typingAttributes = listAttributes
listFlow.secondary.setSelectedRange(NSRange(location: listPrimary.textStorage!.length, length: 0))
listFlow.secondary.insertNewline(nil)
assert(listPrimary.string == "• یادداشت\n• ")
let addedAttributes = listPrimary.textStorage!.attributes(at: listPrimary.textStorage!.length - 1, effectiveRange: nil)
assert(addedAttributes[.font] as? NSFont == listFont)
assert((addedAttributes[.paragraphStyle] as? NSParagraphStyle)?.baseWritingDirection == .rightToLeft)
assert(addedAttributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
listFlow.secondary.insertNewline(nil)
assert(listPrimary.string == "• یادداشت\n")

// Check autosave and undo through the note window's existing editor delegate.
var bulletNote = Note()
let initialList = NSAttributedString(string: "• Keep this")
bulletNote.richText = initialList.rtfd(from: NSRange(location: 0, length: initialList.length), documentAttributes: [:])!
Store.shared.notes.append(bulletNote)
let bulletWindow = NoteWindow(note: bulletNote)
let bulletEditor = bulletWindow.primaryEditor
bulletEditor.setSelectedRange(NSRange(location: bulletEditor.textStorage!.length, length: 0))
bulletEditor.insertNewline(nil)
let savedList = Store.shared.notes.first { $0.id == bulletNote.id }!
assert(NSAttributedString(rtfd: savedList.richText, documentAttributes: nil)!.string == "• Keep this\n• ")
assert(bulletEditor.undoManager?.canUndo == true)
bulletEditor.undoManager!.undo()
assert(bulletEditor.string == "• Keep this")
bulletEditor.undoManager!.redo()
assert(bulletEditor.string == "• Keep this\n• ")
bulletWindow.close()
print("PASS: bullet continuation and exit; paragraph boundaries; selection replacement; Persian/emoji; two columns; formatting; autosave and undo/redo")

// Regression: a manual column break must start an independent list paragraph.
var twoColumnNote = Note(); twoColumnNote.columnCount = 2
let twoColumnContent = NSAttributedString(string: "First column\u{000c}Second column")
twoColumnNote.richText = twoColumnContent.rtfd(from: NSRange(location: 0, length: twoColumnContent.length), documentAttributes: [:])!
Store.shared.notes.append(twoColumnNote)
let twoColumnWindow = NoteWindow(note: twoColumnNote)
let rightEditor = twoColumnWindow.flow.secondary
twoColumnWindow.window!.makeFirstResponder(rightEditor)
rightEditor.setSelectedRange(NSRange(location: rightEditor.textStorage!.length, length: 0))
twoColumnWindow.bullet()
assert(rightEditor.string == "First column\u{000c}• Second column", "Bullet was inserted in the wrong column: \(rightEditor.string.debugDescription)")
assert(rightEditor.selectedRange().location == (rightEditor.string as NSString).length)
twoColumnWindow.refreshFlow()
let columnManager = rightEditor.layoutManager!
let secondBulletIndex = (rightEditor.string as NSString).range(of: "•").location
let secondBulletGlyph = columnManager.glyphIndexForCharacter(at: secondBulletIndex)
columnManager.ensureLayout(for: rightEditor.textContainer!)
assert(columnManager.textContainer(forGlyphAt: secondBulletGlyph, effectiveRange: nil) === rightEditor.textContainer)
rightEditor.insertNewline(nil)
assert(rightEditor.string == "First column\u{000c}• Second column\n• ")
rightEditor.insertNewline(nil)
assert(rightEditor.string == "First column\u{000c}• Second column\n")
// A toolbar control may temporarily take keyboard focus away from column two.
twoColumnWindow.window!.makeFirstResponder(nil)
assert(twoColumnWindow.editor === rightEditor)
twoColumnWindow.bullet()
assert(rightEditor.string == "First column\u{000c}• Second column\n• ")
assert(twoColumnWindow.window!.firstResponder === rightEditor)
assertBulletReturn("First\u{000c}• Second", expected: "First\u{000c}• Second\n• ")
assertBulletReturn("• First\u{000c}• Second", expected: "• First\u{000c}• Second\n• ")
assertBulletReturn("• First\u{000c}• ", expected: "• First\u{000c}")
assertBulletReturn("• First\u{000c}Plain", expected: "• First\u{000c}Plain\n")
assertBulletReturn("• First\u{000c}Second", selection: NSRange(location: 7, length: 0), expected: "• First\n• \u{000c}Second")
// Reproduce clicking into an initially empty second column before using the toolbar.
twoColumnWindow.primaryEditor.string = "• First column"
twoColumnWindow.refreshFlow()
assert(twoColumnWindow.flow.prepareSecondaryInsertion())
twoColumnWindow.bullet()
assert(rightEditor.string == "• First column\u{000c}• ")
rightEditor.insertText("ستون دوم", replacementRange: rightEditor.selectedRange())
rightEditor.insertNewline(nil)
assert(rightEditor.string == "• First column\u{000c}• ستون دوم\n• ")
twoColumnWindow.close()
print("PASS: second-column toolbar bullet placement; visible glyph container; column-break list continuation/exit; focus restoration; empty column and Persian typing")

// Numbered lists use the same column-aware editing as bullets.
assertBulletReturn("1. First", expected: "1. First\n2. ")
assertBulletReturn("  9. خرید نان", expected: "  9. خرید نان\n  10. ")
assertBulletReturn("1. First\n2. ", expected: "1. First\n")
assertBulletReturn("First\u{000c}3. Second", expected: "First\u{000c}3. Second\n4. ")
assertBulletReturn("3.14 is pi", expected: "3.14 is pi\n")
assertBulletReturn("1. First\n2.", expected: "1. First\n")

var numberedNote = Note()
numberedNote.columnCount = 2
let numberedContent = NSAttributedString(string: "Left\u{000c}• Right")
numberedNote.richText = numberedContent.rtfd(from: NSRange(location: 0, length: numberedContent.length), documentAttributes: [:])!
Store.shared.notes.append(numberedNote)
let numberedWindow = NoteWindow(note: numberedNote)
let numberedEditor = numberedWindow.flow.secondary
numberedWindow.window!.makeFirstResponder(numberedEditor)
numberedEditor.setSelectedRange(NSRange(location: numberedContent.length, length: 0))
numberedWindow.numberedItem()
numberedWindow.numberedItem()
assert(numberedEditor.string == "Left\u{000c}1. Right")
numberedEditor.undoManager!.removeAllActions()
numberedEditor.insertNewline(nil)
assert(numberedEditor.string == "Left\u{000c}1. Right\n2. ")
let savedNumberedNote = Store.shared.notes.first { $0.id == numberedNote.id }!
assert(NSAttributedString(rtfd: savedNumberedNote.richText, documentAttributes: nil)?.string == numberedEditor.string)
numberedEditor.undoManager!.undo()
assert(numberedEditor.string == "Left\u{000c}1. Right")
numberedWindow.close()
print("PASS: numbered-list toolbar, continuation and exit, Persian text, second column, autosave and undo")

// Inserting between items shifts the rest of that list, including digit-width changes.
assertBulletReturn("8. Eight\n9. Nine\n10. Ten\n\n1. Separate",
                   selection: NSRange(location: 8, length: 0),
                   expected: "8. Eight\n9. \n10. Nine\n11. Ten\n\n1. Separate", caret: 12)
assertBulletReturn("1. Alpha beta\n2. Next\u{000c}1. Other column",
                   selection: NSRange(location: 9, length: 0),
                   expected: "1. Alpha \n2. beta\n3. Next\u{000c}1. Other column")
assertBulletReturn("1. A\r\n2. B", selection: NSRange(location: 4, length: 0),
                   expected: "1. A\n2. \r\n3. B")

let middleNote = Note()
Store.shared.notes.append(middleNote)
let middleWindow = NoteWindow(note: middleNote)
let middleEditor = middleWindow.primaryEditor
let middleSource = "8. A\n9. B\n10. C"
middleEditor.string = middleSource
middleEditor.textStorage!.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                       range: NSRange(location: 5, length: 4))
middleEditor.setSelectedRange(NSRange(location: 4, length: 0))
middleEditor.undoManager!.removeAllActions()
middleEditor.insertNewline(nil)
let middleResult = "8. A\n9. \n10. B\n11. C"
assert(middleEditor.string == middleResult)
assert(middleEditor.selectedRange().location == 8)
assert(middleEditor.textStorage!.attribute(.underlineStyle, at: 9, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
middleEditor.undoManager!.undo()
assert(middleEditor.string == middleSource, middleEditor.string)
middleEditor.undoManager!.redo()
assert(middleEditor.string == middleResult, middleEditor.string)
let middleSaved = Store.shared.notes.first { $0.id == middleNote.id }!
assert(NSAttributedString(rtfd: middleSaved.richText, documentAttributes: nil)?.string == middleResult)

middleEditor.string = "1. First\nNew item\n2. Last"
middleEditor.setSelectedRange(NSRange(location: 10, length: 0))
middleWindow.numberedItem()
assert(middleEditor.string == "1. First\n2. New item\n3. Last")
middleWindow.close()
print("PASS: numbered items renumber after middle insertion; caret, styles, save and grouped undo/redo; list and column boundaries")

// Removing list items closes the gap without touching a separate list.
let deletionEditor = NoteTextView()
func assertListDeletion(_ source: String, removing removed: String, expected: String,
                        delete: (NoteTextView) -> Void = { $0.deleteBackward(nil) }) {
    deletionEditor.string = source
    deletionEditor.setSelectedRange((source as NSString).range(of: removed))
    delete(deletionEditor)
    assert(deletionEditor.string == expected, deletionEditor.string.debugDescription)
}
assertListDeletion("1. A\n2. B\n3. C\n4. D", removing: "1. A\n2. B\n", expected: "1. C\n2. D")
assertListDeletion("1. A\n2. B\n3. C\n\n8. Separate", removing: "2. B\n",
                   expected: "1. A\n2. C\n\n8. Separate", delete: { $0.deleteForward(nil) })
assertListDeletion("1. A\n2. B\n3. C", removing: "2. ", expected: "1. A\nB\n2. C", delete: { $0.delete(nil) })
assertListDeletion("8. A\r\n9. B\r\n10. C\u{000c}1. Other column", removing: "9. B\r\n",
                   expected: "8. A\r\n9. C\u{000c}1. Other column")
assertListDeletion("1. A\n2. B\n3. C", removing: "B", expected: "1. A\n2. \n3. C")
assertBulletReturn("1. A\n2. \n3. C", selection: NSRange(location: 8, length: 0), expected: "1. A\n\n2. C")

let deletionNote = Note()
Store.shared.notes.append(deletionNote)
let deletionWindow = NoteWindow(note: deletionNote)
let savedDeletionEditor = deletionWindow.primaryEditor
let deletionSource = "8. A\n9. B\n10. C\n11. D"
let deletionResult = "8. A\n9. C\n10. D"
savedDeletionEditor.string = deletionSource
savedDeletionEditor.setSelectedRange(NSRange(location: 5, length: 5))
savedDeletionEditor.undoManager!.removeAllActions()
savedDeletionEditor.deleteBackward(nil)
assert(savedDeletionEditor.string == deletionResult)
assert(savedDeletionEditor.selectedRange().location == 5)
savedDeletionEditor.undoManager!.undo()
assert(savedDeletionEditor.string == deletionSource)
savedDeletionEditor.undoManager!.redo()
assert(savedDeletionEditor.string == deletionResult)
let savedDeletion = Store.shared.notes.first { $0.id == deletionNote.id }!
assert(NSAttributedString(rtfd: savedDeletion.richText, documentAttributes: nil)?.string == deletionResult)
deletionWindow.close()
print("PASS: list renumbering after deletion; first and middle items, marker removal, boundaries, undo/redo and autosave")
