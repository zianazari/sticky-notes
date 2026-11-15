// Color intensity changes color strength, independently of opacity and note data.
UserDefaults.standard.removeObject(forKey: "colorIntensity")
assert(NoteColors.intensity == 0.5)
for base in palette { assert(NoteColors.color(base) == base) }
func rgbSaturation(_ color: NSColor) -> CGFloat {
    let rgb = color.usingColorSpace(.sRGB)!
    let maximum = max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    let minimum = min(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    return maximum == 0 ? 0 : (maximum - minimum) / maximum
}
func luminance(_ color: NSColor) -> CGFloat {
    let rgb = color.usingColorSpace(.sRGB)!
    func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
}
for index in palette.indices {
    var previous: CGFloat = -1
    for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
        UserDefaults.standard.set(amount, forKey: "colorIntensity")
        let color = NoteColors.color(palette[index])
        assert(rgbSaturation(color) >= previous - 0.01)
        previous = rgbSaturation(color)
        assert(color.alphaComponent == 1)
        assert((luminance(NoteColors.paper(index, dark: false)) + 0.05) / 0.05 > 4.5)
        assert(1.05 / (luminance(NoteColors.paper(index, dark: true)) + 0.05) > 4.5)
    }
}
UserDefaults.standard.set(9.0, forKey: "colorIntensity"); assert(NoteColors.intensity == 1)
UserDefaults.standard.set(-1.0, forKey: "colorIntensity"); assert(NoteColors.intensity == 0)
UserDefaults.standard.set(0.5, forKey: "colorIntensity")
var intensityNote = Note(); intensityNote.title = "Color settings"; intensityNote.color = 3
let intensityText = NSAttributedString(string: "Color settings", attributes: [.font: NSFont.boldSystemFont(ofSize: 20), .underlineStyle: 1])
intensityNote.richText = intensityText.rtfd(from: NSRange(location: 0, length: intensityText.length), documentAttributes: [:])!
Store.shared.notes = [intensityNote]; Store.shared.groups = []
let intensityWindow = NoteWindow(note: intensityNote)
intensityWindow.window!.alphaValue = 0.61
intensityWindow.primaryEditor.textStorage!.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: intensityText.length))
let originalIntensityText = NSAttributedString(attributedString: intensityWindow.primaryEditor.textStorage!)
let originalSavedIntensityText = Store.shared.notes[0].richText
let intensityLibrary = LibraryController(); _ = intensityLibrary.view
intensityLibrary.setDisplayMode(.grid)
intensityLibrary.notesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
App.shared.libraryController = intensityLibrary
App.shared.windows[intensityNote.id] = intensityWindow
populateColors(App.shared.color); App.shared.color.selectItem(at: 4)
App.shared.configureColorIntensity()
assert(App.shared.colorIntensity.doubleValue == 0.5)
for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    intensityWindow.window!.appearance = NSAppearance(named: appearance)
    // Theme changes recolor text; intensity itself must leave subsequent formatting alone.
    intensityWindow.primaryEditor.textStorage!.setAttributedString(originalIntensityText)
    for amount in [0.0, 0.25, 1.0] {
        App.shared.colorIntensity.doubleValue = amount
        App.shared.colorIntensityChanged(App.shared.colorIntensity)
        assert(NoteColors.intensity == amount)
        assert(App.shared.colorIntensityLabel.stringValue == "\(Int(amount * 100))%")
        assert(intensityWindow.window!.backgroundColor == NoteColors.paper(3, dark: appearance == .darkAqua))
        assert(intensityWindow.colors.indexOfSelectedItem == 3 && App.shared.color.indexOfSelectedItem == 4)
        assert(abs(intensityWindow.window!.alphaValue - 0.61) < 0.001)
        assert(intensityWindow.primaryEditor.textStorage!.isEqual(to: originalIntensityText))
        assert(Store.shared.notes[0].richText == originalSavedIntensityText)
        assert(intensityLibrary.selectedNote?.id == intensityNote.id && intensityLibrary.displayMode == .grid)
    }
}
App.shared.configureColorIntensity()
assert(App.shared.colorIntensity.doubleValue == 1) // Reopening settings keeps the chosen value.
let newIntensityWindow = NoteWindow(note: intensityNote)
let newDark = newIntensityWindow.primaryEditor.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
assert(newIntensityWindow.window!.backgroundColor == NoteColors.paper(3, dark: newDark))
newIntensityWindow.close()
App.shared.windows.removeValue(forKey: intensityNote.id); intensityWindow.close()
UserDefaults.standard.removeObject(forKey: "colorIntensity")
intensityLibrary.setDisplayMode(.list)
print("PASS: color-intensity defaults/range/persistence; color strength and contrast; live note updates; unchanged opacity/content/selection; new notes")
