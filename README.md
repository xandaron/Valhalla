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
./bin/valhalla.exe ./demo
```

The argument is the project directory, and the app runs with it as its working directory.

## Roadmap

Large undertakings, roughly in the order they are likely to be tackled. Each one is broken into
checkable work in [Tasks](#tasks).

| # | Undertaking | State |
| --- | --- | --- |
| 1 | **Modern Vulkan foundations** — bindless descriptors, hand-rolled allocator, vertex pulling, multiview shadows, host image copy | Complete |
| 2 | **Colour correctness** — colour space handling and light falloff | Partly done |
| 3 | **Own imgui backends** — replace the vendored Vulkan and GLFW integrations to get control over colour, resources and callbacks | Not started |
| 4 | **Normal mapping** — the tangent frame is currently broken, so normal maps are sampled but contribute nothing | Not started |
| 5 | **Light types** — only point lights exist; directional and spot lights are missing | Not started |
| 6 | **Shadow quality and cost** — per-face culling, filtering, cascades for directional lights | Partly done |
| 7 | **Asset and shader pipeline** — shaders are hardcoded at startup; buffers are allocated one per purpose | Not started |
| 8 | **Renderer performance** — buffer consolidation, resize allocation churn, pipeline state objects | Partly done |
| 9 | **Platform coverage** — macOS is written but unrun; Linux cannot be checked end to end | Blocked |
| 10 | **Raytracing** | Not started |

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
- [ ] Verify HDR against an actual HDR display and tune paper white (default 200 nits, now a
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

### 3. Own imgui backends

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

### 4. Normal mapping

- [ ] Fix the tangent frame. `Scene.slang` builds its TBN with the tangent and bitangent rows
      zeroed, so only the normal is meaningful and the sampled normal map has no effect
- [ ] Verify assimp is producing usable tangents, and generate them if it is not
- [ ] Check the `Vertex` tangent/bitangent fields survive the std430 layout correctly
- [ ] Add a normal-map-only debug view to confirm the result (the `norm` entry point exists but
      is only as trustworthy as the TBN)

### 5. Light types

- [ ] Directional lights
- [ ] Spot lights
- [ ] Generalise `PointLight` into a light type the shaders can switch on, rather than the
      single struct in `SceneData.odin`
- [ ] Editor support for creating and editing each type

### 6. Shadow quality and cost

- [x] One draw per light rather than six (multiview)
- [ ] Per-face culling — every light currently submits all geometry to all six views
- [ ] Skip faces a light cannot affect
- [ ] Cascaded shadow maps for directional lights (depends on roadmap 3)
- [ ] Revisit the fixed 512x512 `SHADOW_RESOLUTION` and the 20-sample PCF loop

### 7. Asset and shader pipeline

- [x] Fix "Add Texture" — it passed the `.texture` descriptor path to the image loader instead
      of the asset the descriptor points at, then panicked on the failure
- [x] Fix "Open Scene" — cancelling the dialog produced an empty path that `filepath.rel` could
      not relate, and the resulting broken scene was appended and loaded anyway

- [ ] Load shader descriptor files the way models and textures are loaded, instead of
      hardcoding the six `compileShader` calls in `Main.odin`
- [ ] Compile multiple entry points in one pass (`Shaders.odin`)
- [ ] Combine the per-purpose scene buffers into one buffer with offsets (`SceneBuffers`)
- [ ] Improve swapchain format selection, which currently takes the first format offered
      unless HDR is enabled

### 8. Renderer performance

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

### 9. Platform coverage

- [ ] Run the macOS build. `Graphics_darwin.odin` is written and type-checks but has never
      executed; the `NSTimer` run-loop mode handling is the most likely thing to be wrong
- [ ] Unblock `odin check src -target:linux_amd64`, which stops on `vendor:stb` missing
      prebuilt non-Windows binaries
- [ ] Confirm resizing behaviour on X11 and Wayland, where the callbacks alone are expected to
      be sufficient

### 10. Raytracing

- [ ] Scope what raytracing means here — reflections, shadows, GI, or a full path tracer
- [ ] Acceleration structure build and update
- [ ] Ray pipeline or ray queries

## License

This project is licensed under the MIT License.
