# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Valhalla is a 3D graphics engine written in Odin against Vulkan 1.4, intended to grow into a full
game. Graphics is one component of that game, not the whole project.

## House rules

### One file per component — do not split code up

Do **not** create new `.odin` files. When you add functionality, put it in the file that already
owns that component. `src/Graphics.odin` is large on purpose; size alone is never a reason to
split it.

If something genuinely warrants its own file, say so and wait — that call is the user's, not
yours. This has already been reversed once: the memory allocator, staging ring and descriptor
heap were each written as separate files and later folded back into `src/Graphics.odin`.

Inside a file, organise with section banners instead:

```odin
// ===[ Device Memory ]=========================================================
```

`grep "^// ===\[" src/Graphics.odin` lists the sections. Add new code to the section it belongs
to; add a new section only if it is genuinely a new area of responsibility.

### Do not write comments

Default to no comments. The code should read on its own, and a comment that restates it is noise
to be removed.

Comment only where a reader would otherwise be genuinely stuck, and then explain *why* rather
than *what*:

- a non-obvious constraint the code is obeying (spec requirements, hardware limits, driver
  behaviour)
- a deliberate choice that looks wrong until explained
- an ordering or lifetime dependency that is invisible locally

```odin
// Must be per swapchain image rather than per frame in flight: nothing signals when the
// presentation engine is finished with the semaphore.
presentReady: []vk.Semaphore,
```

Do not add file headers, section prose, banner-comment explanations, or restatements of a
function's name.

## Commands

```sh
odin build src --debug --linker:radlink -out:bin/valhalla.exe     # build
./bin/valhalla.exe ./demo                # run (argument is the project directory)
```

There is no test suite, linter or build script. `odin build` is the only check; treat a clean
build plus a clean validation run as the bar.

### Running it for verification

The app is a GUI program, so a change is not verified until it has been run. Two things matter:

- Kill it and you skip `cleanupGraphics`, which is where the pipeline cache is saved, leak
  reporting runs, and teardown validation errors surface. Close the window instead
  (`Process.CloseMainWindow()` from PowerShell) so shutdown actually executes.
- Validation output goes to **stderr**, ordinary logging to stdout. Check both.

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

`drawFrame` issues two submits: transform (compute queue), then Light/Scene/PostProcess/Imgui as
one batch on the graphics queue. Ordering inside that batch comes from pipeline barriers recorded
in the passes themselves, not from semaphores — if you add or reorder passes, the barriers are
what keeps it correct.

**Descriptors.** Uses `VK_EXT_descriptor_heap`; there are no descriptor sets, pools, set layouts
or `VkPipelineLayout` objects anywhere. Two heaps (resource and sampler) are bound per command
buffer by device address. Shaders are unmodified and still declare `set`/`binding`: the extension's
*typed* model maps those to heap offsets via `VkShaderDescriptorSetAndBindingMappingInfoEXT`,
chained into each **shader stage's** `pNext` (not the pipeline's — validation rejects that).

Consequences worth knowing before touching pipelines or buffers:

- `VK_PIPELINE_CREATE_2_DESCRIPTOR_HEAP_BIT_EXT` requires `layout == VK_NULL_HANDLE`, which is
  why push constants are `vkCmdPushDataEXT` rather than `vkCmdPushConstants2`.
- Every buffer is created with `SHADER_DEVICE_ADDRESS` and every allocation carries
  `VkMemoryAllocateFlagsInfo{DEVICE_ADDRESS}`, because heap writes describe buffers by address.
- Descriptor slots are a static table (`BufferSlot`, `ImageSlot`, `SamplerSlot`) matching the
  set/binding pairs the shaders declare. Adding a binding means adding a slot and a mapping.
- Samplers are not `VkSampler` objects; `vkWriteSamplerDescriptorsEXT` takes a
  `VkSamplerCreateInfo` directly.

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
scene/model/texture serialisation (assimp). `Shaders.odin` compiles `.slang` sources at runtime;
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

- The project directory is a runtime argument (`./demo`), and the app runs with it as its working
  directory. Paths in `Main.odin` (`SCENE_PATH`, `SHADERS_PATH`, ...) are relative to it.
- `docs/` and `pipeline_cache.bin` are gitignored.
- Commit only when asked.
