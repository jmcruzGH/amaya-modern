# amaya-modern

A modernised build of [Amaya 11.4.7](https://www.w3.org/Amaya/), the W3C's
WYSIWYG XHTML/MathML/SVG editor, ported to **Linux amd64 / Kubuntu 24.04**
with a CMake build system.

Original code © INRIA/W3C 1996–2013 by Irène Vatton, Vincent Quint, Laurent
Carcone and contributors.  
Port © 2026 J. Magalhães Cruz `<jmcruz@fe.up.pt>` — FEUP.

---

## What this repo contains

| Directory | Contents |
|---|---|
| `amaya/` | Application source (XHTML editor, CSS, HTTP) |
| `amaya/generated/` | Pre-generated `*APP.c` / `*.h` schema files (committed so you don't need to run the schema compilers) |
| `amaya/*.STR, *.PRS, *.TRA` | Pre-compiled binary schemas (`HTML.STR` etc.) |
| `thotlib/` | Thot rendering engine (document model, OpenGL display, wx UI) |
| `batch/` | Schema compiler source (`str`, `app`) and CMake rules |
| `compat/` | Compatibility shim headers (`wx3compat.h`) |
| `patches/` | Historical record of the original port (already applied) |
| `cmake/` | CMake helper files (`config.h.in`) |

---

## Prerequisites (Kubuntu 24.04 / Ubuntu 24.04)

```bash
sudo apt install \
  build-essential cmake git \
  libwxgtk3.2-dev wx-common \
  libgl-dev libglu1-mesa-dev \
  libfreetype-dev libfontconfig1-dev \
  libcurl4-openssl-dev libssl-dev libexpat1-dev \
  zlib1g-dev libjpeg-dev libpng-dev \
  libraptor2-dev \
  flex bison
```

(`libwxgtk3.2-dev` already includes wxGLCanvas support; there is no separate
`-gl-dev` package on 24.04. The build uses GTK 3, not GTK 2.)

---

## Build

The tree is already patched: no upstream checkout, `rsync` or patch step is needed.

```bash
git clone https://github.com/jmcruzGH/amaya-modern.git
cd amaya-modern
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j$(nproc) 2>&1 | tee build.log
./amaya/amaya            # or: ./amaya/amaya /path/to/file.html
```

The `patches/` directory is kept only as a historical record of how the port
was first produced; its changes are already part of the committed sources.

### Smoke test

`tools/smoke-test.sh` runs the freshly built binary under a virtual X server,
performs a short editing session on a local file, and checks the saved result.
See the comments at the top of the script.  For testing on a real desktop
session, see [`docs/TESTING.md`](docs/TESTING.md).

---

## Phased porting plan

### Phase 1 — wxWidgets 2.8 → 3.2 ✅
- `compat/wx3compat.h` force-included into every TU via CMake
- Renames all `wxEVT_COMMAND_*` → `wxEVT_*`, `DEFINE_EVENT_TYPE` → `wxDEFINE_EVENT`
- Fixes to `wxGLCanvas` construction, `SetCurrent()`,
  `GetContext()→GetGLContext()`, `ListBoxBook` event types
- Runtime fixes under wx 3.2 / GTK 3: glyph position overflow, GL context
  sharing, keyboard input (character corruption, arrows, AltGr), glyph baseline
- wx 3 defines `__WXDEBUG__` by default; Amaya's own debug code now uses
  `AMAYA_WXDEBUG`, set only for `CMAKE_BUILD_TYPE=Debug` (otherwise a
  developer trace window opened beside every Amaya window)
- Note: the shim hides deprecated wx 2.8 API usage rather than migrating it

### Phase 2 — GCC 13 warnings ✅ (error-class and memory-safety categories)
The build uses `-Wall` with **no** `-Wno-*` suppressions and **no**
`-fpermissive`.  All `.c` files are compiled as C++ (see "Open decisions").

| Category | Before | Now | Notes |
|---|---|---|---|
| errors hidden by `-fpermissive` | 5 | 0 | pointer/`'\0'` comparisons, `char`→`char*` |
| `-Wformat-overflow` | 37 | 0 | `sprintf` → `snprintf(buf, sizeof buf, …)` |
| `-Wformat-security` | 22 | 0 | `fprintf(f, s)` → `fprintf(f, "%s", s)` |
| `-Wstringop-truncation` | 91 | 39 | remaining sites verified safe (GCC false positives) or dead code |
| `-Wmaybe-uninitialized` | 27 | 0 | neutral initial values |
| `-Wint-to-pointer-cast` | 170 | 0 | explicit `(intptr_t)` (int-in-`void*` idiom, verified) |
| `-Wreturn-type`, `-Wnonnull`, `-Wmemset-elt-size`, `-Wsizeof-pointer-div`, `-Wuninitialized`, `-Wrestrict`, `-Waddress` | 19 | 0 | several were real bugs |
| `-Wmisleading-indentation` | 5 | 0 | indentation only |
| `-Wparentheses` / `-Wdangling-else` | 12 / 8 | 9 / 7 | 3 NULL dereferences + 1 dangling else fixed; rest correct |

Totals (clean build, unique warnings): **868 → 564**, 0 errors.
Remaining warnings are mostly `-Wswitch-outside-range` (noise),
`-Wunused-but-set-variable`, `-Wunused-result`, and the `-Wformat-truncation`
notes that mark the `snprintf` conversions ("may truncate", formerly "may
overflow").  See `git log` for the individual bugs fixed.

### Phase 3 — libwww → libcurl ⚠ partial (remote loading not working yet)
- `patches/curl/query.c`: full libcurl multi-handle replacement for `GetObjectWWW`,
  `PutObjectWWW`, `StopRequest`, `QueryInit/Close`
- All other libwww files (`AHTBridge.c`, `AHTInit.c`, `AHTMemConv.c`,
  `AHTFWrite.c`, `AHTEvntrg.c`, `answer.c`) replaced by linker stubs
- HTTP-only in this phase; HTTPS requires removing the protocol filter in `query.c`
- libcurl poll wired into wx event loop via `wxAmayaSocketEventLoop::SetCurlPoll()`
- **Known issues** (remote documents never load; local files are unaffected):
  `GetObjectWWW` does not fill in the caller's `outputfile` buffer (the libwww
  version generated a temp-file name there) and returns without calling the
  terminate callback when `fopen("")` fails; the poll timer is only started when
  a socket is registered, which libcurl never does; `AMAYA_SYNC` is ignored;
  no 401/authentication handling.

### Phase 4 — HTTPS, authentication (planned)
Remove the `strncmp(urlName, "http://", 7)` guard in `patches/curl/query.c`.
libcurl handles TLS natively; no other change needed.

### Phase 5 — Qt migration (future, optional)
Port `thotlib/dialogue/` from wxWidgets to Qt6, replacing `wxGLCanvas` with
`QOpenGLWidget`. The Thot rendering engine (`thotlib/view/`, `thotlib/document/`,
`thotlib/tree/`, `thotlib/editing/`) is unchanged — only the ~82 dialogue files
need porting.

---

## Open decisions

- **C compiled as C++.**  Every `.c` file in `amaya/` and `thotlib/` is
  compiled as C++ because `thot_gui_wx.h` declares C++ classes without
  `#ifdef __cplusplus` guards.  Since `-fpermissive` is gone, this is now a
  stable, strict configuration, and returning to C would require guarding
  those headers and re-checking every C/C++ boundary.  Recommendation: keep it.
- **`thotlib/editing/structcreation.c` (~line 3835)** compares two arrays
  (`pEl->ElAbstractBox == pLeaf->ElAbstractBox`).  This has always been false,
  also in Amaya 11.4.7, so the "inclusion" branch never selects the new
  element.  The intent was probably to compare the first view's box; changing
  it alters editing behaviour, so it is left as is.
- **libcurl layer** (Phase 3): see the known issues above; local files are
  not affected.

---

## Regenerating schema files

The `amaya/generated/*APP.c` and `amaya/*.STR` (and `*.PRS`, `*.TRA`) files are committed and
normally do not need regeneration. If you change a `.S` or `.A` schema file:

```bash
cd build
cmake --build . --target amaya_schemas
```

This builds the `amaya_str_compiler` and `amaya_app_compiler` host tools and
reruns them against the changed schema sources.

---

## Architecture notes

```
amaya/          Application layer (HTML parser, CSS, editor actions, HTTP)
  └── wxdialog/ wx dialog subclasses (28 files: Open, Save, Find, Prefs…)
thotlib/
  ├── document/ Document model, schema reader/writer, pivot format
  ├── tree/     Element tree, attributes, references
  ├── editing/  Undo, selection, structural commands
  ├── content/  Text buffers, search
  ├── view/     Box layout engine, OpenGL rendering (1 857 lines of GL)
  ├── presentation/ CSS/presentation schema matching
  ├── dialogue/ wx windows, frames, panels, canvas (AmayaCanvas = wxGLCanvas)
  ├── base/     Memory, registry, platform, message, app instance
  ├── image/    JPEG, PNG, GIF, XPM decoders
  └── unicode/  UTF-8/UTF-16 string helpers
batch/          Schema compilers (NODISPLAY, no wx/GL dep)
  ├── str.c     .S source → .STR binary structure schema
  └── app.c     .A application schema → *APP.c callback registration code
```

The rendering pipeline: `thotlib/view/buildboxes.c` (layout) →
`glwindowdisplay.c` (GL draw calls) → `AmayaCanvas` (wxGLCanvas wrapper) →
the wx event loop. The seam between the layout engine and the UI is the
`FrameTable[]` integer-indexed array of `ThotFrame` (= `AmayaFrame*`) entries.

---

## Licence

Original Amaya code: [W3C Software License](https://www.w3.org/Consortium/Legal/copyright-software)  
Port modifications: same licence.
