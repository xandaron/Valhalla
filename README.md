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

## Project Structure

- `src/` &mdash; Core graphics engine implementation
- `demo/` &mdash; The project directory passed to the executable at runtime
  - `demo/shaders/` &mdash; Slang shaders, compiled at startup
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
| 1 | **Modern Vulkan foundations** — bindless descriptors, hand-rolled allocator, vertex pulling, multiview shadows, one staging ring for every upload | Complete |
| 2 | **Colour correctness** — colour space handling and light falloff | Partly done |
| 3 | **Reflection-driven editor** — inspectors are driven by `imreflect`; only engine behaviour stays hand-written | Complete |
| 4 | **Own imgui backends** — replace the vendored Vulkan and GLFW integrations to get control over colour, resources and callbacks | Complete |
| 5 | **Normal mapping** — tangent frame, linear sampling, and demo assets that exercise a real normal map | Complete |
| 6 | **Light types** — only point lights exist; directional and spot lights are missing | Not started |
| 7 | **Shadow quality and cost** — per-face culling, filtering, cascades for directional lights | Partly done |
| 8 | **Shader loading and hot reload** — shaders are hardcoded at startup and nothing reaches the reload path | Not started |
| 9 | **Renderer performance** — buffer consolidation, swapchain format selection | Partly done |
| 10 | **Project files** — the engine takes a project file rather than a directory, tooling creates them, and machine state lives in the project's config directory | Partly done |

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
- [x] Host image copy for textures — no staging buffer, no barriers, no queue submission.
      Superseded by the staging ring below; `hostImageCopy` is no longer requested
- [x] Move `addImages` onto the staging ring. Scene textures now upload the same way imgui
      textures do, so there is one upload path, and they are back on plain `DEVICE_LOCAL` memory
      instead of the host-visible memory `HOST_TRANSFER` forced them into
- [x] Rename `SamplerSlot.Nearest` to `.Linear`, which is what `createSamplers` writes into it
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
- [x] **The imgui overlay is not transfer-function aware.** It renders into ProcessedImage
      *after* PostProcess has already encoded, and wrote its raw [0,1] values with no
      conversion. In SDR that happens to be consistent. In HDR it was not: scene paper white
      encodes to about 0.58 in PQ, while imgui white wrote 1.0, which PQ defines as 10000 nits.
      Fixed by owning the backend (roadmap 4) — `Imgui.slang` encodes to match the target, so a
      Classic header now reads the same hue in HDR as in SDR instead of crushing to pure blue
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
- [x] Settings is reflected. `GraphicsData` holds a `RenderSettings`, the same struct the user
      settings file under 10 persists, and Settings draws it with `ImRefl.draw_value`. Conditional
      disabling (gamma in HDR, paper white in SDR, gizmo radius without gizmos) is `Read_Only`
      passed at the call site. Fields drawn by hand are tagged `imrefl:"ignore"`, which no longer
      hides them from the settings file: refdisk now reads only its own `refdisk` tag
- [x] A `label=` tag, so a field can read as "Near plane" rather than `near`. Like the flags it
      describes one field, so it is cleared before descending instead of relabelling every child.
      Values are comma separated, so a label cannot contain a comma
- [x] Adopt the `imrefl:"..."` struct tags. **The two consumers disagreed on vocabulary:** `refdisk`
      accepted `ignore` and `padding`, `imreflect` accepted only `padding`, so an `ignore` tag
      silently hid a field from serialisation while still drawing it. `padding` is now dropped from
      both packages and `ignore` is the single spelling; `Draw_Flag.Padding` became `.Ignore` to
      match. `Scene.vertices`, `Scene.indices` and `Scene.buffers` are tagged, as are `Model.meshes`
      and `Model.skeleton`. refdisk has since stopped reading `imrefl` tags at all, so the two
      vocabularies are independent again; a field that should not be serialised needs
      `refdisk:"ignore"`
- [x] Decide how edits signal the renderer. `sceneEdited` rebuilds everything when `draw_value`
      reports a change — deliberately blunt, but it only fires on frames where a value actually
      changed, which is only knowable because `draw_value` now returns that. Narrow it per field
      if it ever shows up in a profile
- [x] Keep hand-written controls where the widget triggers behaviour rather than editing data —
      the HDR toggle must call `setHDREnabled` for the swapchain rebuild, and "New Scene" and the
      scene picker are actions, not fields
- [x] Check what reflection exposes that should stay hidden: `Scene.buffers`, `Scene.vertices`,
      `Scene.indices`, `Model.meshes` and `Model.skeleton` are tagged `ignore`

### 4. Own imgui backends

Replace `imgui_impl_vulkan` and `imgui_impl_glfw` with integrations we own. The vendored ones are
fine in isolation, but they each fight a decision made elsewhere in the engine.

- [x] **Vulkan backend.** Replaced by a `PipelineIndex.Imgui` pass and `Imgui.slang`, drawn like
      every other pass: no descriptor pool, no set layouts, no `VkPipelineLayout`, no `VkSampler`,
      so the claim that there are none anywhere is true again. Vertices are pulled from a
      per-frame host-visible buffer in the resource heap's `ImguiVertex` slot; only the index
      buffer is still bound as fixed function, which needs no descriptor. Textures take a slot
      each in the heap's texture region, and a texture's `TexID` *is* its heap index, which is
      what the per-draw push constant carries
- [x] **Texture uploads on the staging ring.** The first version used `vkCopyMemoryToImage`
      behind a `vkDeviceWaitIdle` on every create or update, because host copies have no GPU
      timeline to order against. Uploads are now recorded into the staging command buffer, so
      several textures in a frame share one submit, and `drawFrame` makes the graphics submit
      wait on the staging timeline whenever it advanced that frame. Alpha8 atlases are expanded
      to RGBA32 while writing the reservation; any other format is reported once and marked
      destroyed, and draw commands whose texture is invalid are skipped, because heap index 0 is
      the Vertex buffer and a shader cannot tell the difference
- [x] **One geometry buffer per frame.** Vertices sit at offset 0, where the `ImguiVertex`
      descriptor points, and indices follow them. Capacity doubles from a floor of 4096, so
      steady state never reallocates, and the descriptor is rewritten only when it does
- [x] **Push constant layout pinned.** `Imgui_PushConstants` has `#assert`s on every offset, and
      each draw command pushes only the 4-byte `texture` field instead of the whole block
- [x] **Transfer-function aware output.** `Imgui.slang` takes the target's transfer function and
      paper white as push constants. Under Gamma it writes the colour unchanged, so SDR is
      byte-identical to what the vendored backend produced; under PQ it recovers the light the
      colour stands for with a fixed 2.2 (the response the colours were authored against, not the
      Gamma slider, which never graded the editor) and re-encodes it at paper white. Blending
      still happens in the encoded buffer, which is what compositing after the display transform
      costs; the alternative is a separate UI buffer resolved in linear light
- [x] **GLFW backend.** Replaced by our own in the `Dear ImGui` section of `Graphics.odin`. The
      callbacks `initWindow` installs are now the only ones on the window and feed imgui
      themselves, so nothing chains through a saved previous callback and nothing subclasses the
      window proc `installModalLoopTimer` already owns. Dropped along with the vendored backend:
      multi-viewport, which needs a second window the engine never creates; gamepad, which was
      dead code with `NavEnableGamepad` unset; and the Win32 mouse-source hook, so a pen or
      touch now reports as a mouse — if that ever matters, the existing subclass is where it
      goes, not a second one
- [x] **Route input by capture.** Owning the callbacks made it possible to ask imgui whether it
      wants an event before the engine acts on it, which `uiData.lockInput` was approximating by
      hand. The GLFW callbacks are thin shims that build an `InputEvent` and call `handleInput`
      in `IO.odin`, which feeds imgui every event and then makes the one routing decision by
      device: mouse events go to the engine unless `imguiWantsMouse`, keyboard events unless
      `imguiWantsKeyboard`. The per-callback guards had drifted apart — cursor motion ignored
      capture entirely, so mouse delta built up while using the editor and snapped the camera on
      entering fly mode. The public `setGLFW*Callback` setters are gone, since replacing a
      callback would bypass the handler
- [x] **Poll camera movement.** `cameraMove` was an accumulator fed by key presses and releases,
      which no filtered event stream can keep balanced: hold `W`, click into a text field,
      release, and the release is routed to imgui and the camera drifts forever. `tickFrame` now
      reads the movement keys with `glfw.GetKey` each frame, so movement follows what is
      physically held. Only discrete actions (`P`, `H`, `M`) remain events
- [x] **Keyboard path to a clean exit.** Ctrl+Q closes the window through GLFW, so the main loop
      ends normally and `cleanupGraphics` runs. It is checked before imgui's capture, so it works
      with a text field focused. Ctrl+Esc was ruled out because Windows takes it for the Start menu
- [x] **Overlay blends in linear light.** imgui draws into its own `R16G16B16A16_SFLOAT` UI image,
      cleared to transparent, before PostProcess. `Imgui.slang` always outputs linear light, so
      what accumulates is premultiplied coverage, and PostProcess composites
      `ui.rgb + scene * (1 - ui.a)` before the single Gamma or PQ encode. Opaque UI in SDR at gamma
      2.2 is unchanged, and translucent panels now blend the same way in both modes
- [x] Retire `uiData.lockInput`. `WantCaptureKeyboard` covers what it approximated
- [x] **Context lifetime.** Now visible rather than inferred: `initImgui` creates the context,
      the platform half holds cursors and a clock, and the renderer half holds one geometry
      buffer per frame in flight and the textures. The only thing in any of it that a swapchain
      resize could touch is the Imgui pipeline's colour format, and that is ProcessedImage's
      format, which does not change — the swapchain's does. Nothing to rebuild on resize
- [x] Decide what stays vendored. imgui itself stays; both backends are gone. `imgui/glfw`,
      `imgui/vulkan` and `imgui/opengl3` are deleted — the last backed a renderer this engine
      does not have

### 5. Normal mapping — complete

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
- [x] Demo assets with real normal maps. `bench.scene` and `environment.scene` from
      `tools/scenegen` carry generated normal maps, so the tangent frame is exercised end to end
- [x] `VkImageFormatListCreateInfo`. `createImage` takes a `pNext`, and `addImages` passes the two
      view formats a texture is read through, so drivers need not disable compression

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

### 8. Shader loading and hot reload

Shaders are compiled from ten hardcoded `compileShader` calls in `Main.odin`, and nothing calls
`updatePipelineShaders` any more, although it still rebuilds any of the six pipelines and dirties
only the affected pass. This undertaking covers a shader manifest that maps source, entry point
and stage to each pipeline; reload driven by that manifest, which must leave a working pipeline
alone when a compile fails; and deciding whether shaders ship with the engine or are copied into
a project at creation, since a fresh project has none and cannot start.

### 9. Renderer performance

- [x] Memory blocks grow geometrically (8 MiB, doubling to a 64 MiB cap) per memory type and
      tiling, instead of every pool reserving 64 MiB up front. Host image copy added a fourth
      pool — textures need `HOST_TRANSFER`, which restricts them to host-visible memory, so they
      moved off plain `DEVICE_LOCAL` onto resizable-BAR memory and cannot share a block with the
      render targets. Reserved memory went from 256 MiB to 34 MiB
- [x] Resize allocation churn. The post-process images and the UI image are sized to a capacity
      that starts at the largest of the swapchain and every connected monitor's video mode and
      only grows, so a live resize reallocates nothing unless the window outgrows every monitor.
      PostProcess bounds itself with a pushed output extent rather than `GetDimensions`
- [x] Frame pacing with `VK_KHR_present_id2` / `VK_KHR_present_wait2`, both optional. When the
      device and surface support them, every present carries an id and `drawFrame` waits for
      `next - maxFrameLatency` after the fence wait; otherwise it logs once and keeps the present
      fence path. The editor shows FPS with the average and worst frame time to measure it
- [ ] Combine the per-purpose scene buffers into one buffer with offsets (`SceneBuffers`)
- [ ] Improve swapchain format selection, which currently takes the first format offered
      unless HDR is enabled

### 10. Project files

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
- [x] A user settings file, separate from the project: `<config>/user.settings` holds
      `RenderSettings` (grading, tonemapper, gamma, paper white, HDR, gizmos, frame latency,
      render size), window geometry, and camera and mouse speed. It is versioned through refdisk
      like the project file, loaded after `loadProject` and saved at shutdown. It is the one place
      the engine falls back to defaults: the file is machine state the engine writes itself, not
      authored project data
- [x] Machine state lives in the project's `configPath`.
      `imgui.ini`, `pipeline_cache.bin` and `user.settings` are written there, the engine creates
      the directory if it is missing, and `projectgen` defaults it to `./config/`, which is
      gitignored
- [ ] A migrator that upgrades outdated project, scene, component and settings files. Until it
      exists every `*_FORMAT_VERSION` stays at 1: bumping one only turns an old file from a misparse
      into a refusal, and there is nothing to upgrade it with. When a struct changes before then,
      regenerate the affected files instead

## License

This project is licensed under the MIT License.
