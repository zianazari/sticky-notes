// Native titlebar controls must stay within the inset sidebar and remain usable.
UserDefaults.standard.set(false, forKey: "librarySidebarHidden")
let chromeLibrary = LibraryController()
let chromeWindow = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 960, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
chromeWindow.isReleasedWhenClosed = false
chromeWindow.titleVisibility = .hidden; chromeWindow.titlebarAppearsTransparent = true
chromeWindow.titlebarSeparatorStyle = .none
chromeWindow.appearance = NSAppearance(named: .aqua)
chromeWindow.contentViewController = chromeLibrary
chromeLibrary.installTitlebarControls(on: chromeWindow)
assert(chromeWindow.titlebarAccessoryViewControllers.count == 1)
chromeWindow.contentView?.superview?.layoutSubtreeIfNeeded()
chromeLibrary.view.layoutSubtreeIfNeeded()
let chromeAccessory = chromeWindow.titlebarAccessoryViewControllers[0].view
func chromeButtons(_ view: NSView) -> [NSButton] {
    (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { chromeButtons($0) }
}
let chromeActions = chromeButtons(chromeAccessory)
assert(chromeActions.count == 2)
for action in chromeActions {
    let rect = chromeLibrary.view.convert(action.bounds, from: action)
    print("Sidebar action", action.toolTip ?? "", rect)
    assert(rect.minX >= 90 && rect.maxX <= 254, "Titlebar actions escaped the sidebar: \(rect), accessory: \(chromeAccessory.frame)")
    assert(action.action != nil)
}
let zoomRect = chromeLibrary.view.convert(chromeWindow.standardWindowButton(.zoomButton)!.bounds, from: chromeWindow.standardWindowButton(.zoomButton)!)
print("Sidebar zoom", zoomRect)
assert(zoomRect.maxX < chromeLibrary.view.convert(chromeActions[0].bounds, from: chromeActions[0]).minX)
chromeLibrary.isSidebarVisible = false; chromeLibrary.applySidebarVisibility()
assert(chromeAccessory.isHidden && !chromeLibrary.restoreSidebar.isHidden)
chromeLibrary.isSidebarVisible = true; chromeLibrary.applySidebarVisibility()
assert(!chromeAccessory.isHidden && chromeLibrary.restoreSidebar.isHidden)
if let frameView = chromeWindow.contentView?.superview,
   let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
    if let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/sidebar-reference-preview.png"))
    }
}
chromeWindow.close()
print("PASS: native sidebar titlebar controls; aligned traffic lights; collapsed/expanded controls")
