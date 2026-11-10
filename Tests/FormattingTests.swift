// Formatting acts on the current column and retains unrelated rich-text attributes.
let firstFormatStyle = NSMutableParagraphStyle(); firstFormatStyle.alignment = .left; firstFormatStyle.baseWritingDirection = .leftToRight
let secondFormatStyle = NSMutableParagraphStyle(); secondFormatStyle.alignment = .left; secondFormatStyle.baseWritingDirection = .rightToLeft
let formatText = NSMutableAttributedString(string: "First column\u{000c}", attributes: [.font: NSFont(name: "Helvetica", size: 16)!, .paragraphStyle: firstFormatStyle])
let secondFormatStart = formatText.length
formatText.append(NSAttributedString(string: "متن فارسی", attributes: [.font: NSFont.boldSystemFont(ofSize: 24), .paragraphStyle: secondFormatStyle, .underlineStyle: NSUnderlineStyle.single.rawValue]))
formatText.append(NSAttributedString(string: " small", attributes: [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: secondFormatStyle]))
var formatNote = Note(); formatNote.columnCount = 2
formatNote.richText = formatText.rtfd(from: NSRange(location: 0, length: formatText.length), documentAttributes: [:])!
Store.shared.notes.append(formatNote)
let formatWindow = NoteWindow(note: formatNote)
let formatEditor = formatWindow.flow.secondary
formatWindow.window!.makeFirstResponder(formatEditor)
formatEditor.setSelectedRange(NSRange(location: secondFormatStart, length: formatText.length - secondFormatStart))
assert(formatWindow.fontPicker.numberOfItems > 1)
assert(formatWindow.window!.contentMinSize.width < 520)
func checkFormatStyle(_ alignment: NSTextAlignment) {
    let firstStyle = formatEditor.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
    let secondStyle = formatEditor.textStorage!.attribute(.paragraphStyle, at: secondFormatStart, effectiveRange: nil) as! NSParagraphStyle
    assert(firstStyle.alignment == .left && firstStyle.baseWritingDirection == .leftToRight)
    assert(secondStyle.alignment == alignment && secondStyle.baseWritingDirection == .rightToLeft)
    assert(formatEditor.string == formatText.string)
}
formatWindow.center(); checkFormatStyle(.center)
formatWindow.right(); checkFormatStyle(.right)
formatWindow.left(); checkFormatStyle(.left)
// Test actual line positions, not only saved style values.
func secondLineX() -> CGFloat {
    formatWindow.refreshFlow()
    let manager = formatEditor.layoutManager!
    manager.ensureLayout(for: formatEditor.textContainer!)
    let range = manager.glyphRange(forCharacterRange: NSRange(location: secondFormatStart, length: 1), actualCharacterRange: nil)
    return manager.boundingRect(forGlyphRange: range, in: formatEditor.textContainer!).minX
}
let leftLineX = secondLineX()
formatWindow.center(); let centeredLineX = secondLineX()
formatWindow.right(); let rightLineX = secondLineX()
assert(centeredLineX > leftLineX && rightLineX > centeredLineX)
formatEditor.undoManager!.removeAllActions()
let originalFormatFont = formatEditor.textStorage!.attribute(.font, at: secondFormatStart, effectiveRange: nil) as! NSFont
let newFamily = NSFontManager.shared.availableFontFamilies.contains("Courier") ? "Courier" : "Times New Roman"
formatWindow.window!.makeFirstResponder(nil) // Toolbar focus must not switch back to column one.
formatWindow.fontPicker.selectItem(withTitle: newFamily)
formatWindow.fontChanged(formatWindow.fontPicker)
let firstFormatFont = formatEditor.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
let changedFormatFont = formatEditor.textStorage!.attribute(.font, at: secondFormatStart, effectiveRange: nil) as! NSFont
let smallFormatFont = formatEditor.textStorage!.attribute(.font, at: formatText.length - 1, effectiveRange: nil) as! NSFont
assert(firstFormatFont.familyName == "Helvetica" && firstFormatFont.pointSize == 16)
assert(changedFormatFont.familyName == newFamily && changedFormatFont.pointSize == 24)
assert(NSFontManager.shared.traits(of: changedFormatFont).contains(.boldFontMask))
assert(smallFormatFont.familyName == newFamily && smallFormatFont.pointSize == 14)
assert(formatEditor.textStorage!.attribute(.underlineStyle, at: secondFormatStart, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
formatEditor.undoManager!.undo()
assert(formatEditor.textStorage!.attribute(.font, at: secondFormatStart, effectiveRange: nil) as? NSFont == originalFormatFont)
formatEditor.undoManager!.redo()
assert((formatEditor.textStorage!.attribute(.font, at: secondFormatStart, effectiveRange: nil) as? NSFont)?.familyName == newFamily)
formatEditor.setSelectedRange(NSRange(location: formatEditor.textStorage!.length, length: 0))
formatWindow.fontPicker.selectItem(withTitle: "System Font"); formatWindow.fontChanged(formatWindow.fontPicker)
assert((formatEditor.textStorage!.attribute(.font, at: secondFormatStart, effectiveRange: nil) as? NSFont)?.familyName == newFamily)
formatEditor.insertText(" more", replacementRange: formatEditor.selectedRange())
assert((formatEditor.textStorage!.attribute(.font, at: formatEditor.textStorage!.length - 1, effectiveRange: nil) as? NSFont)?.familyName != newFamily)
let savedFormatNote = Store.shared.notes.first { $0.id == formatNote.id }!
let savedFormatText = NSAttributedString(rtfd: savedFormatNote.richText, documentAttributes: nil)!
assert((savedFormatText.attribute(.paragraphStyle, at: secondFormatStart, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .right)
assert((savedFormatText.attribute(.font, at: secondFormatStart, effectiveRange: nil) as? NSFont)?.familyName == newFamily)
formatWindow.close()
print("PASS: left/center/right alignment and visible layout; RTL independence; font list; both column scopes; mixed font sizes/traits; undo/redo and persistence")
