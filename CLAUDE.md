# CLAUDE.md

Valhalla is a graphics package for Odin on Vulkan 1.4, intended to grow into a full game. `src/`
(package `Valhalla`) covers graphics, windows and input only; imgui (`src/imgui`, package
`Valhalla_ImGui`) sits beside it and Valhalla never imports it. `examples/` are ordinary clients.

Pending work is tracked in `TODO.md`: tick items off as they land and add new ones there rather than
leaving TODO comments in the source.

## House rules

### The engine is cross platform

Do not reach for a platform API because it is the quickest way to solve something. If a problem has no
portable solution, every supported target needs a real implementation; a Windows path plus empty
stubs is not acceptable. Where a platform needs nothing, say why in a comment so the empty body reads as
a conclusion rather than a gap.

Platform code goes in its own file using Odin's filename suffixes, not `when ODIN_OS` blocks:
`IO_windows.odin` and `IO_darwin.odin` are selected implicitly, and `IO_unix.odin` carries
`#+build linux, freebsd, openbsd, netbsd`. Each defines the same procedures, so exactly one exists per
target. Check them with `odin check src -no-entry-point -target:<target>`; where that stops on a
toolchain gap (`vendor:stb` has no prebuilt non-Windows binaries), copy the platform files to a scratch
package outside the repo with a stub `main` and check that against each target.

### Do not create files

Do not create new `.odin` files. Add code to the file that owns that component (`Device`, `Memory`,
`Heap`, `Window`, `IO`, `Surface`, `Buffer`, `Image`, `Sampler`, `Shader`, `Workload`); size is never a
reason to split one. If something genuinely warrants its own file, say so and wait: that is the user's
call. Inside a file, organise with section banners:

```odin
// ===[ Device Memory ]=========================================================
```

### Do not write comments

No explanatory comments, no "why" comments, no file headers. Section banners are the only exception.

## Commands

```sh
odin check src -no-entry-point        # the package
odin run examples/<name>              # an example, from the repository root
```

There is no test suite or linter. A clean build plus a clean run is the bar.

## Verifying a change

A change is not verified until something using it has run.

- The validation layer, with synchronisation validation, is always on. Its output goes to **stderr**
  and ordinary logging to stdout; check both. A silent run is meaningful evidence.
- Exit cleanly (close the window, or `Process.CloseMainWindow()` from PowerShell). Killing the process
  skips `shutdown`, which is where the memory leak report runs and teardown validation errors appear.
- **Never drive the real mouse or keyboard** (`SetCursorPos`, `mouse_event`, `SendKeys`, posted
  window messages), and never minimise, close or raise the user's windows; the user works on the same
  machine. To test input, call Valhalla's `inject_*` procs, which run a window's installed callbacks
  exactly as GLFW events would.

## Odin notes

- `@(private = "file")` is the default for anything not needed outside its file; `@(private)` for
  what other files in the package need.
- Vulkan is `vendor:vulkan`, which loads function pointers itself; no volk or similar loader.
- Valhalla logs through `core:log` only. The host sets `context.logger` before `init`, which captures
  the context for GLFW and Vulkan callbacks.

## Conventions

- Commit only when asked, directly on `main`.
- `docs/`, `libs/`, `bin/` and `projs/` are gitignored.
