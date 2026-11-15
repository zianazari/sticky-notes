let pasteEditor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
pasteEditor.isRichText = true
pasteEditor.allowsUndo = true
let localFont = NSFont.systemFont(ofSize: 17)
let clipboardText = "Copied text\nمتن فارسی"
let styledClipboardText = NSAttributedString(string: clipboardText, attributes: [
    .font: NSFont.boldSystemFont(ofSize: 32),
    .foregroundColor: NSColor.red,
    .underlineStyle: NSUnderlineStyle.single.rawValue
])
let clipboardRTF = styledClipboardText.rtf(from: NSRange(location: 0, length: styledClipboardText.length), documentAttributes: [:])!
for plainRepresentation in [nil, clipboardText] {
    pasteEditor.string = "Replace"
    pasteEditor.setSelectedRange(NSRange(location: 0, length: 7))
    pasteEditor.typingAttributes = [.font: localFont]
    assert(pasteEditor.pastePlainText(plainRepresentation) { $0 == .rtf ? clipboardRTF : nil })
    assert(pasteEditor.string == clipboardText)
    let storage = pasteEditor.textStorage!
    storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, _, _ in
        assert((attrs[.font] as? NSFont)?.pointSize == localFont.pointSize, "Font: \(String(describing: attrs[.font]))")
        assert(attrs[.underlineStyle] == nil)
        assert(attrs[.foregroundColor] as? NSColor != .red)
    }
}
assert(!pasteEditor.pastePlainText(nil) { _ in nil })
print("PASS: clipboard text replaces the selection using local formatting; rich-only clipboard; image fallback")
