# Valhalla

A graphics package for Odin on Vulkan 1.4. It covers the GPU device, resources, shaders, recorded GPU
work, windows and input, and leaves the frame loop and everything else to the program using it.
Pending work is in [`TODO.md`](TODO.md).

## Requirements

- [Odin](https://odin-lang.org/docs/install/)
- The [Vulkan SDK](https://vulkan.lunarg.com/). On Windows Valhalla loads Slang's DLLs (`slang.dll`,
  `slang-compiler.dll`) from the SDK's `Bin` directory, which must be on `PATH` (or link Slang
  statically; see [Linking](#linking)). The validation layer is on by default and comes from the SDK.
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
| `textured_cube` | Storage and index buffers, a texture and sampler, depth, and a workload recorded once |
| `offscreen` | No window: renders into an image and writes it to `triangle.png` |
| `hdr` | An HDR surface with a PQ-encoding pass, falling back to SDR |
| `lighting` | Shadow maps for a sun and four point lights, using multiview for cube maps |
| `raytracing` | Hardware ray queries from a compute shader: acceleration structures, shadows and mirror bounces |
| `vr` | Stereo rendering: both eyes in one multiview pass into a two-layer image, shown side by side with an optional lens preview |
| `two_windows` | One workload drawing to two windows, input in one driving the other |
| `input` | Keyboard, mouse, gamepad, clipboard, cursors, file drops and fullscreen |
| `external` | Resources made with raw Vulkan handed to Valhalla, and raw commands inside a workload |
| `imgui` | Dear ImGui through `Valhalla_ImGui` |
| `image_editor` | A node-graph image editor with runtime-compiled custom shaders |

## Setup

```odin
Valhalla.init(app_name = "My App") or_return
defer Valhalla.shutdown()

window := Valhalla.make_window(title = "My App") or_return
defer Valhalla.delete_window(&window)

surface := Valhalla.make_surface(window) or_return
defer Valhalla.delete_surface(&surface)
```

`init` picks the GPU and creates the device. Its parameters are all optional: the application name
and version, extra instance and device extensions, Vulkan feature structs for anything Valhalla does
not request itself, and `validation`, which is `.Synchronisation` (the validation layer with
synchronisation validation) by default, or `.Standard` or `.None`. The device is the package variable
`Valhalla.device`; its fields are plain Vulkan handles for anything Valhalla has no API for.

A **surface** is a window's swapchain. `make_surface(window, present_mode = .Fifo, prefer_hdr = false,
encode_srgb = true)` chooses the swapchain format; the result is read from the surface's fields:
`format`, `colour_space`, `extent`, `hdr`, `hdr_available`, `encodes_srgb` and `minimised`.
`set_surface_present_mode` and `set_surface_hdr` rebuild it.

### Errors

Every procedure that can fail returns an `Error`, a union of one enum per area (`Device_Error`,
`Surface_Error`, `Shader_Error`, ...). `nil` is success, so `or_return` works everywhere, and results
that must not be dropped (errors and resource versions) are marked `@(require_results)`. Mistakes in
how the API is used (binding the wrong kind of image, drawing with a compute shader, recording a
shader that is bound to a workload) are asserts, not errors.

### Handles

`Window`, `Surface`, `Buffer`, `Image`, `Sampler`, `Shader` and `Workload` are small structs that
name a GPU object. A procedure takes one by pointer only when it changes the struct itself
(`delete_*`, `resize_image`, `reset_shader`, everything on a `Workload`); everything else takes it by
value, so handles are passed around and stored by value.

## Resources

```odin
vertices := Valhalla.make_buffer_from_memory(slice.to_bytes(data[:]), {.Storage}) or_return
frame    := Valhalla.make_buffer(size_of(Frame), {.Storage}, .Host_Visible) or_return
texture  := Valhalla.make_image_from_file("albedo.png") or_return
target   := Valhalla.make_image(surface.format, {surface.extent.x, surface.extent.y, 1}, {.Attachment}) or_return
linear   := Valhalla.make_sampler() or_return
```

- A buffer's usage is a set of `.Storage`, `.Uniform`, `.Index`, `.Indirect` and
  `.Acceleration_Input`; a buffer is `.Storage` or `.Uniform`, never both. Its memory is
  `.Device_Local` (the default), `.Host_Visible` or `.Host_Readback`.
- An image's usage is a set of `.Attachment` and `.Storage`; every image can also be sampled and
  copied. Whether an attachment is a colour or a depth attachment follows from its format. `make_image`
  also takes `shape` (`.D2`, `.D2_Array`, `.Cube`, ...), `layers`, `mip_levels`, `samples`, `name` and
  `view_formats`. `make_image_view` makes a view of part of an image (mips, layers, another format or
  aspect) that is used like an image of its own.
- Formats and the sampler and draw-state enums are Vulkan's, under Valhalla names: `Format`,
  `Filter`, `Address_Mode`, `Compare_Op`, `Cull_Mode`, `Topology`, `Blend_Equation` and so on, so the
  values are written `.D32_SFLOAT`, `.LINEAR`, `.CLAMP_TO_EDGE`.

Buffers and images made from data are uploaded when they are made; `load_memory_to_buffer`,
`load_memory_to_image`, `load_file_to_image` and the `load_*_to_*` copies write to them later. Data
that changes every frame belongs in a `.Host_Visible` buffer, written with `load_memory_to_buffer`.
Writing a resource, or resizing an image, while the GPU is still using it is the application's
mistake; deleting one is not, because `delete_*` only destroys the object once every execution that
used it has finished.

There are no vertex buffers: vertex shaders read vertex data from storage buffers.

### External resources

A `Buffer` or `Image` can wrap an object made with raw Vulkan: fill in the handle, size or extent,
format, usage, layout and the other fields, and set `variant` to `External_Buffer{}` or
`External_Image{}`. Valhalla then tracks it like its own, except that it never frees it, and it has no
descriptor, so it cannot be a push-data field. It can be an attachment, an index or indirect buffer,
and the source or target of clears, copies, blits and presents. `examples/external` shows the whole
round trip.

## Shaders

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

shader := Valhalla.make_shader(
	#load("Mesh.slang"),
	[]string{"vertex_main", "fragment_main"},
	push_type = Push,
	colour_formats = {0 = surface.format},
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

`push_type` is required; pass `nil` for a shader with no push data after the header. The other
parameters are optional: `colour_formats` (indexed, `{0 = ...}`), `depth_format`, `stencil_format`,
`view_mask` for multiview, `name`, `pipeline_cache`, and `search_paths` and `defines` for the Slang
compiler. The `Valhalla` module is always importable; search paths are only for your own modules.
`make_shaders` builds several pipelines from one compile. The compiler's output is kept and returned
by `shader_diagnostics()` until the next compile; a failed compile returns an error and says nothing
else.

A single struct the shader reads whole (a camera, a block of settings) goes in a `.Uniform` buffer,
declared as `DescriptorHandle<ConstantBuffer<View>> view` and read as `push.view->view_projection`.
The shader's handle type must agree with the buffer's usage.

Everything Vulkan allows to be dynamic (depth test, blending, culling, viewport, ...) is set per draw
with `set_*` procedures, not baked into the shader. Shaders work in linear light: sRGB textures decode
when sampled and SDR surfaces encode on write.

## Workloads

A **workload** is recorded GPU work that can be executed any number of times. A shader holds a small
recording of its own (attachments, push data, draws), and `bind_shader` replays it into a workload:

```odin
frame := Valhalla.make_workload() or_return
defer Valhalla.delete_workload(&frame)

cleared := Valhalla.clear_image(&frame, target, {0.1, 0.1, 0.12, 1})

Valhalla.reset_shader(&shader)
Valhalla.set_push_data(&shader, Push{vertices, texture, linear})
drawn := Valhalla.bind_shader_colour(&shader, cleared)
Valhalla.draw(&shader, 3)
Valhalla.bind_shader(&frame, shader) or_return

Valhalla.present(&frame, drawn, &surface)
Valhalla.finalize_workload(&frame) or_return

execution := Valhalla.execute_workloads(&frame) or_return
Valhalla.wait_execution(execution) or_return
```

- **Writes return versions.** `clear_image`, `clear_depth`, the attachment binds, `bind_shader_output`
  and the copies return the resource's next version, and the next operation takes that version.
  Ordering and barriers follow from it: bind whatever reads a version before whatever writes the next
  one, and the order the code is written in is the order it runs.
- **A bound shader is locked.** After `bind_shader`, recording into the shader again asserts until
  `reset_shader` (everything) or `reset_shader_bindings` (keep the draws, change the resources, push
  data and attachments). Draws default to one instance: `draw(shader, vertex_count)`,
  `draw_indexed(shader, index_count)`; `dispatch_threads` rounds a thread count up to groups.
- **Presenting.** `present(&workload, image, &surface)` records that the image is shown on the surface
  when the workload runs; `execute_workloads` acquires the swapchain image, blits the image onto it
  (scaling if the sizes differ) and presents. A window resize never invalidates a workload: draw into an
  image of your own and resize it, and re-record, whenever you want it to match `surface.extent` again.
  A minimised surface is skipped; `surface.minimised` is current after every execute, so a loop can
  `wait_events` when it is set.
- **Record once, execute often.** A workload can be recorded every frame (`hello_triangle`), or
  recorded once with per-frame data written into host-visible buffers between executions
  (`textured_cube`). `reset_workload` waits for its executions and starts a new recording.
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
  consumer executed every frame. `workload_discards` marks scratch (a depth buffer) so the "written
  but never used" warning stays quiet.
- **Wait before writing.** Wait for an execution (`wait_execution`, or `reset_workload`) before
  writing a host-visible buffer or resizing an image it uses. Deleting needs no wait.
- `readback` copies a resource out of a workload for the CPU (`readback_data` after the wait,
  `write_readback_to_file` for PNG/HDR). `raw_commands` gives the command buffer for raw Vulkan
  between Valhalla's own operations; Valhalla puts a barrier before and after whatever you record.
- **Explicit table bindings.** `bind_table_input`/`bind_table_output` put a resource in the shader's
  binding table and return its index, for shaders that pick resources per draw through `draw_data`
  (`valhalla_sampled`, `valhalla_buffer` and friends in `Valhalla.slang`). Push fields are the normal
  path; `bind_shader_output` declares that a push-field image or buffer is written.

## Windows and input

The input API mirrors GLFW's, renamed to Valhalla's style: `poll_events`, `wait_events`, `key_down`,
`cursor_position`, per-window callbacks such as `set_key_callback` (each returns the previous one),
plus monitors and fullscreen (`Monitor.odin`), gamepads (`Gamepad.odin`), clipboard and cursors.
Callbacks receive the `Window` by value; `set_window_user_pointer` carries your own state into them.

A library that needs to see input without taking the window's callbacks installs an
`Input_Observer` with `set_input_observer`: it is called before the window's own callback for key,
text, mouse button, cursor position, cursor enter, scroll and focus events, and the application can
set or replace its callbacks at any time.

## Dear ImGui

`src/imgui` (package `Valhalla_ImGui`) is a backend on top of Valhalla; Valhalla itself never imports
it.

```odin
valhalla_imgui.init(window, target.format) or_return
defer valhalla_imgui.shutdown()

// each frame
valhalla_imgui.begin_frame()
imgui.Begin("Window") ... imgui.End()
drawn := valhalla_imgui.end_frame(&frame, cleared) or_return
```

`begin_frame` feeds ImGui the window state and starts its frame; `end_frame` renders the draw data
into the image and returns its next version. Show a Valhalla image with
`imgui.Image(valhalla_imgui.texture(image), size)`; the id is valid for the frame it was made in.
Input arrives through an `Input_Observer`, so the application's callbacks are untouched. ImGui draw
callbacks are not supported.

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

The Slang binding's tests run with `odin test src/slang/tests -define:SLANG_LIB_DIR=../../libs`.

## License

MIT.
