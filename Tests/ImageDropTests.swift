// Local image files and image data from other apps share the same drop importer.
let dropBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 60, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let dropPNG = dropBitmap.representation(using: .png, properties: [:])!
let dropImage = NSImage(data: dropPNG)!
let dropFile = root.appendingPathComponent("test image.png")
try dropPNG.write(to: dropFile)
let fileItem = NSPasteboardItem(); fileItem.setString(dropFile.absoluteString, forType: .fileURL)
fileItem.setData(dropPNG, forType: .png) // A file preview must not duplicate the image.
let pngItem = NSPasteboardItem(); pngItem.setData(dropPNG, forType: .png)
let tiffItem = NSPasteboardItem(); tiffItem.setData(dropImage.tiffRepresentation!, forType: .tiff)
let textItem = NSPasteboardItem(); textItem.setString("Keep normal text drops working", forType: .string)
let brokenItem = NSPasteboardItem(); brokenItem.setData(Data([1, 2, 3]), forType: .png)
let remoteItem = NSPasteboardItem(); remoteItem.setString("https://example.com/image.png", forType: .fileURL)
assert(NoteTextView.images(from: [fileItem]).count == 1)
assert(NoteTextView.images(from: [fileItem, pngItem, tiffItem]).count == 3)
assert(NoteTextView.images(from: [textItem, brokenItem, remoteItem]).isEmpty)
assert(NoteTextView.images(from: [brokenItem, fileItem]).count == 1)

func attachmentIndices(in text: NSAttributedString) -> [Int] {
    var result: [Int] = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
        if value != nil { result.append(range.location) }
    }
    return result
}
var dropNote = Note(); dropNote.columnCount = 2
let dropInitial = NSAttributedString(string: "Keep existing text")
dropNote.richText = dropInitial.rtfd(from: NSRange(location: 0, length: dropInitial.length), documentAttributes: [:])!
Store.shared.notes.append(dropNote)
let dropWindow = NoteWindow(note: dropNote)
let dropPrimary = dropWindow.primaryEditor
let dropSecondary = dropWindow.flow.secondary
// A drop inserts at the pointer without replacing a previously selected paragraph.
dropPrimary.setSelectedRange(NSRange(location: 0, length: dropPrimary.textStorage!.length))
assert(dropPrimary.insertDroppedImages(NoteTextView.images(from: [fileItem]), at: NSPoint(x: 12, y: 15)))
assert(dropPrimary.string.contains("Keep existing text"))
assert(attachmentIndices(in: dropPrimary.textStorage!).count == 1)
dropWindow.refreshFlow()
let beforeSecondDrop = dropPrimary.string
dropSecondary.undoManager?.removeAllActions()
assert(dropSecondary.insertDroppedImages(NoteTextView.images(from: [pngItem, tiffItem]), at: NSPoint(x: 12, y: 15)))
assert(dropPrimary.string.contains("\u{000c}"))
let allDroppedAttachments = attachmentIndices(in: dropPrimary.textStorage!)
assert(allDroppedAttachments.count == 3)
dropWindow.refreshFlow()
let dropLayout = dropPrimary.layoutManager!
dropLayout.ensureLayout(for: dropSecondary.textContainer!)
for index in allDroppedAttachments.suffix(2) {
    let glyph = dropLayout.glyphIndexForCharacter(at: index)
    assert(dropLayout.textContainer(forGlyphAt: glyph, effectiveRange: nil) === dropSecondary.textContainer)
}
let savedDrop = Store.shared.notes.first { $0.id == dropNote.id }!
assert(attachmentIndices(in: NSAttributedString(rtfd: savedDrop.richText, documentAttributes: nil)!).count == 3)
dropSecondary.undoManager!.undo()
assert(dropPrimary.string == beforeSecondDrop)
dropSecondary.undoManager!.redo()
assert(attachmentIndices(in: dropPrimary.textStorage!).count == 3)
let lastDroppedIndex = attachmentIndices(in: dropPrimary.textStorage!).last!
dropSecondary.setSelectedRange(NSRange(location: lastDroppedIndex, length: 1))
assert(dropSecondary.selectedImage() != nil)
assert(dropSecondary.resizeSelectedImage(to: 100))
dropSecondary.deleteBackward(nil)
assert(attachmentIndices(in: dropPrimary.textStorage!).count == 2)
try FileManager.default.removeItem(at: dropFile)
// Imported images are embedded, so deleting the original file does not affect them.
let storedDrop = Store.shared.notes.first { $0.id == dropNote.id }!
let reopenedDrop = NSAttributedString(rtfd: storedDrop.richText, documentAttributes: nil)!
assert(attachmentIndices(in: reopenedDrop).count == 2)
dropPrimary.isEditable = false
assert(!dropPrimary.insertDroppedImages([dropImage], at: .zero))
dropWindow.close()
print("PASS: file/PNG/TIFF drag payloads; multiple images; no duplicate previews; both column destinations; embedded autosave; undo/redo; image resize/delete")
