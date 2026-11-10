// Launch directly into the saved Grid mode, with a restored window size.
Store.shared.notes = (0..<30).map { index in var note = Note(); note.title = "Startup note \(index)"; return note }
Store.shared.groups = []
for width in [720.0, 1180.0] {
    for hiddenSidebar in [false, true] {
        for scrollerStyle in [NSScroller.Style.overlay, .legacy] {
            UserDefaults.standard.set("grid", forKey: "libraryDisplayMode")
            UserDefaults.standard.set(hiddenSidebar, forKey: "librarySidebarHidden")
            let startup = LibraryController()
            let startupWindow = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 960, height: 610), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            startupWindow.isReleasedWhenClosed = false
            startupWindow.contentViewController = startup
            startup.gridScroll.scrollerStyle = scrollerStyle
            startupWindow.setContentSize(NSSize(width: width, height: 610))
            startup.view.layoutSubtreeIfNeeded()
            startup.notesGrid.layoutSubtreeIfNeeded()
            let viewport = startup.gridScroll.contentView.bounds.width
            let expectedColumns = max(1, Int((viewport + 12) / 212))
            let expectedWidth = floor((viewport - CGFloat(expectedColumns - 1) * 12) / CGFloat(expectedColumns))
            let initialFrames = (0..<30).map { startup.gridLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!.frame }
            assert(abs(startup.notesGrid.bounds.width - viewport) < 1, "Initial document width differs from viewport")
            assert(abs(initialFrames[0].width - expectedWidth) < 1, "Initial cards use a stale width")
            if expectedColumns > 1 { assert(initialFrames[1].minY == initialFrames[0].minY) }
            if expectedColumns > 1 { assert(initialFrames[1].minX - initialFrames[0].maxX < 14) }
            startup.setDisplayMode(.list); startup.setDisplayMode(.grid)
            startup.view.layoutSubtreeIfNeeded(); startup.notesGrid.layoutSubtreeIfNeeded()
            let toggledFrames = (0..<30).map { startup.gridLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!.frame }
            assert(initialFrames == toggledFrames, "Switching view modes unexpectedly fixes startup geometry")
            startupWindow.close()
        }
    }
}
UserDefaults.standard.set("list", forKey: "libraryDisplayMode")
UserDefaults.standard.set(false, forKey: "librarySidebarHidden")
print("PASS: initial saved Grid layout matches mode-switch layout; restored sizes; hidden/visible sidebar; overlay/legacy scrollbars")
