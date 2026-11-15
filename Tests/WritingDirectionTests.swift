// Direction changes must move the insertion point, even before text is entered.
UserDefaults.standard.set(false, forKey: "rtl")
var directionNote = Note()
Store.shared.notes.append(directionNote)
let directionWindow = NoteWindow(note: directionNote)
let directionEditor = directionWindow.primaryEditor
directionWindow.window!.makeFirstResponder(directionEditor)
directionEditor.setSelectedRange(NSRange(location: 0, length: 0))
func directionCaretX(_ editor: NoteTextView) -> CGFloat {
    editor.layoutManager!.ensureLayout(for: editor.textContainer!)
    let rect = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
    return editor.convert(editor.window!.convertFromScreen(rect), from: nil).minX
}
func chooseDirection(_ index: Int, in window: NoteWindow) {
    window.directionControl.selectedSegment = index
    window.directionChanged(window.directionControl)
    window.refreshFlow()
}
chooseDirection(1, in: directionWindow)
assert((directionEditor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.baseWritingDirection == .rightToLeft)
assert((directionEditor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .right)
assert(directionCaretX(directionEditor) > directionEditor.bounds.width * 0.7, "RTL caret should start on the right")
chooseDirection(0, in: directionWindow)
assert(directionCaretX(directionEditor) < directionEditor.bounds.width * 0.3, "LTR caret should start on the left")
directionEditor.insertText("First column", replacementRange: directionEditor.selectedRange())
directionWindow.columns.selectItem(at: 1); directionWindow.addColumns(directionWindow.columns)
assert(directionWindow.flow.prepareSecondaryInsertion())
let secondDirectionEditor = directionWindow.flow.secondary
chooseDirection(1, in: directionWindow)
assert(directionCaretX(secondDirectionEditor) > secondDirectionEditor.bounds.width * 0.7, "Empty second-column RTL caret should start on the right")
secondDirectionEditor.insertText("سلام", replacementRange: secondDirectionEditor.selectedRange())
secondDirectionEditor.insertNewline(nil)
assert(directionCaretX(secondDirectionEditor) > secondDirectionEditor.bounds.width * 0.7, "RTL newline should preserve the right-side caret")
let firstDirectionStyle = directionEditor.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
assert(firstDirectionStyle.baseWritingDirection != .rightToLeft && firstDirectionStyle.alignment != .right)
chooseDirection(0, in: directionWindow)
assert(directionCaretX(secondDirectionEditor) < secondDirectionEditor.bounds.width * 0.3)
directionWindow.close()
print("PASS: RTL/LTR empty-note caret; empty second column; newline inheritance; independent first-column formatting")
