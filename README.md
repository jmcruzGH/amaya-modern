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
| `amaya/schemas/` | Pre-compiled binary structure schemas (`HTML.STR` etc.) |
| `thotlib/` | Thot rendering engine (document model, OpenGL display, wx UI) |
| `batch/` | Schema compiler source (`str`, `app`) and CMake rules |
| `compat/` | Compatibility shim headers (`wx3compat.h`) |
| `patches/` | Apply scripts and libcurl replacement sources |
| `cmake/` | CMake helper files (`config.h.in`) |

---

## Prerequisites (Kubuntu 24.04 / Ubuntu 24.04)

```bash
sudo apt install \
  build-essential cmake git \
  libwxgtk3.2-dev libwxgtk-gl3.2-dev wx-common \
  libgl-dev libglu1-mesa-dev \
  libfreetype-dev libfontconfig1-dev \
  libgtk2.0-dev libglib2.0-dev \
  libcurl4-openssl-dev \
  libssl-dev libexpat1-dev \
  zlib1g-dev libjpeg-dev libpng-dev \
  libraptor2-dev \
  flex bison
```

---

## Build

```bash
# 1. Clone this repo
git clone https://github.com/jmcruzGH/amaya-modern.git
cd amaya-modern

# 2. Clone the original Amaya source alongside it
git clone --depth=1 https://github.com/w3c/Amaya-Editor.git ../Amaya-Editor

# 3. Merge original source into this repo (patches will be applied on top)
rsync -a --exclude='.git' --exclude='WindowsWX' ../Amaya-Editor/ ./

# 4. Apply all patches (Phases 1–3)
bash patches/apply-patches.sh

# 5. Configure and build
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j$(nproc) 2>&1 | tee build.log

# 6. Check for errors
grep -c 'error:' build.log && echo "errors — see build.log" || echo "clean build"

# 7. Run
./amaya
```

---

## Phased porting plan

### Phase 1 — wxWidgets 2.8 → 3.2 ✅
- `compat/wx3compat.h` force-included into every TU via CMake
- Renames all `wxEVT_COMMAND_*` → `wxEVT_*`, `DEFINE_EVENT_TYPE` → `wxDEFINE_EVENT`
- `patches/apply-patches.sh`: fixes `wxGLCanvas` constructor, `SetCurrent()`,
  `GetContext()→GetGLContext()`, `ListBoxBook` event types

### Phase 2 — GCC 13/14 compatibility ✅
- Global flags: `-Wno-implicit-function-declaration`, `-Wno-incompatible-pointer-types`,
  `-fno-strict-aliasing`, `-fpermissive` (C++ only)
- `GL_CLAMP → GL_CLAMP_TO_EDGE` in `glwindowdisplay.c`
- `WX_GL_NOT_ACCELERATED` removed from `AmayaApp.cpp`
- `static_cast` fix in `base64.cpp`

### Phase 3 — libwww → libcurl ✅
- `patches/curl/query.c`: full libcurl multi-handle replacement for `GetObjectWWW`,
  `PutObjectWWW`, `StopRequest`, `QueryInit/Close`
- All other libwww files (`AHTBridge.c`, `AHTInit.c`, `AHTMemConv.c`,
  `AHTFWrite.c`, `AHTEvntrg.c`, `answer.c`) replaced by linker stubs
- HTTP-only in this phase; HTTPS requires removing the protocol filter in `query.c`
- libcurl poll wired into wx event loop via `wxAmayaSocketEventLoop::SetCurlPoll()`

### Phase 4 — HTTPS, authentication (planned)
Remove the `strncmp(urlName, "http://", 7)` guard in `patches/curl/query.c`.
libcurl handles TLS natively; no other change needed.

### Phase 5 — Qt migration (future, optional)
Port `thotlib/dialogue/` from wxWidgets to Qt6, replacing `wxGLCanvas` with
`QOpenGLWidget`. The Thot rendering engine (`thotlib/view/`, `thotlib/document/`,
`thotlib/tree/`, `thotlib/editing/`) is unchanged — only the ~82 dialogue files
need porting.

---

## Regenerating schema files

The `amaya/generated/*APP.c` and `amaya/schemas/*.STR` files are committed and
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
