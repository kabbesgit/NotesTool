# NotesTool

A super-slim macOS menu-bar app. **Hold a key chord → a note appears on screen; release → it vanishes.**
Built for keeping rarely-used keyboard shortcuts (or any markdown note) one chord away.

## Build & run

```bash
make run
```

This compiles a release build, assembles `NotesTool.app`, ad-hoc codesigns it, and launches it.
A note icon appears in the menu bar — there is no Dock icon.

Requires Xcode command-line tools (Swift 5.9+). Open in Xcode with `open Package.swift` if you prefer.

## First run: grant Accessibility

Watching the keyboard system-wide (global key-down events) requires the **Accessibility** permission.
Input Monitoring is *not* the right one — `NSEvent` global key monitors gate on Accessibility trust.

1. On first launch macOS prompts you — or use the menu bar note icon → **Accessibility Access…**.
2. System Settings → Privacy & Security → **Accessibility** → enable **NotesTool**.
3. No relaunch needed: the app polls for the grant and re-arms itself within ~1s.

### Signing matters

The build is signed with a stable **Apple Development** identity (see `scripts/build-app.sh`,
`NOTESTOOL_SIGN_ID`). This is deliberate: the Accessibility grant is bound to the code signature, and an
**ad-hoc** signature changes on every build, silently revoking the grant. A real identity keeps it stable
across rebuilds. To use a different identity, set `NOTESTOOL_SIGN_ID` (see `security find-identity -v -p codesigning`).

If chords ever stop working after signing changes, you likely have a stale authorization record. Reset it
and re-grant:

```bash
tccutil reset Accessibility com.kasper.notestool
```

## Defining chords

Menu bar → **Configure…**:

- **+** adds a note. Give it a name.
- **Record chord**, then *press and hold* your combination and *release* — e.g. `⌃⌥T` or `⌃⌥⇧`.
  Use 3+ keys to avoid clashes, and always include **⌃ (Control)** so the chord never types into the app
  you're working in.
- Add one or more **markdown items** (bold, `code`, italics, links, line breaks render inline).
- The **Preview** shows exactly what the overlay will look like.

A chord is **modifiers + an optional key, held**. Modifiers must match exactly, so `⌃⌥` and `⌃⌥⇧`
are distinct chords and won't cross-trigger.

## Using it

Hold a configured chord from anywhere — the note floats centered on your active screen, over other apps
and fullscreen windows, without stealing focus. Release any key to dismiss it.

## Launch at login

System Settings → General → Login Items → **+** → select `NotesTool.app`.

## Config storage

Notes are JSON at `~/Library/Application Support/NotesTool/config.json` (editable by hand).
