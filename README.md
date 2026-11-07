<div align="center">
  <img src="Assets/AppIcon.png" alt="Three overlapping colorful sticky notes" width="150" />

# Sticky Notes

**A little space for ideas, reminders, and everything in between.**

A native macOS app with colorful notes, rich text, images, and a quiet place to keep them all.

![macOS](https://img.shields.io/badge/macOS-14%2B-222222?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6_toolchain-F05138?logo=swift&logoColor=white)
![UI](https://img.shields.io/badge/UI-AppKit-147EFB)
![Storage](https://img.shields.io/badge/Storage-Local_only-568C53)

</div>

## At a glance

Create a note, give it a color, and start writing. Edits save automatically. Closing a note keeps it in **My Notes**, ready to open again with a double-click.

- **Your notes, on your Mac.** No account, cloud service, or subscription required.
- **An independent window for every note.** Resize it, keep it above other windows, or close it for later.
- **A familiar native editor.** Fonts, headings, images, and writing direction use macOS text-editing foundations.


## Features

### Notes that stay with you

- Five colors: **Yellow, Rose, Sage, Sky, and Lavender**.
- **My Notes** displays saved notes with their titles and modification times.
- Single-click to select; double-click to open.
- Automatic local saving after edits and when a note closes.
- A confirmation before permanently deleting a note.
- Independently resizable windows, with a minimum size that keeps all controls visible.

### Rich text, without a separate document app

- Native font picker, **bold**, underline, and bullet insertion.
- **Text, H1, H2, and H3** styles.
- Left and right alignment, plus left-to-right and right-to-left writing.
- **One or two continuous text columns** sharing the same document.
- Click an empty second column to start writing there. Switching back to one column brings all text together in order.
- Standard copy, cut, paste, select-all, and text undo shortcuts.

### Images inside your notes

- Add images with the **Image** button, paste them, or drag image files into a note.
- Click an image to select it; press **Delete** to remove it.
- Drag the selected image's lower-right blue handle to resize it.
- Use **Resize image** to enter a precise width while preserving its proportions.
- Images are embedded in the saved note rather than linked to their original file location.

### Make it feel right

- Light and dark appearances.
- Window opacity from **25% to 100%**.
- **Keep note above** is saved independently for each note.
- Persistent defaults for new notes: font family, font size, color, and writing direction.
- Color swatches beside color names.
- Settings under **Sticky Notes → Settings…**, and note creation under **File → New Note**.

## Download

**[Download the latest macOS release](https://github.com/zianazari/sticky-notes/releases/latest)**

Choose the Apple Silicon ZIP, unzip it, and drag **Sticky Notes.app** into Applications.
The release includes SHA-256 checksums. This build is locally signed, not notarized by Apple.

## Get started

If you already have a built copy, open `dist/Sticky Notes.app`. To install it, copy the app to **Applications** with Finder. Quit an older running version before replacing it.

Build outputs are intentionally excluded from Git, so a fresh checkout must be built first.

### Build from source

Requirements:

- macOS with Apple Command Line Tools installed.
- A Swift 6 toolchain, Python 3, and the standard macOS command-line utilities.
- The generated app declares macOS 14 as its minimum version. Development builds have been compiled on Apple Silicon; older macOS releases have not been separately validated.

```sh
# Install Apple's tools if needed.
xcode-select --install

# From the project directory:
./scripts/build.sh

# Launch the built app.
open "dist/Sticky Notes.app"
```

The script compiles the Swift sources, packages the icon and app bundle, writes version metadata, and applies a local ad-hoc signature. It also assigns a custom Finder icon to preserve the transparent paper silhouette.

> This is a local development build, not a notarized release for public distribution. The script targets the architecture of the Mac running it; it does not produce a universal binary.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New note | `⌘N` |
| Show all notes | `⌘L` |
| Settings | `⌘,` |
| Undo text editing | `⌘Z` |
| Cut / Copy / Paste | `⌘X` / `⌘C` / `⌘V` |
| Select all | `⌘A` |
| Quit | `⌘Q` |
| Delete a selected image | `Delete` |

## Technology

<p align="left">
  <img src="https://skillicons.dev/icons?i=swift,py,bash,git&theme=dark" alt="Swift, Python, shell scripting and Git" />
</p>
<p align="left">
  <img src="https://img.shields.io/badge/AppKit-147EFB?style=for-the-badge&logo=apple&logoColor=white" alt="AppKit" />
  <img src="https://img.shields.io/badge/TextKit-555555?style=for-the-badge&logo=apple&logoColor=white" alt="TextKit" />
  <img src="https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS" />
</p>

| Layer | Implementation |
| --- | --- |
| Language | **Swift**, compiled with the Swift 6 toolchain |
| Native interface | **AppKit** — `NSWindow`, `NSTableView`, `NSStackView`, and native menus |
| Text editing | **TextKit 1** — `NSTextView`, `NSTextStorage`, `NSLayoutManager`, and linked `NSTextContainer` objects |
| Rich content | **RTFD** for attributed text and embedded image attachments |
| Note storage | **Foundation Codable + JSON**, written atomically to disk |
| Preferences | **UserDefaults** |
| Image import | **AppKit + UniformTypeIdentifiers** |
| Packaging | **zsh**, `swiftc`, small **Python 3** helpers, `sips`, and `codesign` |

The app uses native macOS frameworks and has **no third-party runtime dependencies**. Two-column mode uses linked text containers, not tables or separate documents.


