# Valhalla

A graphics package for Odin on Vulkan 1.4. It covers the GPU device, resources, shaders, recorded GPU
work, windows and input, and leaves the frame loop and everything else to the program using it.
Pending work is in [`TODO.md`](TODO.md).

## Requirements

- [Odin](https://odin-lang.org/docs/install/)
- The [Vulkan SDK](https://vulkan.lunarg.com/). Valhalla always enables the validation layer, and on
  Windows it loads Slang's DLLs (`slang.dll`, `slang-compiler.dll`) from the SDK's `Bin` directory,
  which must be on `PATH` (or link Slang statically; see [Linking](#linking)).
- A GPU and driver with `VK_EXT_descriptor_heap`, `VK_KHR_shader_untyped_pointers`,
  `VK_KHR_unified_image_layouts` and `VK_EXT_extended_dynamic_state3`.
- On Linux, GLFW 3.4 or later.

## Running the examples

From the repository root:

```sh
odin run examples/hello_triangle
```

| Example | Shows |
| --- | --- |
| `hello_triangle` | The smallest program: a window, a shader, and a workload recorded every frame |
| `textured_cube` | Vertex and index buffers, a texture and sampler, depth, and a workload recorded once |
| `offscreen` | No window: renders into an image and writes it to `triangle.png` |
| `hdr` | An HDR surface with a PQ-encoding pass, falling back to SDR |
| `lighting` | Shadow maps for a sun and four point lights, using multiview for cube maps |
| `two_windows` | One workload drawing to two windows, input in one driving the other |
| `input` | Keyboard, mouse, gamepad, clipboard, cursors, file drops and fullscreen |
| `imgui` | Dear ImGui through `Valhalla_ImGui` |
| `image_editor` | A node-graph image editor with runtime-compiled custom shaders |

### Setup

```odin
Valhalla.init(app_name = "My App") or_return
defer Valhalla.shutdown()

window := Valhalla.make_window(title = "My App") or_return
defer Valhalla.delete_window(&window)

surface := Valhalla.make_surface(&window, {}) or_return
defer Valhalla.delete_surface(&surface)
```

`init` picks the GPU and creates the device; extra extensions and features are parameters of `init`.
A **surface** is a window's swapchain. It rebuilds itself when the window resizes, and its state
(`extent`, `format`, `hdr`, `minimised`) is read from its fields.

### Resources

```odin
vertices := Valhalla.make_buffer(slice.to_bytes(data[:]), Valhalla.Buffer_Settings{usage = {.Storage}}) or_return
texture  := Valhalla.make_image_from_file("albedo.png") or_return
linear   := Valhalla.make_sampler() or_return
```

Buffers, images and samplers are uploaded when they are made, and stay on the GPU until written again.
There are no vertex buffers: vertex shaders read vertex data from storage buffers. Data that changes
every frame belongs in a `.Host_Visible` buffer, written with `load_memory_to_buffer`. The application
must not write a resource while the GPU is still using it.

### Shaders

A shader is a pipeline built from Slang (a file or source) or SPIR-V. Shaders declare no bindings:
resources reach them through push data. The Odin struct named by `push_type` is matched against the
shader's push struct when the shader is made, and `Image`, `Buffer` and `Sampler` fields arrive as
typed handles used as the resources themselves:

```odin
Push :: struct {
	vertices: Valhalla.Buffer,
	albedo:   Valhalla.Image,
	linear:   Valhalla.Sampler,
}

shader, _ := Valhalla.make_shader(
	#load("Mesh.slang"),
	[]string{"vertex_main", "fragment_main"},
	{search_paths = {"path/to/valhalla/src/shaders"}},
	{push_type = Push, colour_formats = {0 = surface.format.format}},
) or_return
```

```slang
import Valhalla;

struct Push {
	ValhallaHeader header;
	DescriptorHandle<StructuredBuffer<Vertex>> vertices;
	DescriptorHandle<Texture2D<float4>> albedo;
	DescriptorHandle<SamplerState> linear;
};
[[vk::push_constant]] ConstantBuffer<Push> push;

// push.vertices[vertex_id], push.albedo.Sample(push.linear, uv)
```

The second return value is the compiler's diagnostics. Everything Vulkan allows to be dynamic (depth
test, blending, culling, viewport, ...) is set per draw with `set_*` procedures, not baked into the
shader. Shaders work in linear light: sRGB textures decode when sampled and SDR surfaces encode on
write.

### Workloads

A **workload** is recorded GPU work that can be executed any number of times. A shader holds a small
recording of its own (attachments, push data, draws), and `bind_shader` replays it into a workload:

```odin
frame := Valhalla.make_workload() or_return
defer Valhalla.delete_workload(&frame)

image := Valhalla.acquire(&frame, &surface) or_return
cleared := Valhalla.clear_image(&frame, image, {})

Valhalla.reset_shader(&shader)
Valhalla.set_push_data(&shader, Push{vertices, texture, linear})
drawn := Valhalla.bind_shader_colour(&shader, cleared)
Valhalla.draw(&shader, 3, 1, 0, 0)
Valhalla.bind_shader(&frame, shader) or_return

Valhalla.present(&frame, drawn)
Valhalla.finalize_workload(&frame) or_return

execution := Valhalla.execute_workloads(&frame) or_return
Valhalla.wait_execution(execution) or_return
```

- **Writes return versions.** `clear_image`, the attachment binds and `bind_shader_output` return the
  resource's next version, and the next operation takes that version. Ordering and barriers follow
  from it: bind whatever reads a version before whatever writes the next one, and the order the code is
  written in is the order it runs.
- **Record once, execute often.** A workload can be recorded every frame (`hello_triangle`), or
  recorded once with per-frame data written into host-visible buffers between executions
  (`textured_cube`). When the swapchain is rebuilt, `execute_workloads` returns
  `.Swapchain_Changed` and the workload is recorded again.
- **Chain workloads to make passes optional.** `execute_workloads` submits its workloads in one go, in
  order, each starting after everything before it has finished. Recording a toggleable pass as its
  own workload that writes in place, and leaving it out of the chain, turns it off without
  re-recording anything:

  ```odin
  chain: [3]^Valhalla.Workload
  count := 0
  chain[count] = &scene; count += 1
  if show_gizmos {
  	chain[count] = &gizmos; count += 1
  }
  chain[count] = &frame; count += 1
  execution := Valhalla.execute_workloads(..chain[:count]) or_return
  ```

  The only link between workloads is what `workload_produces` hands over: a workload reads the latest
  written contents and never makes its producer run again, so a producer executed once can feed a
  consumer executed every frame.
- **Wait before reusing.** Wait for an execution before writing, resizing or deleting what it uses.
- `readback` copies a resource out of a workload for the CPU; `raw_commands` gives the command buffer
  for raw Vulkan.

### Windows and input

The input API mirrors GLFW's, renamed to Valhalla's style: `poll_events`, `key_down`,
`cursor_position`, per-window callbacks such as `set_key_callback`, plus gamepads, clipboard, cursors
and monitors. `set_frame_callback` keeps frames coming while a window is being dragged or resized.

## Linking

Each binding links the libraries committed beside it by default. A define points it at another
directory, relative to the binding's package (Odin reads an absolute path's drive letter as a
collection name):

| Define | Binding | Effect |
| --- | --- | --- |
| `SLANG_LIB_DIR` | `src/slang` | Links Slang's static libraries from that directory instead of the DLL import libraries, so no Slang DLL is needed |
| `IMGUI_LIB_DIR` | `deps/imgui` | Takes the prebuilt ImGui library from that directory |
| `TINYFILEDIALOGS_LIB_DIR` | `deps/tinyfiledialogs` | Takes the prebuilt tinyfiledialogs library from that directory |

`libs/` at the repository root is ignored by git for local libraries such as Slang's static build:

```sh
odin run examples/hello_triangle -define:SLANG_LIB_DIR=../../libs
```

## License

MIT.
