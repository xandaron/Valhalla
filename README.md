# Valhalla Graphics Engine

Valhalla is a 3D graphics rendering demo showcasing modern graphics techniques and real-time rendering capabilities. This project serves as a demonstration of graphics programming concepts and rendering features.

## Features

- Rigged 3D model and animation support
- Multiple light sources
- Custom shaders
- Shadow mapping
- Real-time rendering
- Bindless rendering via `VK_EXT_descriptor_heap`, vertex pulling, multiview shadow maps
- Cross-platform (Windows and Linux; macOS is written but unverified)
- Hot-reloadable shaders

## Project Structure

- `src/` &mdash; Core graphics engine implementation
- `demo/` &mdash; The project directory passed to the executable at runtime
  - `demo/shaders/` &mdash; Slang shaders, compiled at startup and hot-reloadable
  - `demo/assets/` &mdash; Models and textures
  - `demo/scenes/` &mdash; Serialised scenes
  - `demo/scene_components/` &mdash; Model and texture descriptors referenced by scenes

## Getting Started

### Prerequisites

- [Odin](https://odin-lang.org/docs/install/) programming language
- [VulkanSDK](https://vulkan.lunarg.com/) (recommended for development)

### Setup

#### Linux

- Install [Assimp](https://github.com/assimp/assimp/releases/tag/v6.0.1) as a shared library.
- Install GLFW 3.4+ (older versions may cause crashes).

Clone the repository and build the demo program:

```sh
git clone https://github.com/xandaron/valhalla.git
cd valhalla
odin build src -out:bin/valhalla.exe
./bin/valhalla.exe ./demo/demo.project
```

The argument is the project directory, and the app runs with it as its working directory.

## Roadmap

Large undertakings, roughly in the order they are likely to be tackled. Each one is broken into
checkable work in [Tasks](#tasks).

| # | Undertaking | State |
| --- | --- | --- |
| 1 | **Modern Vulkan foundations** — bindless descriptors, hand-rolled allocator, vertex pulling, multiview shadows, host image copy | Complete |
| 2 | **Colour correctness** — colour space handling and light falloff | Partly done |
| 3 | **Reflection-driven editor** — inspectors are driven by `imreflect`; only engine behaviour stays hand-written | Complete |
| 4 | **Own imgui backends** — replace the vendored Vulkan and GLFW integrations to get control over colour, resources and callbacks | Not started |
| 5 | **Normal mapping** — tangent frame and linear sampling are fixed; no debug view or demo asset that exercises a real normal map | Partly done |
| 6 | **Light types** — only point lights exist; directional and spot lights are missing | Not started |
| 7 | **Shadow quality and cost** — per-face culling, filtering, cascades for directional lights | Partly done |
| 8 | **Asset and shader pipeline** — shaders are hardcoded at startup; buffers are allocated one per purpose | Not started |
| 9 | **Renderer performance** — buffer consolidation, resize allocation churn, pipeline state objects | Partly done |
| 10 | **Platform coverage** — macOS is written but unrun; Linux cannot be checked end to end | Blocked |
| 11 | **Raytracing** | Not started |
| 12 | **Test content** — procedurally generated scenes and assets that exercise the renderer, and the generator that produces them | Partly done |
| 13 | **Project files** — the engine takes a project file rather than a directory, and tooling creates them | Partly done |

## Tasks

### 1. Modern Vulkan foundations — complete

- [x] Hand-rolled device memory sub-allocator: first-fit with coalescing, persistent mapping,
      dedicated allocations for large or driver-requested resources
- [x] Persistent staging ring paced by a timeline semaphore
- [x] `VK_EXT_descriptor_heap` in its untyped model; no descriptor sets, pools, layouts or
      `VkPipelineLayout` anywhere
- [x] Native-resolution textures with free-list heap slots
- [x] Vertex pulling; no fixed-function vertex input
- [x] Pre-transformed positions so the shadow pass reads 16 bytes rather than 76
- [x] Dynamic viewport and scissor
- [x] Aspect-correct presentation with black bars when the render target and window disagree
- [x] Multiview shadow mapping: one draw per light instead of six
- [x] Device feature audit — seven features and one extension removed
- [x] Host image copy for textures — no staging buffer, no barriers, no queue submission
- [x] Memory priority and pageable device-local memory
- [x] Present fences (`VK_EXT_swapchain_maintenance1`) — present-wait semaphores are now per
      frame in flight rather than per swapchain image
- [x] Remaining legacy entry points replaced: `vkMapMemory2`, `vkUnmapMemory2`,
      `vkBindBufferMemory2`, `vkBindImageMemory2`

### 2. Colour correctness

- [x] Fix the double gamma encode. Albedo textures are `R8G8B8A8_SRGB`, so `Sample` already
      returns linear, but `Scene.slang` re-encoded with `pow(x, 1/2.2)` and `PostProcess.slang`
      encoded again — output was `linear^(1/4.84)`, which is what washed SDR out. Lighting now
      runs in linear with a single display encode at the end
- [x] Runtime HDR toggle, including reselecting the surface format. `HDR_DEFAULT` is only a
      starting value. `setHDREnabled` cannot recreate the swapchain itself — it runs inside
      `drawImgui`, by which point `drawFrame` has reset the current frame's fence, so
      `recreateSwapchain`'s `waitAll` over every in-flight fence would deadlock. It sets
      `swapchainDirty` and `drawFrame` acts on it at the next frame boundary
- [x] Real HDR10 output — `PostProcess.slang` now applies the ST 2084 (PQ) transfer function and
      a Rec.709 to Rec.2020 primaries conversion instead of reusing the SDR gamma path
- [x] **Physically based point lights.** `dropoff` is gone and lights are specified in
      **lumens**. An isotropic source of flux F has intensity `F / 4pi`, giving illuminance
      `F / (4pi d^2)`, and a Lambertian surface reflects `albedo * E * cos(theta) / pi` — so the
      shader accumulates `lumens * cos(theta) / (4 pi^2 d^2)`. Distance squared is clamped at
      the bottom to stand in for the light having physical size, since a true point source
      diverges at its own position. For reference, 800 lm is a 60 W-equivalent bulb and 1600 lm
      a 100 W equivalent
- [x] Migrate the existing scene files. `PointLight` is serialised positionally with no version
      field, so dropping a `f32` shifts everything after it and the old files would have
      misparsed into garbage. Migrated with a temporary dual-struct pass (`SceneDataV1`) rather
      than by editing the binaries; `brightness` was converted at `x355`, which is the factor
      that reproduces the old intensity at 3 units and lands the demo lights near a 100 W bulb
- [ ] **The imgui overlay is not transfer-function aware.** It renders into ProcessedImage
      *after* PostProcess has already encoded, and writes its raw [0,1] values with no
      conversion. In SDR that happens to be consistent. In HDR it is not: scene paper white
      encodes to about 0.58 in PQ, while imgui white writes 1.0, which PQ defines as 10000 nits.
      The editor will be searingly bright against the scene. Blocked on roadmap 3 — the vendored
      backend has no notion of a target colour space, and owning it is the clean fix
- [x] Verify HDR against an actual HDR display and tune paper white (default 200 nits, now a
      runtime slider in Settings rather than a constant)
- [x] Removed the `drawLights` overlay entirely — it was unreachable, and its
      `(0.5 * 0.5) / colour` was unbounded as a pixel approached black. It was also the only
      implicit-LOD `Sample` in a compute shader, so deleting it retired
      `computeDerivativeGroupQuads` and `VK_KHR_compute_shader_derivatives` as well. A light
      gizmo wants a real solution, not a reciprocal in the post-process pass
- [x] Light gizmos. An instanced camera-facing quad per light, generated from `SV_VertexID` with
      no vertex or index buffer, drawn at the end of the Scene pass inside the same rendering
      instance. Sharing the scene's depth buffer with `depthWrite` off gives real per-fragment
      occlusion, which is what `drawLights` was faking with a manual depth compare, and keeping
      it out of the post-process pass means it is not subject to the display transfer function.
      World-sized and additive, with a blown core and a soft halo so it reads as an emitter.
      Toggle and radius live in Settings
- [ ] Gizmo picking — the billboards are real geometry, so clicking one to select its light is
      now feasible
- [x] Ambient light adds rather than acting as a floor. It is an illuminance arriving uniformly
      from all directions, so it contributes `E / pi` exactly as the point lights do, instead of
      `max(cumulative, ambient)`. The editor range widened from 0-1 to 0-10 to suit
- [x] Re-tuned the demo scenes. Both were authored against the old clamped falloff, which held
      everything within `dropoff + 1` units at full intensity — `knight.scene` had its light
      0.5 units from the model's face, so under real inverse-square the helmet blew out while
      the torso went black. Moved the key lights back and up (knight to `(2, 3, -3)` at 800 lm,
      lights to `(2, 3, -4)` at 1600 lm) and raised knight's ambient from 0.01 to 0.3. Checked
      in SDR, since HDR captures are not representative

### 3. Reflection-driven editor — complete

`imreflect` is already vendored and currently unused. It walks any Odin value with `core:reflect`
and emits imgui widgets for it — `draw_value(name, value: any)` handles every type kind, including
nested structs, slices, dynamic arrays, maps, enums, bit sets, unions, matrices and quaternions.
`src/UI.odin` is 992 lines with 38 hand-placed widgets, each naming a field that reflection could
find on its own, and every new field on `PointLight` or `Camera` currently means editing the
inspector by hand.

Four changes were needed in `imreflect` itself before any of this could work; it is a package we
maintain, so they were made there rather than worked around.

- [x] **Make `draw_value` report whether it edited anything.** Every `draw_*` now returns
      `changed: bool` and aggregates over children. imgui already returns this per widget and the
      package was discarding it, which left a caller no way to tell an edit from a repaint. This
      is what answers the dirty-signal question below
- [x] **Settle the imgui naming mismatch.** `imreflect` called `imgui.Gui_TreeNode` while the
      bindings of the day exposed those procs unprefixed, so the package could not compile against
      this project at all. Resolved from the binding side when it was swapped to dcimgui: the
      `Gui_` prefix was stripped from all 1008 procs, each keeping an explicit
      `@(link_name="ImGui_X")` because the foreign block's `link_prefix="Im"` would otherwise have
      resolved them to symbols that do not exist
- [x] **Handle `Fixed_Capacity_Dynamic_Array`**, a type kind newer than the package. Its elements
      are stored inline with the length after them, so it reads through `len_offset` rather than a
      `Raw_` header
- [x] **Draw 2 to 4 component numeric arrays inline.** A `Vec3` is an array of three floats, which
      reflected as a collapsible node with three rows — a bad trade for the most common type in a
      3D editor. They now render as one `DragScalarN` row, matching the hand-written `DragFloat3`
- [x] Light and camera inspectors now come from `ImRefl.draw_value`
- [x] Objects, models, textures and scene settings. `flatten` lets the reflected fields and the
      hand-written pickers share one tree node instead of the pickers hanging off the end
- [x] `flatten` (was `Using_Flatten`) draws a struct's fields inline rather than behind its own
      tree node. It is still set automatically for an anonymous `using _` field, but it is now a
      tag any struct can carry and a flag any caller can pass
- [x] **Tags so reflection can describe the data rather than the editor working around it:**
      `euler` draws a quaternion as XYZ degrees, applying a delta to the existing rotation rather
      than rebuilding from the displayed angles (Euler extraction is not injective, so rebuilding
      makes the numbers jump mid-drag near a pole); `colour` routes a 3 or 4 component float
      vector to a colour picker; `normalized` renormalises a vector after an edit; and
      `min=`/`max=`/`speed=` give a field a range. Bounds are values rather than flags, so
      `Draw_Flags` became `Draw_Info{flags, min, max, speed}` threaded through every draw proc
- [x] **Draw the line at engine behaviour.** Hooks and reference tags were both considered and
      rejected: reflection should describe data, and anything that changes engine state stays
      hand-written. `modelIdx`, `instanceIdx`, `textureIdxs` and `attachment` are tagged `ignore`
      because none of them is a plain assignment — changing a model resizes `textureIdxs` and the
      animation state, and `attachment.targetIdx`/`bindpointIdx` index `scene.objects` and the
      model's bindpoints with only a `>= 0` guard, so a free-form integer reads out of bounds
- [ ] Settings stays hand-written, and not because of a reflection limit: `GraphicsData` mixes six
      settings fields with about forty Vulkan handles, so it wants the settings struct that the user
      settings file under 13 produces anyway. Conditional disabling (gamma in HDR, paper white,
      gizmo radius) needs no new feature — `Read_Only` can be passed at the call site
- [x] A `label=` tag, so a field can read as "Near plane" rather than `near`. Like the flags it
      describes one field, so it is cleared before descending instead of relabelling every child.
      Values are comma separated, so a label cannot contain a comma
- [x] Adopt the `imrefl:"..."` struct tags. **The two consumers disagreed on vocabulary:** `refdisk`
      accepted `ignore` and `padding`, `imreflect` accepted only `padding`, so an `ignore` tag
      silently hid a field from serialisation while still drawing it. `padding` is now dropped from
      both packages and `ignore` is the single spelling; `Draw_Flag.Padding` became `.Ignore` to
      match. `Scene.vertices`, `Scene.indices` and `Scene.buffers` are tagged, as are `Model.meshes`
      and `Model.skeleton`
- [x] Decide how edits signal the renderer. `sceneEdited` rebuilds everything when `draw_value`
      reports a change — deliberately blunt, but it only fires on frames where a value actually
      changed, which is only knowable because `draw_value` now returns that. Narrow it per field
      if it ever shows up in a profile
- [ ] Keep hand-written controls where the widget triggers behaviour rather than editing data —
      the HDR toggle must call `setHDREnabled` for the swapchain rebuild, and "New Scene" and
      the shader reload are actions, not fields
- [ ] Check what reflection exposes that should stay hidden: `Scene` holds `buffers: SceneBuffers`
      full of Vulkan handles, and `Model` holds vertex data. Those want `padding`/`ignore` tags
      before anything walks a whole `Scene`

### 4. Own imgui backends

Replace `imgui_impl_vulkan` and `imgui_impl_glfw` with integrations we own. The vendored ones are
fine in isolation, but they each fight a decision made elsewhere in the engine.

- [ ] **Vulkan backend.** It creates its own `VkDescriptorPool`, `VkPipelineLayout`, descriptor
      sets and sampler — every object type the renderer deliberately removed when it moved to
      `VK_EXT_descriptor_heap`. Ours should draw the UI through the resource heap like everything
      else, so the claim that there are no descriptor sets anywhere becomes true again.
- [ ] **Transfer-function aware output.** The reason this became urgent: the backend writes raw
      [0,1] values into whatever target it is given, with no idea the buffer is PQ-encoded. Owning
      it means the UI can be composited before the display transform, or encoded to match. Fixes
      the blown-out editor in HDR (see roadmap 2).
- [ ] **GLFW backend.** It installs its own GLFW callbacks and, on Windows, subclasses the window
      proc — the same window proc `installModalLoopTimer` subclasses for render-during-resize.
      Two independent subclassers of one window is a latent ordering problem.
- [ ] **Context lifetime.** `initImgui` calls `imgui.CreateContext`, which made the obvious
      "recreate imgui on resize" approach destroy and rebuild the whole context every frame of a
      drag. Owning setup makes it clear what actually depends on the swapchain, which is nothing.
- [ ] Decide what stays vendored. The aim is to replace the two backends, not imgui itself.

### 5. Normal mapping

- [x] Fix the tangent frame. `Scene.slang` builds its TBN with the tangent and bitangent rows
      zeroed, so only the normal is meaningful and the sampled normal map has no effect
- [x] Verify assimp is producing usable tangents, and generate them if it is not. `CalcTangentSpace`
      was already set and does produce them; the gap was that `Files.odin` dereferenced
      `mTangents`/`mBitangents`/`mTextureCoords[0]` without checking for null, which is what
      assimp returns for a mesh with no UVs. Guarded, and it now warns instead
- [x] Check the `Vertex` tangent/bitangent fields survive the std430 layout correctly. They do —
      the explicit `u32` padding puts every `Vec3` on a 16-byte boundary and `size_of(Vertex)` is
      112, matching the shader struct
- [x] Sample normal maps through a linear view. Every texture was created as `R8G8B8A8_SRGB`, so
      the hardware applied an sRGB decode to normal maps too and a flat (128,128,255) map
      resolved to roughly (-0.57,-0.57,1). Textures are now `MUTABLE_FORMAT` with a second UNORM
      view in its own heap slot, and `TEXTURE_SLOT_IS_LINEAR` picks the view per texture slot
- [ ] Add a normal-map-only debug view to confirm the result. The `norm` entry point exists and is
      now trustworthy, and the `R` key in `IO.odin` does compile it — but only by hijacking the
      shader reload path, which swaps the scene pipeline to it one way with no way back. Make it a
      real toggle; see the hot reload tasks under 8
- [ ] Add a demo asset with a real normal map. Both demo meshes use the flat map, so nothing in
      the scene currently exercises a non-trivial tangent frame end to end
- [ ] Reconsider `VkImageFormatListCreateInfo`. `MUTABLE_FORMAT` without a format list lets
      drivers disable texture compression conservatively; `createImage` has no `pNext` hook to
      pass one through yet

### 6. Light types

- [ ] Directional lights
- [ ] Spot lights
- [ ] Generalise `PointLight` into a light type the shaders can switch on, rather than the
      single struct in `SceneData.odin`
- [ ] Editor support for creating and editing each type

### 7. Shadow quality and cost

- [x] One draw per light rather than six (multiview)
- [ ] Per-face culling — every light currently submits all geometry to all six views
- [ ] Skip faces a light cannot affect
- [ ] Cascaded shadow maps for directional lights (depends on roadmap 3)
- [ ] Revisit the fixed 512x512 `SHADOW_RESOLUTION` and the 20-sample PCF loop

### 8. Asset and shader pipeline

- [x] Fix "Add Texture" — it passed the `.texture` descriptor path to the image loader instead
      of the asset the descriptor points at, then panicked on the failure
- [x] Fix "Open Scene" — cancelling the dialog produced an empty path that `filepath.rel` could
      not relate, and the resulting broken scene was appended and loaded anyway

- [ ] Load shader descriptor files the way models and textures are loaded, instead of
      hardcoding the six `compileShader` calls in `Main.odin`
- [ ] Compile multiple entry points in one pass (`Shaders.odin`)

**Shader hot reload.** The mechanism still exists and works — `updatePipelineShaders` waits for
idle, tears down the pipeline, rebuilds it and dirties only the affected pass, and it already
handles all five `PipelineIndex` cases. What is missing is any usable way to reach it. Its sole
caller is the `R` key in `IO.odin`, which is hardcoded to one pipeline and, worse, has been left
compiling the `norm` debug entry point instead of `frag`, so pressing it swaps the scene to the
normal-map view rather than reloading the shader.

- [ ] Point the reload path back at `frag` and make the debug view a deliberate toggle of its own
      rather than a side effect of the reload key
- [ ] Reload every pipeline, not just `.Scene`. Needs a table mapping each `PipelineIndex` to its
      source files, entry points and stages — the same table the descriptor-file task above wants,
      so the two should land together
- [ ] Handle compile failure. The `R` path discards the `CompileError` with `_` and hands the
      result to `createScenePipeline` regardless, so a syntax error tears down a working pipeline
      and rebuilds it from nothing. A failed compile must log and leave the existing pipeline alone
- [ ] Watch the shader directory for changes rather than requiring a keypress, and debounce it —
      editors write files in several steps and a reload mid-write will read a truncated source
- [ ] Decide whether reload belongs on a key at all, given `IO.odin` already owns it. A UI button
      is discoverable and does not collide with camera movement
- [ ] Combine the per-purpose scene buffers into one buffer with offsets (`SceneBuffers`)
- [ ] Improve swapchain format selection, which currently takes the first format offered
      unless HDR is enabled

### 9. Renderer performance

- [x] Memory blocks grow geometrically (8 MiB, doubling to a 64 MiB cap) per memory type and
      tiling, instead of every pool reserving 64 MiB up front. Host image copy added a fourth
      pool — textures need `HOST_TRANSFER`, which restricts them to host-visible memory, so they
      moved off plain `DEVICE_LOCAL` onto resizable-BAR memory and cannot share a block with the
      render targets. Reserved memory went from 256 MiB to 34 MiB
- [ ] Reduce resize allocation churn — every swapchain resize frees and reallocates both
      post-process images, and live resizing does that per frame of a drag
- [ ] `VK_KHR_present_wait` / `present_id` for frame pacing and latency control — worth doing
      once there is a frametime readout to measure against
- [ ] `VK_KHR_dynamic_rendering_local_read` — only pays off if the renderer gains attachment
      reads mid-pass, such as a deferred path
- [ ] Replace the `drawLights` overlay's implicit-LOD `Sample` with `SampleLevel`, which would
      retire `computeDerivativeGroupQuads` and `VK_KHR_compute_shader_derivatives`
- [ ] Consider `VK_EXT_extended_dynamic_state3` and shader objects — deliberately deferred,
      since two graphics pipelines and a working pipeline cache do not justify them yet
- [ ] Dedicated transfer queue — deliberately deferred; uploads happen during scene load with
      nothing to overlap, and it would need queue family ownership transfers

### 10. Platform coverage

- [ ] Run the macOS build. `Graphics_darwin.odin` is written and type-checks but has never
      executed; the `NSTimer` run-loop mode handling is the most likely thing to be wrong
- [ ] Unblock `odin check src -target:linux_amd64`, which stops on `vendor:stb` missing
      prebuilt non-Windows binaries
- [ ] Confirm resizing behaviour on X11 and Wayland, where the callbacks alone are expected to
      be sufficient

### 11. Raytracing

- [ ] Scope what raytracing means here — reflections, shadows, GI, or a full path tracer
- [ ] Acceleration structure build and update
- [ ] Ray pipeline or ray queries

### 12. Test content

`tools/scenegen` generates every mesh and texture it uses from code, so the output carries no
third party licence and regenerating is deterministic. It imports the engine's own `SceneData`,
`ModelComponent` and `TextureComponent` and writes them through `refdisk`, so it cannot drift
from the on-disk format. Run it with the project directory, the same argument the engine takes:

```sh
odin build tools/scenegen -out:tools/scenegen/scenegen.exe
./tools/scenegen/scenegen.exe ./demo            # -scene:bench|environment|all, -size:N
```

- [x] Procedural generator: plane, cube, sphere and torus as OBJ; checker, brick, tile, dome and
      plaster as PNG, with normal maps derived from the same height fields
- [x] `bench.scene` — diagnostic. Two spheres with identical albedo and geometry differing only
      in normal map, a non-uniformly scaled cube to exercise the inverse transpose, a torus for
      tangent handedness across a UV seam, and low ambient so relief stays readable
- [x] `environment.scene` — a walled courtyard, to judge whether the whole thing looks right
      rather than whether one feature works
- [ ] **Mipmaps.** `createImage` hardcodes `mipLevels = 1`, so every texture aliases under
      minification; the courtyard floor moirés badly at a distance. Needs a mip chain, generation
      at load (or offline), and `maxLod` wired to it
- [ ] Make the startup scene selectable. `Main.odin` hardcodes `./scenes/knight.scene`, so the
      generated scenes can only be reached through the editor's Open Scene dialog
- [ ] Scenes that cover what these two do not: skinned animation, many lights at once, and enough
      geometry to be a performance test
- [ ] Decide whether the generated assets belong in git or should be produced on demand. They are
      about 2.6 MB and fully reproducible from the generator

### 13. Project files

The engine is given a project file, not a directory, and can only ever load one — creating a
project is `tools/projectgen`'s job. Both the engine and the tools share `ProjectData`, so the
format has a single definition.

```sh
./tools/projectgen/projectgen.exe ./demo -name:demo -startup:./scenes/environment.scene
./bin/valhalla.exe ./demo/demo.project
```

- [x] `ProjectData` and `loadProject`, carrying name, root, and the scene, asset, component and
      shader paths. A project states its whole layout — the engine infers nothing, and an unset
      field is rejected at load rather than quietly resolved to a conventional directory. Every
      missing field is named in one pass so a half-written project takes one run to fix
- [x] `version` as the first field, so it sits at offset 0 where it can be read before the rest
      of a positional format is trusted
- [x] Startup scene in the project file, replacing the hardcoded path in `Main.odin`. Still
      overridable as a second command line argument
- [x] Default model, albedo and normal for new scenes. `newScene` previously hardcoded
      `cube.model`, `cube.texture` and `blank_normal.texture`, which broke the moment those
      assets were renamed
- [x] `tools/projectgen`, and `tools/scenegen` reading paths from the project file instead of
      assuming a layout
- [ ] A user settings file, separate from the project: render resolution, window geometry, HDR
      and paper white, gamma, exposure and tonemapper, camera and mouse speed. Per machine, so
      gitignored — where the project file is committed and identical for everyone
- [ ] Decide where machine state belongs. `imgui.ini` and `pipeline_cache.bin` are written into
      the project directory today and are neither project data nor user settings
- [ ] A shader manifest in the project file, mapping source, entry point and stage to each
      pipeline. Would replace the eight hardcoded `compileShader` calls and supply the table the
      hot reload work needs to cover all five pipelines rather than only `.Scene`
- [ ] Shaders are engine-coupled but live per project, so a fresh project has none and cannot
      start. Decide whether they ship with the engine or are copied in at creation
- [ ] Validate paths at load and report all of them at once, rather than failing at the first
      asset that happens to be missing

## License

This project is licensed under the MIT License.
