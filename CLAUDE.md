# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Valhalla is a 3D graphics engine written in Odin against Vulkan 1.4, intended to grow into a full
game. Graphics is one component of that game, not the whole project.

## House rules

### The engine is cross platform

Valhalla targets more than Windows. Do not reach for a platform API because it is the quickest
way to solve something. If a problem genuinely has no portable solution, every supported target
needs a real implementation — a Windows path plus empty stubs is not acceptable. Where a
platform needs nothing, say why in a comment so the empty body reads as a conclusion rather
than a gap.

Platform code goes in its own file using Odin's filename suffixes rather than `when ODIN_OS`
blocks: `Graphics_windows.odin` and `Graphics_darwin.odin` are selected implicitly, and
`Graphics_unix.odin` carries an explicit `#+build linux, freebsd, openbsd, netbsd`. Each defines
the same procedure, so exactly one exists per target.

`odin check src -target:<target>` is the check. It currently stops on `vendor:stb` missing
prebuilt non-Windows binaries, which is a toolchain gap rather than a code problem; to verify
platform files in isolation, copy them to a scratch package outside the repo with a stub `main`
and check that against each target. That also catches a missing or duplicated definition, which
is the main hazard of this layout.

### One file per component — do not split code up

Do **not** create new `.odin` files. When you add functionality, put it in the file that already
owns that component. `src/Graphics.odin` is large on purpose; size alone is never a reason to
split it.

If something genuinely warrants its own file, say so and wait — that call is the user's, not
yours. This has already been reversed once: the memory allocator, staging ring and descriptor
heap were each written as separate files and later folded back into `src/Graphics.odin`.

The sanctioned exception is platform code, which uses Odin's filename build tags
(`Graphics_windows.odin`, `Graphics_darwin.odin`, `Graphics_unix.odin`). Do not fold these back
into `Graphics.odin`.

Inside a file, organise with section banners instead:

```odin
// ===[ Device Memory ]=========================================================
```

`grep "^// ===\[" src/Graphics.odin` lists the sections. Add new code to the section it belongs
to; add a new section only if it is genuinely a new area of responsibility.

### Do not write comments

Do not write comments. Not explanatory ones, not "why" ones, not file headers. The code stands on
its own.

The only exception is the section banners described above, which are structure rather than prose.

## Task tracking

`README.md` holds the roadmap and task list. The roadmap describes large undertakings; the tasks
section breaks each one into checkable items. Keep both current: tick items off as they land, and
add new ones there rather than leaving TODO comments scattered in the source.

## Commands

```sh
odin build src --debug --linker:radlink -out:bin/valhalla.exe     # build
./bin/valhalla.exe ./demo/demo.project   # run (argument is the project file)
./bin/valhalla.exe ./demo/demo.project ./scenes/bench.scene   # optional scene override
```

There is no test suite, linter or build script. `odin build` is the only check; treat a clean
build plus a clean validation run as the bar.

### Running it for verification

The app is a GUI program, so a change is not verified until it has been run. Two things matter:

- Kill it and you skip `cleanupGraphics`, which is where the pipeline cache is saved, leak
  reporting runs, and teardown validation errors surface. Close the window instead
  (`Process.CloseMainWindow()` from PowerShell), or press **Ctrl+Q**, which is a clean exit that
  works even with an imgui text field focused, so shutdown actually executes.
- Validation output goes to **stderr**, ordinary logging to stdout. Check both.
- Never minimise or close the user's other windows to get a clean screenshot. To raise the app,
  use `BringWindowToTop` / `SetForegroundWindow` on its own `MainWindowHandle` and capture that
  window's rect; if something still occludes it, capture anyway and say so.

Validation layers and `SYNCHRONIZATION_VALIDATION` are enabled in `createInstance`, so
synchronisation mistakes are caught at runtime. A silent run is meaningful evidence; take it
seriously when it is not silent.

## Architecture

`src/Graphics.odin` holds the whole renderer. Everything below lives in it.

**Frame flow.** Command buffers are pre-recorded per pass, not re-recorded each frame.
`dirtyCommands: bit_set[CmdBufferIndex]` tracks which passes need re-recording; callers mark work
dirty through `markCommandsDirty` with `DIRTY_ALL`, `DIRTY_GEOMETRY` or an explicit set, so a
light change does not force the scene pass to re-record. Each pass owns a primary command buffer
and records its own barriers, so passes are independent.

The frame body lives in `tickFrame`, not in the loop itself. Dragging a window border or title
bar puts Win32 into a modal message loop where `glfwPollEvents` does not return, so three things
drive frames during a drag, and all of them are needed:

- the window refresh and framebuffer size callbacks, which fire only when something *changes*
- `installModalLoopTimer`, which covers the case the callbacks miss: holding a border still
  produces no messages at all. It lives in the per-platform `Graphics_*.odin` files:
  - `Graphics_windows.odin` subclasses the window proc and runs a timer between
    `WM_ENTERSIZEMOVE` and `WM_EXITSIZEMOVE`. It imports `core:sys/windows` directly, which is
    only possible because the file is never compiled on other targets.
  - `Graphics_darwin.odin` schedules an `NSTimer` through `core:sys/darwin/Foundation` and adds
    it for `NSRunLoopCommonModes`. AppKit's live resize runs the main run loop in
    `NSEventTrackingRunLoopMode`, which is one of those modes, so the timer keeps firing through
    the drag; the default mode alone would not. It sends
    `scheduledTimerWithTimeInterval:repeats:block:` via `intrinsics.objc_send` rather than the
    package's `Timer_scheduledTimerWithTimeIntervalRepeatsBlock`, which passes only two
    arguments to that three-argument selector and so drops the interval. Recheck that wrapper
    when Odin updates. **Untested** — written without a Mac to run it on.
  - `Graphics_unix.odin` is empty on purpose: X11 and Wayland are driven by configure events and
    `glfwPollEvents` returns throughout, so the callbacks already cover the drag.

  The macOS timer lives for the whole process, so `pollingEvents` (set around `glfwPollEvents`
  in `updateWindow`) tells a stalled modal loop apart from ordinary frames.
- a `ticking` guard, because `recreateSwapchain` can pump events itself via `glfw.WaitEvents`

`recreateSwapchain` must not tear down imgui. Nothing in its init depends on the swapchain
extent — only on the colour format, which does not change — and rebuilding the context on every
size change makes the overlay vanish while resizing.

The shadow pass uses multiview: one `CmdBeginRendering` per light with `viewMask` covering all
six cube faces, and `Light.slang` takes the face from `SV_ViewID`. Multiview view *i* maps to
layer *i* of the *attachment view*, so each light has its own six-layer view
(`shadowColourViews` / `shadowDepthViews`); destroy those before the images they came from. Do
not reintroduce `SV_RenderTargetArrayIndex` there — under multiview the layer is implied by the
view index and writing Layer as well is invalid.

Nothing called from `drawImgui` may recreate the swapchain directly. `drawFrame` has already
reset the current frame's fence by then, so `recreateSwapchain`'s wait over every in-flight fence
would never return. Set `swapchainDirty` instead; `drawFrame` handles it at the next frame
boundary, before any fence is reset.

`drawFrame` issues two submits: transform (compute queue), then Light/Scene/Imgui/PostProcess/
Present as one batch on the graphics queue. Ordering inside that batch comes from pipeline
barriers recorded in the passes themselves, not from semaphores — if you add or reorder passes,
the barriers are what keeps it correct.

imgui does not draw onto the scene. The Imgui pass renders into its own `R16G16B16A16_SFLOAT` UI
image (`ImageSlot.UiImage`), cleared to transparent, and `Imgui.slang` always outputs linear light,
so the image holds premultiplied coverage. PostProcess tonemaps the scene, composites
`ui.rgb + scene * (1 - ui.a)` and applies the single Gamma or PQ encode, so overlay blending is
the same in SDR and HDR. Imgui ends by moving the UI image to `GENERAL` for that compute read, and
PostProcess ends by moving ProcessedImage to `TRANSFER_SRC`. Present is a small command buffer,
re-recorded every frame because it depends on `imageIndex`, that blits ProcessedImage to the
swapchain image and transitions it for present.

The post-process and UI images are sized to `outputCapacity`, not `swapchain.extent`: the largest
of the swapchain and every connected monitor's video mode, grown only when the window outgrows
it. Anything that bounds work by the output must use `swapchain.extent` (PostProcess takes it as
`outputExtentX/Y`), never the image's own dimensions.

**Descriptors.** Uses `VK_EXT_descriptor_heap` in its **untyped** model; there are no descriptor
sets, pools, set layouts or `VkPipelineLayout` objects anywhere, and no set/binding mappings.
Two heaps (resource and sampler) are bound per command buffer by device address, and shaders
reach them through `ResourceHeapEXT`/`SamplerHeapEXT` builtins.

Shaders declare no bindings. Each pass's push constants start with a `resources: HeapIndices`
block of plain integer indices; `HeapIndices` exposes each resource as a `property` that builds a
`DescriptorHandle<T>` from the matching index, so shaders read
`pushConstants.resources.Lights[i]`. Properties carry no storage, so the block is exactly one
uint per resource (currently 16, 64 bytes).

std430 sizes that block at its used bytes and aligns whatever follows it by *that member's* own
rule. At 64 bytes everything after it sits at 64, but at an odd count — 15 fields, 60 bytes — a
`u32` after it sits at 60 while a `float2` sits at 64. Odin's `Vec2` is `[2]f32` and needs only 4,
which is the one place the two sides disagree — hence `ShaderVec2`, an 8-aligned pair used
for Imgui's `scale` and `translate`. Align the *type*, not the struct: `#align` on a push constant
struct does not move interior fields, and `#min_field_align(8)` pushes the trailing `u32`s out of
place too. A mismatch here is invisible at runtime — the pushed range still covers what the shader
reads, so validation stays silent and the shader just reads the neighbouring field — so `#assert`s
below the push constant structs pin every offset at compile time.

Call sites use a bare `Resources.Vertices[i]`. That comes from `DECLARE_RESOURCES(pushConstants)`
in `Resources.slang`, which each pass **`#include`s** — it must be `#include`, not `import`,
because the macro forwards to that file's own push constant and Slang's imports do not carry
preprocessor definitions. It expands to an empty struct plus a global instance, so it costs
nothing.

`HeapIndices` in `Buffers.slang` mirrors the Odin struct of the same name. Adding a resource
means adding a field to *both* structs in the same order, a property on `HeapIndices`, a
forwarding property in the `DECLARE_RESOURCES` macro, and a slot to the matching enum. Texture
and sampler properties live in `Textures.slang` via `extension HeapIndices`.

Consequences worth knowing before touching pipelines, buffers or shaders:

- `Shaders.odin` must set the `spvDescriptorHeapEXT` capability on the target
  (`slang.find_capability` + a `Compiler_Option_Entry` of `.Capability`). Without it Slang silently falls
  back to descriptor-indexing and the pipelines fail validation. The `+capability` suffix on a
  profile string does **not** work through the API.
- `VK_KHR_shader_untyped_pointers` and `shaderUntypedPointers` are required, because the untyped
  heap lowers to `OpTypeUntypedPointerKHR`.
- `VK_PIPELINE_CREATE_2_DESCRIPTOR_HEAP_BIT_EXT` requires `layout == VK_NULL_HANDLE`, which is
  why push constants are `vkCmdPushDataEXT` rather than `vkCmdPushConstants2`.
- Every buffer is created with `SHADER_DEVICE_ADDRESS` and every allocation carries
  `VkMemoryAllocateFlagsInfo{DEVICE_ADDRESS}`, because heap writes describe buffers by address.
- Heap indices in push data are **absolute** (`bufferSlotIndex`, `imageSlotIndex`,
  `textureSlotIndex`), scaled by that descriptor type's own size — the stride is
  `OpConstantSizeOfEXT`, so each region must start on a multiple of its descriptor size.
- Scene textures keep their source resolution; each is its own image, free-list allocated from the
  heap's texture region up to `MAX_HEAP_TEXTURES`. Each one takes **two** slots, not one: the image
  is created `MUTABLE_FORMAT` and viewed both as `R8G8B8A8_SRGB` and as `R8G8B8A8_UNORM`, because
  whether a texture wants the sRGB decode depends on the slot it is read through, not on the file.
  `TEXTURE_SLOT_IS_LINEAR` maps each `TextureIndex` to a view, and `updateTextureIndexBuffer`
  writes the matching heap index. A new `TextureIndex` must be added there too — colour data is the
  exception, not the default.
- Samplers are not `VkSampler` objects; `vkWriteSamplerDescriptorsEXT` takes a
  `VkSamplerCreateInfo` directly.
- There is no fixed-function vertex input. Pipelines declare zero bindings and attributes;
  vertex shaders pull from `Resources.Vertices`. Index with
  `SV_VertexID + SV_StartVertexLocation` — Slang's `SV_VertexID` follows HLSL and excludes the
  draw's `vertexOffset`, which the buffer *is* indexed by.
- `Vertex`'s manual padding is std430 alignment for that storage-buffer read, not fixed-function
  alignment. `size_of(Vertex)` is 112 and must stay identical to the shader struct.

**Memory.** A hand-rolled sub-allocator, deliberately not VMA. First-fit with coalescing, one
`vkAllocateMemory` block per memory type, persistent mapping for host-visible blocks, dedicated
allocations for large or driver-requested resources. Linear and optimal-tiled resources never
share a block, which sidesteps `bufferImageGranularity` by construction — preserve that
separation. `memoryAllocatorReportLeaks` runs at shutdown.

Uploads go through a staging ring: one persistently mapped buffer paced by a timeline semaphore,
accumulating into a single command buffer. `stagingWait` before anything reads an uploaded
resource. `beginSingleTimeCommands`/`endSingleTimeCommands` still exist but are only for
one-off layout transitions; they block, so do not use them for uploads.

**Other files.** `Main.odin` owns the `globals` struct and the frame loop. `Files.odin` handles
scene/model/texture serialisation (assimp). `Shaders.odin` compiles `.slang` sources at runtime through the `slang/`
bindings, which wrap Slang's COM-lite interfaces as plain Odin procs (`slang.load_module`,
`slang.release`, ...) — there is no C shim and no vtable calls at the call site;
`IO.odin` hot-reloads them through `updatePipelineShaders`, which dirties only the affected pass.
`UI.odin` is the imgui editor. `Debug.odin` has the log wrappers and the Vulkan debug-utils
helpers (`vkNameObject`, `vkBeginLabel`, `vkEndLabel`) — name new long-lived objects in
`nameCoreObjects`.

## Odin notes

- `#+feature using-stmt` is per-file and must be the first line of any file using `using`.
- `@(private = "file")` is the default for anything not needed outside its file. Because the
  renderer is one file, most of it is file-private; keep it that way.
- Vulkan bindings are `vendor:vulkan`, which already loads function pointers via
  `vk.load_proc_addresses` — volk and similar loaders are unnecessary.
- `logf`/`log` in `Debug.odin` wrap `core:log` and panic on `.Fatal`.

## Conventions

- A **project file** is the runtime argument (`./demo/demo.project`), not a directory. The app
  chdirs to the directory holding it, so every path inside the file stays relative to the file.
  `loadProject` reads it into `globals.project` before anything else runs.
- `SCENE_PATH()`, `RESOURCE_PATH()`, `SHADERS_PATH()` and `ASSETS_PATH()` are **procedures now,
  not constants** — they read `globals.project`. They can't be concatenated at compile time, so
  use `projectPath(dir, file)` to join, and `projectPathC` where a C API needs a cstring.
- The engine can only **load** a project. Creating one is `tools/projectgen`; do not add project
  authoring to the engine. Both tools import the engine's `ProjectData` so the format has one
  definition.
- A project file supplies its own data in full. Do **not** add fallbacks for unset fields — the
  engine infers nothing, and `loadProject` rejects a project that leaves a required field blank.
  Sensible defaults belong in `projectgen`, which bakes them into the file it writes, so what the
  engine reads is always explicit.
- Machine state lives in the project's `configPath` (`CONFIG_PATH()`), which is gitignored and
  created at startup if missing: `imgui.ini`, `pipeline_cache.bin` and `user.settings`. Nothing
  per-machine goes in the project directory itself.
- `user.settings` (`UserSettings` in `Files.odin`: `RenderSettings`, window geometry, camera
  speeds) is the **one sanctioned default**. When it is missing or from another format version,
  the engine uses `defaultUserSettings()`, because the engine writes that file itself — it is
  not authored project data. It is loaded after `loadProject` and saved at shutdown, so it too
  depends on a clean exit.
- refdisk reads only its own tag (`refdisk:"ignore"`) and imreflect reads only
  `imrefl:"..."`. Hiding a field from the editor does not drop it from a file, and vice versa.
- `ProjectData.version` is the first field on purpose. refdisk is positional with no header, so
  offset 0 is the only place a version can be read before the rest of the layout is trusted.
  Do **not** bump `PROJECT_FORMAT_VERSION` (or any other `*_FORMAT_VERSION`) yet: there is no
  migrator to upgrade old files, so every version stays at 1 until one exists. When a struct
  changes before then, regenerate the affected files instead.
- `docs/`, `pipeline_cache.bin` and `config/` are gitignored.
- Commit only when asked.
