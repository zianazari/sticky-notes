#!/usr/bin/env python3
"""Build the real app declarations with an isolated store and assertion harness."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='sticky-tests-', dir=root / '.build') as directory:
    temp = Path(directory)
    source = (root / 'Sources/StickyNotes/main.swift').read_text().split('let app = NSApplication.shared')[0]
    source = source.replace('static let shared = Store()', 'static let shared = Store(url: URL(fileURLWithPath: "' + str(temp / 'notes.json') + '"))')
    source = source.replace('UserDefaults.standard', 'UserDefaults(suiteName: "StickyNotes.LibraryTests")!')
    (temp / 'main.swift').write_text(source + '\n' + (root / 'Tests/LibraryTests.swift').read_text().replace('UserDefaults.standard', 'UserDefaults(suiteName: \"StickyNotes.LibraryTests\")!'))
    controller = (root / 'Sources/StickyNotes/LibraryController.swift').read_text().replace('UserDefaults.standard', 'UserDefaults(suiteName: \"StickyNotes.LibraryTests\")!')
    (temp / 'LibraryController.swift').write_text(controller)
    binary = temp / 'tests'
    subprocess.run(['swiftc', '-module-cache-path', str(root / '.build/module-cache'), str(temp / 'main.swift'), str(temp / 'LibraryController.swift'), '-o', str(binary)], check=True, cwd=root)
    subprocess.run([str(binary)], check=True, cwd=root)
