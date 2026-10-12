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

- `src/` &mdash; The Valhalla package: graphics, window management and input
- `demo/src/` &mdash; The demo executable: project and scene files, editor UI, external API, frame loop
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
odin build demo/src -out:bin/demo.exe
./bin/demo.exe
```

The argument is the project directory, and the app runs with it as its working directory.

## Roadmap

Large undertakings, roughly in the order they are likely to be tackled. Each one is broken into
checkable work in [Tasks](#tasks).

| # | Undertaking | State |
| --- | --- | --- |
| 1 | **Scene editor** — docking, an object catalog and inspector, click-to-select, tabs and renaming, so scenes can be built in the editor | Partly done |
| 2 | **Colour correctness** — colour space handling, light falloff and gizmo picking | Done |
| 3 | **Light types** — only point lights exist; directional and spot lights are missing | Not started |
| 4 | **Shadow quality and cost** — per-face culling, filtering, cascades for directional lights | Partly done |
| 5 | **Shader loading and hot reload** — shaders are hardcoded at startup and nothing reaches the reload path | Not started |
| 6 | **Renderer performance** — buffer consolidation, swapchain format selection | Partly done |
| 7 | **Project files** — a migrator for outdated file versions | Partly done |

## Tasks

### 1. Scene editor

The editor is a main menu bar and docked panels around a passthrough central node the scene
shows through: Objects, Lights and Scenes on the left, the Inspector on the right, and Scene,
Settings, Models and Textures below it. **F1** hides all of it, and so does fly mode (middle
click) until it ends.

- [x] **Docking.** `DockSpaceOverViewport` with a passthrough central node; the default layout is
      built with the DockBuilder when `imgui.ini` holds none
- [x] **Object inspector.** Reflected fields plus the model, animation clip and texture pickers;
      lights are inspected the same way
- [x] **Click to select.** `cursorRay` builds the ray from the letterboxed content rect and the
      active camera; `pick` tests each mesh's box in object space via `objectTransform`,
      which the instance buffer shares, so attachments are honoured. Light gizmos are picked as
      spheres of `lightGizmoRadius` while they are shown
- [x] **Object catalog.** Objects panel, filterable by name
- [x] **Translate gizmo.** The selected object or light shows X/Y/Z arrows and plane pads, drawn
      on imgui's background draw list; arrows drag along the closest point between the mouse ray
      and the axis, pads along the ray's hit on the plane through the gizmo. Attached objects are
      moved in their parent's space, so the handles stay world-aligned
- [x] **Tabs.** Each inspector tab has a pin left of its name, off by default. Showing an unpinned
      tab, including a newly opened one, closes every other unpinned tab. The Scenes panel lists every `.scene` in the scenes directory and
      opens or switches to one on click
- [x] **Renaming.** `nameField` in `UI.odin`, backed by a `strings.Builder` that `InputText`'s
      `.CallbackResize` grows; commits on deactivation. Renames objects and scenes
- [ ] The scene still renders across the whole window behind the panels. Letterboxing it into the
      central node would need PostProcess re-recorded whenever the dock layout changes, and
      `cursorToRenderNDC` moved to the same rect
- [ ] Picking uses bind-pose mesh boxes, so animated and skinned objects are picked by where their
      rest pose is
- [ ] Deleting objects. Selection and open tabs are indices into `scene.objects`, so removal must
      remap them (and every `Attachment.targetIdx`)
- [ ] If the name field becomes imreflect's string widget, so every string field is editable,
      settle first who owns the string's memory, since imreflect cannot know the allocator

### 2. Colour correctness

- [x] Gizmo picking — clicking a light's billboard opens it in the inspector (see 1)

### 3. Light types

- [ ] Directional lights
- [ ] Spot lights
- [ ] Generalise `PointLight` into a light type the shaders can switch on, rather than the
      single struct in `SceneData.odin`
- [ ] Editor support for creating and editing each type

### 4. Shadow quality and cost

- [ ] Per-face culling — every light currently submits all geometry to all six views
- [ ] Skip faces a light cannot affect
- [ ] Cascaded shadow maps for directional lights (depends on 3, light types)
- [ ] Revisit the fixed 512x512 `SHADOW_RESOLUTION` and the 20-sample PCF loop

### 5. Shader loading and hot reload

Shaders are compiled from ten hardcoded `compileShader` calls in `demo/src/Main.odin`, and nothing calls
`updatePipelineShaders` any more, although it still rebuilds any of the six pipelines and dirties
only the affected pass. This undertaking covers a shader manifest that maps source, entry point
and stage to each pipeline; reload driven by that manifest, which must leave a working pipeline
alone when a compile fails; and deciding whether shaders ship with the engine or are copied into
a project at creation, since a fresh project has none and cannot start.

### 6. Renderer performance

- [ ] Combine the per-purpose scene buffers into one buffer with offsets (`SceneBuffers`)
- [ ] Improve swapchain format selection, which currently takes the first format offered
      unless HDR is enabled

### 7. Project files

The engine is given a project file, not a directory, and can only ever load one — creating a
project is `tools/projectgen`'s job. Both the engine and the tools share `ProjectData`, so the
format has a single definition.

```sh
./tools/projectgen/projectgen.exe ./demo -name:demo -startup:./scenes/creature.scene
./bin/demo.exe
```

- [ ] A migrator that upgrades outdated project, scene, component and settings files. Until it
      exists every `*_FORMAT_VERSION` stays at 1: bumping one only turns an old file from a misparse
      into a refusal, and there is nothing to upgrade it with. When a struct changes before then,
      regenerate the affected files instead

## License

This project is licensed under the MIT License.
