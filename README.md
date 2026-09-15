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
| 2 | **Normal mapping** — the tangent frame is currently broken, so normal maps are sampled but contribute nothing | Not started |
| 3 | **Light types** — only point lights exist; directional and spot lights are missing | Not started |
| 4 | **Shadow quality and cost** — per-face culling, filtering, cascades for directional lights | Partly done |
| 5 | **Asset and shader pipeline** — shaders are hardcoded at startup; buffers are allocated one per purpose | Not started |
| 6 | **Renderer performance** — buffer consolidation, resize allocation churn, pipeline state objects | Partly done |
| 7 | **Platform coverage** — macOS is written but unrun; Linux cannot be checked end to end | Blocked |
| 8 | **Raytracing** | Not started |

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

### 2. Normal mapping

- [ ] Fix the tangent frame. `Scene.slang` builds its TBN with the tangent and bitangent rows
      zeroed, so only the normal is meaningful and the sampled normal map has no effect
- [ ] Verify assimp is producing usable tangents, and generate them if it is not
- [ ] Check the `Vertex` tangent/bitangent fields survive the std430 layout correctly
- [ ] Add a normal-map-only debug view to confirm the result (the `norm` entry point exists but
      is only as trustworthy as the TBN)

### 3. Light types

- [ ] Directional lights
- [ ] Spot lights
- [ ] Generalise `PointLight` into a light type the shaders can switch on, rather than the
      single struct in `SceneData.odin`
- [ ] Editor support for creating and editing each type

### 4. Shadow quality and cost

- [x] One draw per light rather than six (multiview)
- [ ] Per-face culling — every light currently submits all geometry to all six views
- [ ] Skip faces a light cannot affect
- [ ] Cascaded shadow maps for directional lights (depends on roadmap 3)
- [ ] Revisit the fixed 512x512 `SHADOW_RESOLUTION` and the 20-sample PCF loop

### 5. Asset and shader pipeline

- [ ] Load shader descriptor files the way models and textures are loaded, instead of
      hardcoding the six `compileShader` calls in `Main.odin`
- [ ] Compile multiple entry points in one pass (`Shaders.odin`)
- [ ] Combine the per-purpose scene buffers into one buffer with offsets (`SceneBuffers`)
- [ ] Improve swapchain format selection, which currently takes the first format offered
      unless HDR is enabled

### 6. Renderer performance

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

### 7. Platform coverage

- [ ] Run the macOS build. `Graphics_darwin.odin` is written and type-checks but has never
      executed; the `NSTimer` run-loop mode handling is the most likely thing to be wrong
- [ ] Unblock `odin check src -target:linux_amd64`, which stops on `vendor:stb` missing
      prebuilt non-Windows binaries
- [ ] Confirm resizing behaviour on X11 and Wayland, where the callbacks alone are expected to
      be sufficient

### 8. Raytracing

- [ ] Scope what raytracing means here — reflections, shadows, GI, or a full path tracer
- [ ] Acceleration structure build and update
- [ ] Ray pipeline or ray queries

## License

This project is licensed under the MIT License.
