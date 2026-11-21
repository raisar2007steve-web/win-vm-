# Latest CI diagnostics

Run: 44862337908  ·  commit a1aeed962d53f208990c991462995efab19ae91f  ·  2026-11-21T03:42:32Z
Device: iPhone 17 Pro Max

## Build errors
```
/Users/runner/work/win-vm-/win-vm-/NotesApp/Services/SeedData.swift:13:19: error: call to main actor-isolated instance method 'createFolder(named:symbolName:)' in a synchronous nonisolated context
/Users/runner/work/win-vm-/win-vm-/NotesApp/Services/SeedData.swift:87:30: error: call to main actor-isolated instance method 'createNote(title:document:folder:tags:now:)' in a synchronous nonisolated context
/Users/runner/work/win-vm-/win-vm-/NotesApp/Services/SeedData.swift:90:52: error: call to main actor-isolated instance method 'tag(named:)' in a synchronous nonisolated context
/Users/runner/work/win-vm-/win-vm-/NotesApp/Services/SeedData.swift:92:15: error: call to main actor-isolated instance method 'persist()' in a synchronous nonisolated context
```

## Build warnings
```
```
