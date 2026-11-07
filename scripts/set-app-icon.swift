import AppKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appURL = root.appendingPathComponent("dist/Sticky Notes.app")
let image = NSImage(contentsOf: root.appendingPathComponent("Assets/AppIcon.png"))!
let clear = CommandLine.arguments.contains("--clear")
guard NSWorkspace.shared.setIcon(clear ? nil : image, forFile: appURL.path, options: []) else { exit(1) }
print(clear ? "Cleared custom icon" : "Applied transparent Finder icon")
