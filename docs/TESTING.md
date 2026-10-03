# Testing Amaya on a real desktop (Ubuntu / Kubuntu 24.04)

`tools/smoke-test.sh` catches crashes and gross editing regressions under a
virtual X server.  It cannot judge what "running smoothly" means on a real
session: rendering quality, responsiveness, input methods, dialogs.  This
checklist covers that.  Run it once on X11 and once on Wayland (log out,
pick the session type on the login screen), and note the results per item.

Start from a clean profile to avoid stale settings:

```bash
mv ~/.amaya ~/.amaya.bak 2>/dev/null
cd build/amaya && ./amaya ~/some-test-file.html
```

If something crashes, rerun under gdb and keep the backtrace:

```bash
gdb -batch -ex run -ex bt --args ./amaya ~/some-test-file.html
```

## 1. Start-up and window

- [ ] Starts without error dialogs; no developer trace window (a panel of
      checkboxes "Misc, Panels, Dialog…") appears beside the main window
- [ ] Tip-of-the-day dialog opens and closes; "Show tip at startup" is remembered
- [ ] Window resizes and maximises smoothly; document reflows without
      flicker or blank areas
- [ ] HiDPI / scaled display: text and icons are the right size

## 2. Opening and rendering local files

- [ ] File → Open on an `.html` file; also opening via command-line argument
- [ ] UTF-8 page with accents (ã, ç, é, €) and a page declaring ISO-8859-1
- [ ] Page with a linked local CSS file: styles applied
- [ ] Page with local PNG / JPEG / GIF / SVG images
- [ ] Tables with `colspan`/`rowspan`; nested lists; `<pre>`
- [ ] MathML formula and inline SVG (if you use them)
- [ ] Scrolling with wheel, scrollbar, PgUp/PgDn on a long document: smooth,
      no redraw artefacts

## 3. WYSIWYG editing

- [ ] Typing, including at the start and end of elements
- [ ] Portuguese input: dead keys (´ ` ~ ^), ç, AltGr characters (€, @ on
      layouts that need it), compose key if you use one
- [ ] Enter in a paragraph, in a heading, in a list item (new item), in a
      table cell
- [ ] Backspace/Delete across element boundaries (merging paragraphs)
- [ ] Arrow keys, Home/End, Ctrl+arrows, Shift+arrows selection, mouse
      selection, double-click word selection
- [ ] Cut / copy / paste within Amaya, and to/from another application
      (both CLIPBOARD and middle-click PRIMARY)
- [ ] Undo / redo over a sequence of edits
- [ ] Insert: heading, list, table, link, image (local file)
- [ ] Change element type (e.g. paragraph → heading) via the Elements panel
- [ ] Apply bold/italic; apply a class from "Apply class"
- [ ] Source view and structure view open, and stay in sync with edits

## 4. Saving

- [ ] Save (Ctrl+S) and reopen: content identical, encoding preserved
- [ ] Save As to a new directory, with images copied/relocated as offered
- [ ] Save as text, save CSS
- [ ] Unsaved-changes prompt on close and on quit

## 5. Dialogs (each one: opens, fields usable, OK/Cancel work, no crash)

- [ ] Preferences (all tabs) — this exercises code fixed in this branch
- [ ] Style dialog: type a long value (60+ characters) into a field — this
      used to overflow a 50-byte buffer
- [ ] Find / Replace
- [ ] Spell checker (Tools) — the "no more proposals" case used to
      dereference NULL
- [ ] Print → print to PostScript file
- [ ] Open / Save As / New document dialogs
- [ ] Link and image insertion dialogs

## 6. Longer session

- [ ] Edit a real document of your own for 15–20 minutes: note any
      slowdown, flicker, lost keystrokes, caret misplacement, or crash
- [ ] Two documents open in tabs, switch between them while editing
- [ ] Quit (Ctrl+Q) exits cleanly (`echo $?` prints 0)

## Reporting

For each failure note: X11 or Wayland, the steps, what you expected, what
happened, and any terminal output (Amaya writes diagnostics to stderr).
