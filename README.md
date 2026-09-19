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
| 1 | **Colour correctness** — colour space handling and light falloff are done; gizmo picking remains | Partly done |
| 2 | **Light types** — only point lights exist; directional and spot lights are missing | Not started |
| 3 | **Shadow quality and cost** — per-face culling, filtering, cascades for directional lights | Partly done |
| 4 | **Shader loading and hot reload** — shaders are hardcoded at startup and nothing reaches the reload path | Not started |
| 5 | **Renderer performance** — buffer consolidation, swapchain format selection | Partly done |
| 6 | **Project files** — a migrator for outdated file versions | Partly done |

## Tasks

### 1. Colour correctness

- [ ] Gizmo picking — the billboards are real geometry, so clicking one to select its light is
      now feasible

### 2. Light types

- [ ] Directional lights
- [ ] Spot lights
- [ ] Generalise `PointLight` into a light type the shaders can switch on, rather than the
      single struct in `SceneData.odin`
- [ ] Editor support for creating and editing each type

### 3. Shadow quality and cost

- [ ] Per-face culling — every light currently submits all geometry to all six views
- [ ] Skip faces a light cannot affect
- [ ] Cascaded shadow maps for directional lights (depends on 2, light types)
- [ ] Revisit the fixed 512x512 `SHADOW_RESOLUTION` and the 20-sample PCF loop

### 4. Shader loading and hot reload

Shaders are compiled from ten hardcoded `compileShader` calls in `Main.odin`, and nothing calls
`updatePipelineShaders` any more, although it still rebuilds any of the six pipelines and dirties
only the affected pass. This undertaking covers a shader manifest that maps source, entry point
and stage to each pipeline; reload driven by that manifest, which must leave a working pipeline
alone when a compile fails; and deciding whether shaders ship with the engine or are copied into
a project at creation, since a fresh project has none and cannot start.

### 5. Renderer performance

- [ ] Combine the per-purpose scene buffers into one buffer with offsets (`SceneBuffers`)
- [ ] Improve swapchain format selection, which currently takes the first format offered
      unless HDR is enabled

### 6. Project files

The engine is given a project file, not a directory, and can only ever load one — creating a
project is `tools/projectgen`'s job. Both the engine and the tools share `ProjectData`, so the
format has a single definition.

```sh
./tools/projectgen/projectgen.exe ./demo -name:demo -startup:./scenes/environment.scene
./bin/valhalla.exe ./demo/demo.project
```

- [ ] A migrator that upgrades outdated project, scene, component and settings files. Until it
      exists every `*_FORMAT_VERSION` stays at 1: bumping one only turns an old file from a misparse
      into a refusal, and there is nothing to upgrade it with. When a struct changes before then,
      regenerate the affected files instead

## License

This project is licensed under the MIT License.
