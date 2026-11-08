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
