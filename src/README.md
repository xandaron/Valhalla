# Valhalla API Design

Valhalla is the proposed public API for the graphics package: resources are input state, a workload is a
recorded set of operations, and a workload result is output state. The name is a placeholder; Bragi fits
the Norse theme of Odin better.

The sketch lives in this folder, one file per area: Device, Memory, Window, Surface, Buffer, Image, Shader and
Workload.

The demo in `demo/` runs on Valhalla (see The demo, below).

## Principles

- **Keep Vulkan out of the user's way.** The user should not need to know Vulkan to draw.
- **Never trap the user.** Anyone who needs to can call Vulkan directly on our structs. As long as they
  respect our data structures, the package respects resources they define themselves.
- **Constrain rather than mirror.** We expect to limit what the API exposes, and grow it when a real need
  appears.
- **Small scope.** The package covers graphics, the window and input. imgui and shader reflection live
  outside it.

## Naming and conventions

Valhalla follows Odin's standard style, a deliberate break from the camelCase the demo uses.

| Kind | Style | Example |
| --- | --- | --- |
| Types | Ada_Case | `Shader_Recording`, `Image_Settings` |
| Procedures and variables | snake_case | `make_image_from_file`, `index_count` |

- Every resource is created with `make_*` and destroyed with `delete_*`: `make_window`/`delete_window`,
  `make_surface`/`delete_surface`, `make_shader`/`delete_shader`, `delete_workload`.
- Variants sit behind an overload group named after the general case: `make_image` covers
  `make_image_from_file`, `make_image_from_memory`, `make_image_from_buffer` and so on.
- **A proc whose only parameter would be a settings struct takes parameters with defaults instead**
  (`init`, `make_window`, `make_image`'s empty variant, `make_workload`), so a call names only what it
  changes. Procs that take a settings struct alongside other arguments keep the struct
  (`make_buffer(size, settings)`, `make_image(memory, settings)`, `make_surface(window, settings)`).
- Copies between resources are named by direction: `load_X_to_Y` and `write_X_to_Y`.

## Device and initialisation

Valhalla uses a single device, created by `init` and destroyed by `shutdown`. It is package state, not a
handle, so no other call takes a device parameter.

- **Valhalla chooses the GPU.** The user does not pick a physical device.
- **The user supplies device settings** at startup, including any Vulkan extensions their shaders need.
  Beyond that, device creation stays inside the package.
- **Multiple devices are a goal, not yet supported.** Supporting them would turn the device into a handle
  that resources, shaders and workloads belong to, so keep that change cheap: avoid designs that assume
  only one device exists beyond the package state itself. It would also mean loading device functions
  into per-device tables (`vk.load_proc_addresses_device_vtable`) instead of the global pointers used now.

Implemented in `Device.odin`. `init(...)` starts GLFW, creates the instance and debug messenger,
picks the GPU and creates the logical device; `shutdown` tears all of it down. If `init` fails partway it
cleans up what it made.

**Raw Vulkan.** The device is the public package variable `device`, and a user who needs Vulkan reads
its fields directly (`Valhalla.device.handle`, `.instance`, `.physical_device`, the queues and their
families, the device `properties` with its limits, memory and descriptor heap properties, and
`dynamic_state_properties`). There are no getter procs.

**`init`'s parameters**, all with defaults so a call names only what it needs
(`Valhalla.init(app_name = "My App")`):

| Parameter | Default | Meaning |
| --- | --- | --- |
| `app_name`, `app_version` | `""`, `0` | Passed to the Vulkan instance |
| `instance_extensions` | none | Extra instance extensions; `init` fails with `.Missing_Instance_Extension` if one is unavailable |
| `device_extensions` | none | Extra device extensions; a GPU without all of them is never picked |
| `features` | none | A `Device_Features`: core, 1.1, 1.2, 1.3 and 1.4 feature structs; their booleans are merged into Valhalla's own request, and a GPU without them is never picked |
| `feature_chain` | `nil` | A `pNext` chain of the user's own feature structs (for extension features such as compute derivatives), appended after Valhalla's chain at device creation |

Duplicates of extensions Valhalla already enables are dropped. Two rules for `feature_chain`, because
Valhalla cannot read structs whose types it does not know:

- It is not checked while picking the GPU. An unsupported feature there makes `init` fail with
  `.Unsupported_Feature` instead of steering the choice.
- It must not repeat a struct type Valhalla already chains (the 1.1–1.4 structs, descriptor heap, untyped
  pointers, memory priority, pageable memory, swapchain maintenance 1). Vulkan forbids duplicates in a
  `pNext` chain; set those through `features` instead.

**Optional features** are enabled when the chosen GPU has them, without affecting the choice, and
`device.optional` says which: `multi_draw_indirect` (several draws per indirect command),
`draw_indirect_count` (the `_count` draws), and `mesh_shader`, `task_shader` and
`multiview_mesh_shader` from `VK_EXT_mesh_shader`, whose extension and feature struct Valhalla chains
itself unless the application lists the extension in `device_extensions`. Procs that need one assert
on it, and a shader with mesh or task stages fails with `.Unsupported_Stage` without it.

**Pipeline cache.** The application owns its pipeline caches; Valhalla never loads or saves one on its
own. A cache is consulted only when a pipeline is built, so it is passed where pipelines are made,
`Shader_Config.pipeline_cache`, and a shader keeps it for `reload_shader`. It cannot go to `init` (a
cache belongs to the logical device `init` creates) and would do nothing on a workload (recording and
executing build no pipelines).

```odin
cache, cache_err := Valhalla.make_pipeline_cache("app.pipeline_cache")
if cache_err != nil {
	cache = Valhalla.make_pipeline_cache() or_return
}
defer Valhalla.delete_pipeline_cache(&cache)
defer _ = Valhalla.write_pipeline_cache_to_file(cache, "app.pipeline_cache")

shader, _ := Valhalla.make_shader(code, entry_points, settings, {pipeline_cache = cache, push_type = Push}) or_return
```

- `make_pipeline_cache()` makes an empty one; `make_pipeline_cache(filename)` loads a file, returning
  `.Pipeline_Cache_File_Read_Failed` when it cannot be read (the first run) and
  `.Pipeline_Cache_Incompatible` when its header does not name this GPU, driver and cache UUID, so the
  caller decides whether to fall back to an empty cache.
- `write_pipeline_cache_to_file(cache, filename)` writes through a temporary file and a rename, so a
  crash mid-write cannot leave a torn cache. `delete_pipeline_cache` destroys it; pipelines built with
  it are unaffected.
- **One cache for the whole program is the usual choice.** Vulkan pipeline caches are internally
  synchronised, so one can be shared by every shader and thread, and the driver deduplicates inside it.
  Several caches only buy separate files (per tool, per plugin); they can be used side by side, one per
  `Shader_Config`.
- The zero `Pipeline_Cache` means none, which is what every example except the image editor uses. The
  editor keeps `image_editor.pipeline_cache` in its working directory (ignored by git), covering its
  node shaders and the user's custom shaders. Tested: a missing file, a garbage file
  (`.Pipeline_Cache_Incompatible`), and a 42 KiB cache for four lit pipelines written, then loaded; the
  editor's 125 KiB cache written and loaded on its next run. The time saved on this machine is small
  (about 470 to 420 ms for the four, dominated by Slang compiling), since NVIDIA keeps its own shader
  cache; drivers without one gain more.

**Debug names and labels**, when `VK_EXT_debug_utils` is available (`device.debug_utils`):
- Objects carry names: `Buffer_Settings.name`, `make_image(..., name)` and `Image_Settings.name`,
  `Shader_Config.name`, and `make_workload(name = "workload")`. Unnamed things get useful defaults: an
  image loaded from a file is named after the file, a shader after its entry points
  (`lit_vertex+lit_fragment`), and image views after their image and range. A resized image keeps its
  name.
- Command buffers carry labels: each workload's whole recording is labelled with its name, each
  `bind_shader` with the shader's name (inside its rendering scope), and each clear, copy, blit and
  readback with the operation.
- Validation messages show both, after the message: `COMMAND_BUFFER "named frame"` and `in "named
  frame"`, so a message says which object and which pass it came from. RenderDoc and Nsight show the
  same names and the label tree.

**Choosing the GPU** follows the old engine's `pickPhysicalDevice`. A device must have graphics, compute and
present queue families, support every requested feature and extension, and is then scored: +1000 for a
discrete GPU, +100 each when graphics shares a family with present or with compute, plus its maximum 2D
image size. Two things differ, because `init` runs before any window exists:

- Present support is checked with `glfw.GetPhysicalDevicePresentationSupport`, which needs no surface,
  instead of `vkGetPhysicalDeviceSurfaceSupportKHR`.
- The old engine's swapchain check (the surface offers at least one format and present mode) moves to when a
  window is first presented to.

**What Valhalla always requests.** Instance: validation layer with synchronisation validation (hard-coded,
as debug tooling is), debug utils, swapchain colour space, surface capabilities 2 and surface
maintenance 1. Device: the same extensions as the old engine (swapchain, memory budget, descriptor heap,
untyped pointers, memory priority, pageable device-local memory, swapchain maintenance 1), and the
features Valhalla itself relies on (shader draw parameters, timeline semaphores, buffer device address,
synchronisation 2, dynamic rendering, maintenance 5, descriptor heap, untyped pointers, memory priority,
pageable memory, swapchain maintenance 1, cube image arrays for `.Cube_Array` images, sampler
anisotropy for `make_sampler`, and non-solid fill, depth clamp and depth bias clamp for the dynamic state
setters, and multiview for shaders with a view mask). Compute derivatives, which the old engine also uses, are
left for the application to request.

Valhalla also requires `VK_EXT_extended_dynamic_state3`, which the old engine does not, with its polygon mode,
rasterization samples, sample mask, alpha-to-coverage, depth clamp, colour blend enable, colour blend
equation and colour write mask features. Those let shaders leave that state to workloads (see Shaders).

Present wait (`VK_KHR_present_wait2`) is not enabled yet. It must be switched on at device creation, so
`init` will need to enable it when the GPU supports it, ahead of presentation landing.

Valhalla also requires `VK_KHR_unified_image_layouts`. With it, `GENERAL` is an optimal layout for
attachments, sampling, storage and transfers alike, so every image Valhalla works with sits in `GENERAL`:
attachments, uploads, bound images and descriptors all use it. Only presenting still transitions (to
present layout), and an image's first use transitions from undefined.

### Descriptor heap

One global heap, written once. Implemented in `Heap.odin`; `init` opens it and `shutdown` closes it. Tested on the
GPU: a compute workload read a bound buffer and wrote a bound storage buffer and storage image; a graphics
workload pulled its triangle's positions from a storage buffer and sampled the compute's output; waiting
only on the graphics workload pulled the compute in; enforcement reads returned zero; the validation
layer was silent.

- **Layout.** The resource heap holds the driver's reserved range, then a buffer region (16,384 storage
  buffer descriptors) and an image region (16,384 image *pairs*); about 1.3 MiB on the 4060 Ti. The
  sampler heap holds its reserved range and 256 sampler slots (8 KiB). Both are host-visible, bound once
  at the start of every workload's command buffer.
- **Written once, at creation.** `make_buffer` takes a buffer slot (if the buffer has `.Storage` usage) and
  writes its descriptor; `make_image` takes an image pair: a sampled descriptor and, next to it, a storage
  descriptor, so the shader picks how to use an image without declaring an access mode. Usage an image
  lacks gets the null image's descriptor in that half. Deleting returns the slot, which can be reused at
  once (deleting already requires the resource not to be in use). Combined depth-stencil images get no
  slots, since a descriptor can only see one aspect; a depth-only or stencil-only view of them does (see
  Image views). Multisampled images get none yet. `make_sampler` takes a sampler slot and writes it straight from a
  `VkSamplerCreateInfo`; there are no `VkSampler` objects.
- **Null resources** occupy slot 0 of each region: a zeroed 16-byte buffer, a cleared 1×1 image, and a
  linear, repeating sampler (`make_sampler`'s defaults).
- **Resources reach shaders two ways.** The usual one is the push struct: a field of type `Image`,
  `Buffer` or `Sampler` becomes a `DescriptorHandle` in the shader, and Valhalla writes the resource's
  global heap index into it when the shader is bound (see Resources in push data). The user never
  handles an index. The low-level way, `bind_shader_input`, returns a *local* index into a per-bind
  table, for resources whose number is only known at runtime, such as imgui's textures picked per draw
  by `draw_data`.
- **An index table per shader bind.** Every `bind_shader` that has `bind_shader_input` or
  `bind_shader_output` bindings writes a small table into host-visible memory the
  workload owns (allocated in 16 KiB chunks): a count, the null buffer, null image and null sampler
  indices, then one entry per resource the shader bound (at most `SHADER_BINDING_CAPACITY`, 4092: the 16 KiB chunk less the four header words), holding
  its global index. Image entries carry tag bit 31 and sampler entries bit 30, so a local index can only
  be read as the kind of resource it was bound as. `reset_workload` frees the tables. A bind with no such
  bindings (every resource in its push struct) writes no table.
- **Push data.** Valhalla owns the first 16 bytes (`PUSH_HEADER_SIZE`): the table's address, the draw's
  `draw_data` and 4 reserved bytes (`ValhallaHeader { uint* table; uint draw_data; uint reserved; }`). User
  push data starts at byte 16, so a shader struct whose first field is a `float4` still lines
  up. `set_push_data` checks the total fits the device's push data size (256 bytes here).
- **Draw data.** `draw_vertices`, `draw_indexed`, `dispatch` and `dispatch_threads` take an optional
  `draw_data: u32` (0 by default), which the shader reads as `push.header.draw_data`. It is deliberately
  just one integer, meant to be a buffer index or similar small value. Per-draw data of any size goes in
  a buffer the application fills and indexes with it. It exists so that the instance index can mean a
  model instance again, rather than being borrowed as a draw index. Push data stays per bind:
  `set_push_data` is one block for every draw of a bind, so a recording can still be re-bound with new
  push data, as the lighting example does per light. The replay pushes the first command's value with
  the header, then the 4 bytes at offset 8 only when the value changes from one command to the next.
- **Push type.** A shader that reads push data past the header declares the Odin struct that matches
  it: `Shader_Config.push_type`, e.g. `{push_type = Push, colour_formats = {0 = format}}`. When the shader is
  made, or reloaded, Valhalla matches the struct against the shader's push block and builds a packing plan.
  `set_push_data(&shader, value)` then only asserts that `value`'s type is the declared one, a `typeid`
  comparison, and keeps a copy of it. Leaving `push_type` unset on a shader with push fields, or setting it
  on one without, asserts at creation. This is runtime rather than compile time on purpose: a parametric
  `Shader($Push)` would spread into every signature that takes a shader, and lose the freedom to pick
  and reload shaders at runtime.
- **Matching.** Valhalla flattens the push struct from SPIR-V into scalar leaves, each with a byte offset, a
  kind (float, integer, bool, pointer) and a width. It follows member offsets, vectors, matrices (by
  `MatrixStride` and row/column-major decoration), arrays (by `ArrayStride`) and nested structs, and names
  each leaf from `OpMemberName`, e.g. `p0[2]` or `basis[1][0]`. The 16-byte header is skipped. The
  declared type is flattened the same way through Odin's `type_info_of` (struct fields, arrays, enumerated
  arrays, SIMD vectors, matrices by `elem_stride` and layout, enums and bit sets as their integers),
  except that a field of type `Image`, `Buffer` or `Sampler` is one resource leaf. Both lists are sorted
  by offset and matched **in order**: every Odin leaf meets the next shader leaf with the same width and a
  compatible kind (floats meet floats; signed, unsigned, bool and pointer are interchangeable), and when
  both belong to the same top-level field their paths must match too, which catches element order inside
  matrices and arrays. Matrix leaves are named by storage, `[vector][element]` in memory order, so how a
  compiler labels rows and columns does not matter. A resource leaf meets one `uint` or one
  `DescriptorHandle` (a `uint2`). Leaves left over on either side are a mismatch. It panics with the first
  diverging leaf, e.g. *Push data mismatch between the shader's push struct and Swapped: the shader has
  f32 (float) `v[0]` at byte 16 where Swapped has Buffer `v`.*
- **Packing.** Because leaves are matched by order rather than by offset, **the Odin struct does not have
  to reproduce std430's padding**: the plan copies each run of leaves from its Odin offset to the shader's,
  merging runs that are contiguous on both sides (a struct that already matches is one copy). An Odin
  `[4]f32` after an `f32` lands at the shader's 16-byte boundary, and an Odin `matrix[3,3]f32` fills a
  `float3x3`'s padded columns. Declaring explicit padding still works, as long as the shader declares
  the same fields. The plan is applied when the shader is bound, not in `set_push_data`, so it sees every
  binding however the calls are ordered, and a `reload_shader` that changes the push block simply
  repacks the kept value with the new plan.
- Tested: a compute shader writing back a struct whose Odin side has an unpadded `float4`, a resource in a
  nested struct, an output buffer bound after `set_push_data`, a storage image and an empty field; a
  `float3x3` from a `matrix[3,3]f32`; mismatches for a float where the shader has a buffer, a missing
  field and an extra field; and every example converted, rendering as before.
- `bind_shader` asserts that a shader whose push block goes past the header had push data set.
- **Resources in push data.** A push field of type `Image`, `Buffer` or `Sampler` is declared in Slang as
  a typed `DescriptorHandle`, which Slang lets the shader use as the resource itself:

  ```odin
  Push :: struct {
  	transform: matrix[4, 4]f32,
  	vertices:  Valhalla.Buffer,
  	albedo:    Valhalla.Image,
  	linear:    Valhalla.Sampler,
  	target:    Valhalla.Image,
  }

  Valhalla.reset_shader(&shader)
  written, _ := Valhalla.bind_shader_output(&shader, target) or_return
  Valhalla.set_push_data(&shader, Push{transform, vertices, albedo, linear, target})
  ```

  ```slang
  import Valhalla;
  struct Push {
  	ValhallaHeader header;
  	float4x4 transform;
  	DescriptorHandle<StructuredBuffer<Vertex>> vertices;
  	DescriptorHandle<Texture2D<float4>> albedo;
  	DescriptorHandle<SamplerState> linear;
  	DescriptorHandle<RWTexture2D<float4>> target;
  };
  [[vk::push_constant]] ConstantBuffer<Push> push;

  Vertex vertex = push.vertices[vertex_id];
  float4 colour = push.albedo.Sample(push.linear, uv);
  push.target[pixel] = colour;
  ```

  - When the shader is bound, each resource field gets its heap index (a `DescriptorHandle` is a `uint2`
    in this mode, the index and a zero). An image gets its sampled descriptor, or its storage descriptor
    when the same image (the same view) is also bound with `bind_shader_output`; a buffer's descriptor
    serves both. Every field not bound as an output is recorded as a read of the version it holds, so the
    version graph and barriers see push resources like any other binding: put a written version in the
    field (the lighting example passes the shadow map version its depth pass wrote).
  - An empty field, a zero `Image`, `Buffer` or `Sampler`, reads as the null resource, so passes that share
    one push struct can leave out what they do not use. A real resource without a descriptor asserts.
  - Arrays and nested structs work: `[4]Valhalla.Image` matches `DescriptorHandle<TextureCube<float>>
    maps[4]` (the lighting example's point shadow maps).
  - `bind_shader_output` is still how a write is declared, since it returns the next version; it also
    still returns a local index for the table path.
  - Each resource costs 8 bytes of push data, so the device's 256 bytes leave room for about thirty
    after the header, fewer alongside matrices.
- **The table path.** `shaders/Valhalla.slang` keeps the helpers for local indices from
  `bind_shader_input`: `valhalla_buffer<T>(push.header, index)`, `valhalla_rw_buffer`,
  `valhalla_sampled<Texture2D<float4>>`, `valhalla_storage`, `valhalla_sampler` and
  `valhalla_comparison_sampler`. An out-of-range local index, or one used as the wrong kind, resolves to the
  null resource. Valhalla_ImGui uses this path for its per-draw textures, and push fields for its vertex
  buffer and samplers.
- Every workload's command buffer starts with a global memory barrier, so writes from earlier
  submissions (uploads, other workloads) are visible to everything it binds.

### Device memory

Ported from the old engine's hand-rolled sub-allocator (deliberately not VMA), and living in `Memory.odin`
next to the device it allocates from. Package-private: `allocate_memory(requirements, properties,
usage, dedicated)` and `free_memory(&allocation)`. The `Allocation` it returns is public (memory,
offset, size, mapped pointer) so raw-Vulkan users can see what backs a resource.

- **Blocks.** One `vkAllocateMemory` block per memory type and usage, first-fit with coalescing on free.
  The first block of a kind is 8 MiB and each new one doubles, up to 64 MiB.
- **Linear and optimal never share a block.** `Memory_Usage` (`.Linear` for buffers and linear images,
  `.Optimal` for optimal images) keeps them apart, which sidesteps `bufferImageGranularity` by
  construction. Preserve that separation.
- **Dedicated allocations** for anything 16 MiB or larger, or when the driver prefers or requires one.
- **Host-visible memory is persistently mapped**; an allocation's `mapped` points at its own bytes.
- **Budget aware.** `VK_EXT_memory_budget` is checked before growing a heap: a new block shrinks towards
  the request if the heap is near its budget, and `.Out_Of_Budget` is returned if even that will not fit.
- **Priorities** through `VK_EXT_memory_priority`: dedicated allocations high, blocks medium.
- **Every allocation can be used by device address** (`VkMemoryAllocateFlagsInfo{DEVICE_ADDRESS}`),
  because descriptor heap writes describe buffers by address.
- **Leak report.** `shutdown` logs live blocks and allocations and the lifetime totals, and warns about
  any block with bytes still allocated or dedicated allocation never freed. Like the old engine's, it depends
  on a clean exit.

Tested: 40 small images shared one 8 MiB block, a 64 MiB image was given a dedicated allocation, a freed
range was reused, and a deliberately leaked image was reported at shutdown (exactly its 65,536 bytes).
A clean run reported nothing live.

### Staging

Ported from the old engine's staging ring, also in `Memory.odin`. One persistently mapped 64 MiB host buffer
used as a ring, paced by a timeline semaphore, with uploads accumulating into one command buffer per batch.
It is created on first use, so an application that never uploads does not pay for it. Package-private:
`stage(size)` reserves space (returning the buffer, offset and mapped pointer), `staging_commands()`
returns the batch's command buffer, `flush_staging()` submits it, and `upload_to_buffer` is ready for
buffers.

- **Uploads larger than the ring** get their own temporary host buffer. Unlike the old engine, which frees those
  only on a full staging wait, Valhalla frees each one as soon as the batch that used it completes.
- **When the ring is full** the oldest batch is waited on before its space is reused; a batch's command
  buffer is reused only once the timeline has passed it.
- **Ordering.** The old engine flushes before each frame's submit. Valhalla flushes before anything reaches the
  queue: submitting a workload and presenting. Everything shares the graphics queue, so uploads always
  land before work that might read them, without the user waiting.
- **Deleting an image waits for outstanding uploads.** An image destroyed while its upload was recorded
  but not yet submitted invalidates the staging command buffer (and submitting it lost the device in
  testing), so `delete_image` first submits and waits for staging work if there is any. A deferred
  destruction queue would avoid the wait; that is a later optimisation.
- `shutdown` waits for staging work and destroys the ring before the memory leak report.

Tested: a checkerboard uploaded with `make_image_from_memory` and then loaded by a workload that drew
the triangle over it read back correctly with no explicit wait; 100 MiB of uploads wrapped through the
ring; a 256 MiB upload took the oversized path; a mip-level upload worked and malformed uploads were
refused; shutdown reported nothing live, and the validation layer was silent.

## Error handling

Every procedure that can fail returns an error, `make_*` included, so the caller can always tell why a
call failed. A zero-value result is not used as a failure signal.

`Error` is a union of one enum per area (`Device_Error`, `Window_Error`, `Input_Error`, `Surface_Error`, `Shader_Error`, `Workload_Error`, `Image_Error`, `Sampler_Error`, `Memory_Error`, `Staging_Error`, `Buffer_Error` and `Heap_Error`), sharing a nil value,
so `or_return` works across areas and `err != nil` means failure. It lives in `Device.odin`.

## Window

Implemented in `Window.odin` on top of GLFW, so it is portable as written.

| Proc | Does |
| --- | --- |
| `make_window(title, size, position, resizable, focus_on_show)` | Creates and shows a window |
| `delete_window` | Destroys it |
| `should_close` / `request_close` | Read or set the close flag |
| `window_size`, `window_framebuffer_size` | Size in screen coordinates and in pixels |
| `window_position` | Returns `.Unsupported_On_Platform` on Wayland, which does not expose it |
| `window_content_scale` | The DPI scale of the monitor the window is on |
| `window_focused`, `window_hovered` | Whether the window has input focus, and whether the cursor is over it |
| `set_window_title` | Changes the title |
| `set_window_user_pointer` / `window_user_pointer` | The application's own pointer, for callbacks to find their state |

`make_window`'s parameters all have defaults: `title = ""`, `size = {1280, 720}`, `position = nil`,
`resizable = true` and `focus_on_show = true`, so `Valhalla.make_window(title = "My App")` is enough. A
position is ignored on Wayland, and also when it falls outside every monitor's work area, so a window
saved on a disconnected monitor still opens on screen.

GLFW has one explicit lifetime: `init` starts it and installs the error callback, and `shutdown`
terminates it. Both are called once, on the main thread, at the start and end of the program;
`make_window` asserts that `init` has run. GLFW is not restarted per window because terminating it
unloads the Vulkan loader (every `vk.*` pointer comes through `glfw.GetInstanceProcAddress`) and
destroys monitor and cursor handles.

### Input

In `IO.odin` (with the per-platform `IO_windows.odin`, `IO_darwin.odin` and `IO_unix.odin`), a thin forward of GLFW's input API: the same procedures, callbacks and semantics, so GLFW's
documentation applies. Names follow Valhalla's style rather than GLFW's: queries have no `get_` prefix
(`cursor_position`, `joystick_axes`, `clipboard_text`, `time`), held-state queries return `bool`
(`key_down`, `mouse_button_down`, from `glfwGetKey`/`glfwGetMouseButton`), `pos` is `position`, `char`
is `text`, iconify/maximize are `minimise`/`maximise`, and `glfwPostEmptyEvent` is `wake_events`.
Setters and callback setters keep `set_` (`set_scroll_callback`). The types change too. Each
GLFW constant group is an Odin enum whose values *are* GLFW's (`Key.A = glfw.KEY_A`,
`Cursor_Mode.Disabled = glfw.CURSOR_DISABLED`), so converting is a cast, and the bit sets (`Modifiers`,
`Hat`) and `Gamepad_State` share GLFW's layout, pinned by `#assert`s. Pairs of coordinates are `[2]`
arrays. Resource lifetimes follow Valhalla's `make_*`/`delete_*` rule. There is no event queue: input
arrives through callbacks during `poll_events`/`wait_events`, or is polled.

**Event loop.**

| Proc | GLFW |
| --- | --- |
| `poll_events`, `wait_events`, `wait_events_timeout(seconds)`, `wake_events` | `glfwPollEvents`, `glfwWaitEvents`, `glfwWaitEventsTimeout`, `glfwPostEmptyEvent` |
| `time`, `set_time` | `glfwGetTime`, `glfwSetTime` |
| `set_frame_callback(callback, user_data)` | None; see below |

The pumping procs return an `Error`: the error a frame callback returned while they ran, if any. They
assert they are not called from inside a callback, which GLFW forbids.

**Frames during a resize.** Dragging a window border or title bar on Windows, and live resize on macOS,
run the platform's own modal loop inside `poll_events`, so it does not return until the drag ends and an
application's frame loop stalls with it. `set_frame_callback(proc(user_data: rawptr) -> Error,
user_data)` hands Valhalla the application's frame body, which it then calls whenever it is stuck inside
`poll_events`/`wait_events` and a frame is due: from GLFW's window refresh and (non-zero) framebuffer size
callbacks, and from a timer that runs for the length of the drag. The timer lives in the platform files.
`IO_windows.odin` subclasses each window's procedure and runs an 8 ms `WM_TIMER` between
`WM_ENTERSIZEMOVE` and `WM_EXITSIZEMOVE`. `IO_darwin.odin` adds one `NSTimer` to
`NSRunLoopCommonModes`, which includes the live-resize tracking mode, and ignores it outside a pump.
`IO_unix.odin` is empty because X11 and Wayland keep `glfwPollEvents` returning. The callback never
runs re-entrantly, and after it returns an error it is not called again until that pump returns the
error. The macOS path is untested, since it was written without a Mac.

The frame body is then shared between the loop and the callback:

```odin
Valhalla.set_frame_callback(draw_frame, rawptr(&scene))
defer Valhalla.set_frame_callback(nil)
for !Valhalla.should_close(&window) {
	Valhalla.poll_events() or_return
	draw_frame(&scene) or_return
}
```

A frame body cannot call `wait_events` itself, since it may be running inside one. The examples have
`draw_frame` record that the surface is minimised, and the loop waits instead of polling while it is.
Tested by an in-process stand-in for a border drag: a window procedure that sends `WM_ENTERSIZEMOVE`, runs
its own message loop for 1.5 s while resizing the window six times, then sends `WM_EXITSIZEMOVE`.
`poll_events` was held for the whole 1.5 s and 107 frames were rendered inside it, covering all six
swapchain sizes. The validation layer was silent and nothing leaked.

**Callbacks.** Each `set_*_callback(&window, callback)` replaces that window's callback and returns the
previous one; `nil` removes it. Callbacks are ordinary Odin procedures that receive the `^Window` they
fired for, and they run with the context `init` was called with. GLFW's own user pointer belongs to
Valhalla, so state reaches callbacks through `set_window_user_pointer`/`window_user_pointer`, which
behave like GLFW's.

| Setter | Callback signature after `window: ^Window` |
| --- | --- |
| `set_key_callback` | `key: Key, scancode: i32, action: Action, modifiers: Modifiers` |
| `set_text_callback` | `codepoint: rune` (use this for text entry) |
| `set_mouse_button_callback` | `button: Mouse_Button, action: Action, modifiers: Modifiers` |
| `set_cursor_position_callback`, `set_scroll_callback` | `position: [2]f64`; `offset: [2]f64` |
| `set_cursor_enter_callback`, `set_window_focus_callback` | `entered: bool`; `focused: bool` |
| `set_drop_callback` | `paths: []string`, valid only during the call |
| `set_window_position_callback`, `set_window_size_callback`, `set_framebuffer_size_callback` | `position`/`size: [2]i32` |
| `set_window_minimise_callback`, `set_window_maximise_callback` | `minimised: bool`; `maximised: bool` |
| `set_window_content_scale_callback` | `scale: [2]f32` |
| `set_window_close_callback`, `set_window_refresh_callback` | Nothing more. As in GLFW, the close flag is set before the close callback runs |

`set_joystick_callback(callback)` is global, as in GLFW: `proc(joystick: int, event: Connection_Event)`.

**Keyboard and mouse.**

| Proc | Returns |
| --- | --- |
| `key_down(&window, key)`, `mouse_button_down(&window, button)` | Whether the key or button is held now |
| `key_name(key, scancode)`, `key_scancode(key)` | The layout-specific printable name (GLFW-owned, valid until the next call), and the platform scancode |
| `cursor_position` / `set_cursor_position` | The cursor in window (screen) coordinates, as `[2]f64` |
| `cursor_mode` / `set_cursor_mode` | `.Normal`, `.Hidden`, `.Disabled` (hidden and locked, unbounded motion) or `.Captured` |
| `set_sticky_keys`, `set_sticky_mouse_buttons`, `set_lock_key_modifiers` | `glfwSetInputMode` for those modes; lock-key mods must be on for `.Caps_Lock`/`.Num_Lock` to appear in `Modifiers` |
| `raw_mouse_motion_supported`, `set_raw_mouse_motion(&window, enabled)` | The latter returns `.Unsupported_On_Platform` where unsupported |

Types: `Key` (GLFW's key set, digits as `.Digit_0`… and keypad keys as `.Keypad_0`…, plus `.Unknown`),
`Action` (`.Release`, `.Press`, `.Repeat`), `Mouse_Button` (`.Left`, `.Right`, `.Middle`,
`.Button_4`…`.Button_8`), and `Modifiers`, a bit set of `.Shift`, `.Control`, `.Alt`, `.Super`,
`.Caps_Lock` and `.Num_Lock`.

**Injected input.** `inject_key`, `inject_text`, `inject_mouse_button`, `inject_cursor_position`,
`inject_cursor_enter`, `inject_scroll` and `inject_focus` take a window and the same arguments as the
matching callback, and call that window's installed callback exactly as GLFW's event would. Anything
chained onto the callbacks (`Valhalla_ImGui` included) sees an injected event as a real one, so tests and
remote control drive an application through its real input path without touching the operating system's
input. Polling (`key_down`, `mouse_button_down`, `cursor_position`) still reports the real devices.
Injecting from inside a callback is allowed; it just calls the callback directly.

**Cursors.** `make_standard_cursor(shape)` (`Cursor_Shape`: GLFW's ten standard shapes) and
`make_cursor(pixels, size, hotspot)` (RGBA8, non-premultiplied, `size.x * size.y * 4` bytes) return a
`Cursor`, or `.Cursor_Creation_Failed` where the platform lacks the shape. `set_cursor(&window, cursor)`
applies one and `nil` restores the default; `delete_cursor` frees it.

**Clipboard.** `clipboard_text()` (GLFW-owned, valid until the next call or clipboard change;
empty when the clipboard holds no text, without logging GLFW's "format unavailable" error) and
`set_clipboard_text(text)`.

**Joysticks and gamepads.** Ids run from `0` to `MAX_JOYSTICKS - 1`. Joysticks plugged in before `init`
raise no connection event, so scan with `joystick_present` at startup.

| Proc | Returns |
| --- | --- |
| `joystick_present`, `joystick_is_gamepad` | Whether the id is connected, and whether it has a gamepad mapping |
| `joystick_axes`, `joystick_buttons`, `joystick_hats` | GLFW-owned `[]f32`, `[]Action`, `[]Hat` |
| `joystick_name`, `joystick_guid`, `gamepad_name` | GLFW-owned strings |
| `set_joystick_user_pointer`, `joystick_user_pointer` | As GLFW's |
| `gamepad_state(joystick)` | `(Gamepad_State, ok)`: `buttons` indexed by `Gamepad_Button` (`Action`s), `axes` by `Gamepad_Axis` |
| `update_gamepad_mappings(text)` | SDL_GameControllerDB-format mappings; `.Gamepad_Mappings_Rejected` on failure |

GLFW-owned results stay valid until the same call is made again for that joystick, it disconnects, or
`shutdown`; clone what you keep.

A window's callbacks and user pointer live in Valhalla-owned memory the `Window` points at (`window.data`),
so copies of a `Window` share them; `delete_window` frees it.

**Window manipulation**, all thin wrappers over GLFW: `set_window_size`, `set_window_position` (an
error on Wayland, which has no window positions), `set_window_size_limits(window, minimum, maximum)` and
`set_window_aspect_ratio(window, ratio)` (`nil` removes a limit), `minimise_window`, `maximise_window`,
`restore_window`, `show_window`, `hide_window`, `focus_window`, `request_window_attention`,
`set_window_opacity`, `set_window_resizable`, `set_window_decorated`, `set_window_floating` (always on
top), and the queries `window_minimised`, `window_maximised`, `window_visible` and `window_opacity`.

**Monitors.** A `Monitor` wraps a GLFW monitor handle.

| Proc | Returns |
| --- | --- |
| `monitors()`, `primary_monitor()` | The connected monitors (GLFW-owned, primary first, valid until the monitors change), and the primary one with a found flag |
| `monitor_name`, `monitor_position`, `monitor_work_area`, `monitor_physical_size`, `monitor_content_scale` | Name (GLFW-owned), virtual-desktop position, the area not covered by task bars as `(position, size)`, size in millimetres, and DPI scale |
| `video_mode(monitor)`, `video_modes(monitor)` | The current `Video_Mode` (`size`, per-channel `bits`, `refresh_rate`), and every mode it supports (GLFW-owned) |
| `set_monitor_callback(proc(monitor, Connection_Event))` | Connects and disconnects, like joysticks |
| `nearest_monitor(window)` | The monitor a windowed window overlaps most (its own monitor when fullscreen, the primary one on Wayland) |
| `window_monitor(window)` | The monitor a fullscreen window is on, and whether it is fullscreen |

**Fullscreen.** `set_window_fullscreen(window, monitor, mode = nil)` makes a window fullscreen on a
monitor, at the monitor's current video mode when `mode` is `nil` (no mode switch, which most platforms
treat as borderless fullscreen) or at a mode from `video_modes` (exclusive, switching the display).
It remembers the windowed position and size the first time, and `set_window_windowed(window, position =
nil, size = nil)` goes back to them unless given others. The swapchain follows on its own: the
framebuffer size changes, so the next `acquire` or `execute_workload` rebuilds it and stale recordings
report `.Swapchain_Changed`. The `input` example toggles it with F11.

Tested with the validation layer silent: monitor enumeration (two monitors, their modes, work areas,
sizes and scales), the current mode appearing in the mode list, `nearest_monitor`, and size, position,
size limits, opacity, hide and show, minimise and restore on a window of the test's own, with the surface
following the resize. Fullscreen itself was not run in testing, since it would take over the display of
the machine it was developed on; it is two GLFW calls, but treat it as untested.

## Resources

Buffers and images are the input state of a workload; a workload can also write to them, which makes them
part of its output.

| Operation | Buffer | Image |
| --- | --- | --- |
| Create | `make_buffer`: empty, file, memory, image, buffer | `make_image`: empty, file, memory, image, buffer |
| Copy in | `load_to_buffer`: memory, image, buffer | `load_to_image`: file, memory, image, buffer |
| Copy out | `write_buffer`: file, image, buffer, surface | `write_image`: file, image, buffer, surface |
| Destroy | `delete_buffer` | `delete_image` |

- Creating or loading a resource sends its data to the GPU, where it stays until the user writes to the
  resource again. Per-frame data, such as the view-projection matrix, changes by writing to it.
- The application must make sure a resource is no longer in use by a workload before writing to it. Valhalla
  may add in-use checks, but probably will not. Valhalla does not use per-frame copies of resources, since
  they multiply with the size of the workload: per-frame data lives in one host-visible buffer, written
  after waiting for the execution that last read it (see Reusing workloads).
- Users may define their own resources with direct Vulkan calls. The package respects them as long as
  they respect its data structures.
- Workloads should take resources **by value**, not by pointer, because they will need to track
  intermediate resource states. Fixing how workloads take resources waits until images and buffers are
  both designed.

### Buffers

Implemented in `Buffer.odin` and tested on the GPU with the validation layer silent: indexed draws from
device-local index buffers (32- and 16-bit), a 1 MiB device-local buffer round-tripped byte for byte
through staging and a readback buffer, a host-visible buffer written directly at an offset,
`make_buffer_from_file`, and the error cases. The shutdown report was clean.

A `Buffer` carries what every buffer has: the `vk.Buffer`, its `size`, `usage`, device `address` (heap
writes describe buffers by address) and a `mapped` pointer when its memory is host-visible. What differs
by origin lives in `buffer.variant`:

| Variant | Made by | Holds | `delete_buffer` |
| --- | --- | --- | --- |
| `Owned_Buffer` | `make_buffer` | its allocation and memory kind | destroys the buffer and frees its memory |
| `External_Buffer` | the user, filling in a `Buffer` around a buffer made with raw Vulkan | nothing | only clears the struct |

A buffer also carries a `version`, which counts writes within a workload (see Workloads); a buffer from
`make_buffer` is version 0, the original.

`Buffer_Settings`:

| Field | Values | Meaning |
| --- | --- | --- |
| `usage` | a set of `.Storage`, `.Index`, `.Uniform`, `.Indirect` | What the buffer is bound as; every buffer also gets transfer source/destination and device-address usage. With vertex pulling there is no vertex usage: vertex data is storage. |
| `memory` | `.Device_Local` (default), `.Host_Visible`, `.Host_Readback` | Device-local is written through staging; host-visible is mapped and coherent, for data the CPU rewrites (per-frame uniforms); host-readback is mapped, coherent and cached, for reading GPU results |

- `make_buffer(size, settings)` makes an empty buffer; `make_buffer(memory, settings)` and
  `make_buffer(filename, settings)` make one and fill it. `make_buffer(&image, settings, region = {})`
  makes one holding an image region's texels, tightly packed, and `make_buffer(&buffer, settings)` a copy
  of another buffer (see Copies).
- `load_memory_to_buffer(source, &buffer, offset = 0)` copies straight into mapped memory, or goes through
  the staging ring for device-local buffers; an overrun returns `.Buffer_Out_Of_Range`. Writing a mapped
  buffer is immediate, so the buffer must not be in use by the GPU (the usual rule).
- Buffers use `.Linear` memory, so they never share a block with optimal images; a buffer gets a dedicated
  allocation when the driver prefers one or it is 16 MiB or larger.
- `delete_buffer` waits for outstanding uploads first, like `delete_image`.
- Staging now ends each batch with a global memory barrier, so staged buffer writes are visible to the
  shaders and copies that follow. Images did not need it (workloads transition them), buffers do.
- Each batch also starts with a global barrier, so an upload waits for earlier work on the queue that
  may still read or write what it overwrites (imgui updating its font atlas while the previous frame
  samples it is the case that needed it).

**In workloads.** `bind_shader_index_buffer(&shader, buffer, index_type)` gives a graphics shader its index
buffer (`.U32` by default, or `.U16`), and `draw_indexed` draws from it. There is no vertex buffer bind:
vertex data is a storage buffer the vertex shader pulls from through the descriptor heap.

### Images

Implemented in `Image.odin`: `make_image(format, size, kind = .Colour, shape = .D2, layers = 1, mip_levels = 1, samples = 1)` (the empty variant) and `delete_image`, tested on the GPU across
every shape and kind, with the validation layer silent.

An `Image` carries everything needed to use it on the GPU: the `vk.Image`, a `vk.ImageView` covering
every mip and layer, format, extent, layer count (in Vulkan layers, so 6 per cube), mip levels, sample
count, aspect, usage, its `layout`, and a `version` counting writes within a workload (see Workloads;
an image from `make_image` is version 0, the original). What differs by where the image came from lives
in `image.variant`:

| Variant | Made by | Holds | `delete_image` |
| --- | --- | --- | --- |
| `Owned_Image` | `make_image` | its memory, kind and shape | destroys the view, image and memory |
| `External_Image` | the user, filling in an `Image` around handles made with raw Vulkan | nothing | only clears the struct |
| `Swapchain_Image` | `acquire` | its surface and swapchain index | only clears the struct; the surface owns it |

**Every owned image lives in `GENERAL`.** `make_image` records the transition from undefined on the
staging command buffer, so an image is in `GENERAL` before anything can use it, and stays there: with
unified image layouts nothing else is needed. Only swapchain images start undefined (a workload moves
them to `GENERAL` on first use, and to present layout when presented), and an external image's `layout`
is whatever the user says.

An image is described on two axes, by `make_image`'s parameters or (for the procs that take data plus settings) by an `Image_Settings`:

| `kind` | Usage | Format rule |
| --- | --- | --- |
| `.Colour` | colour attachment, sampled, transfer | not a depth format |
| `.Depth` | depth/stencil attachment, sampled, transfer | a depth or stencil format; stencil formats get both aspects |
| `.Generic` | storage, sampled, transfer | the format must support storage (sRGB formats do not) |

| `shape` | `size` used | `layers` means |
| --- | --- | --- |
| `.D1`, `.D1_Array` | x | array elements (arrays only) |
| `.D2`, `.D2_Array` | x, y | array elements (arrays only) |
| `.D3` | x, y, z | ignored |
| `.Cube`, `.Cube_Array` | x, y (must be square) | cubes (arrays only); Valhalla creates 6 layers per cube |

There is no 3D array: Vulkan has no arrayed 3D images.

- `mip_levels` and `samples` of 0 mean 1. `mip_levels` only allocates levels: **Valhalla generates mips only when asked** (`generate_mips`, see Copies); until then every level past mip 0 is undefined. Asking for more
  levels than the image's size allows (11 for 1024×512) is refused. Multisampling is limited to
  single-mip 2D colour or depth images, which are then not sampled or stored.
- `format` is a `vk.Format` for now, like `Shader_Config`'s formats.
- Creation checks the settings first (`.Invalid_Settings`), then asks the device whether the format
  supports that type, usage and size (`.Unsupported_Format`).
- Cube arrays need the `imageCubeArray` feature, which Valhalla now always requests.

**Memory.** Images are suballocated through the device memory allocator (see Device), as `.Optimal`
memory; `Owned_Image.allocation` holds the memory, offset and size. An image gets a dedicated
allocation when the driver prefers or requires one, or when it is 16 MiB or larger.

**Loading data.** `load_memory_to_image(source, &image, mip_level = 0, first_layer = 0, offset = {},
size = {})` uploads tightly packed texels for one mip level through the staging ring, into one or more
layers starting at `first_layer`; `make_image_from_memory(memory, settings)` is `make_image` plus that
load. `offset` and `size` pick a region of the mip, and a zero `size` means everything from `offset` to
the mip's far corner, so the defaults load whole layers. The source must be a whole number of layers of
the region (texel size × width × height × depth each) that fits in the image,
and the format must be one Valhalla knows the texel size of (the common 8-, 16- and 32-bit colour formats
and the single-aspect depth formats; block-compressed and 3-channel 32-bit formats are not supported
yet). The upload moves the image to `GENERAL` if it is not there already, updating `image.layout`.
Combined depth-stencil images are refused. Uploads are asynchronous; Valhalla submits them before any
workload or present (see Device), so no wait is needed before using the image.

**Loading files.** Decoding goes through `vendor:stb/image`, as in the old engine, so PNG, JPEG, TGA, BMP, PSD,
GIF, HDR and PNM files load. Texels are always expanded to four channels.

- `resize_image(&image, size)` rebuilds an image made by Valhalla at a new size, with the same format,
  kind, shape, layers and sample count. The mip count is capped to what the new size allows, and the
  contents are not kept. It returns whether anything changed and does nothing when the size already
  matches, so `resize_image(&depth, image.extent)` each frame keeps a depth buffer the size of the
  swapchain. The replacement is made before the old image is deleted, so a failure leaves the original
  intact.
- `make_image_from_file(filename, kind = .Colour, srgb = true)` makes a single-mip 2D image the size of
  the file and loads it. The format follows the file: Radiance `.hdr` files become `R32G32B32A32_SFLOAT`;
  with `srgb = false`, 16-bit files become `R16G16B16A16_UNORM` and others `R8G8B8A8_UNORM`; with
  `srgb = true` (colour data) every non-HDR file becomes `R8G8B8A8_SRGB`, since there is no 16-bit sRGB
  format. Pass `srgb = false` for data such as normal maps. `kind` may be `.Colour` or `.Generic`; the
  latter fails for sRGB, which storage cannot use.
- `load_file_to_image(filename, &image, mip_level = 0, layer = 0)` decodes a file into one layer of one
  mip of an existing image, converting to the image's format, which must be `R8G8B8A8_SRGB`/`_UNORM`,
  `R16G16B16A16_UNORM` or `R32G32B32A32_SFLOAT` (`.Unsupported_Format` otherwise). The file must be
  exactly that mip's size (`.Invalid_Upload` otherwise). This is how arrays, cube faces and hand-made mip
  chains are filled from files.
- Failures are `.Image_File_Read_Failed` (missing or unreadable) and `.Image_Decode_Failed` (not an image
  stb understands), with stb's reason logged.

Tested on the GPU with the validation layer silent: a PNG loaded as UNORM and as sRGB (grey 128 sampled
as 0.2158), a 16-bit PNG as `R16G16B16A16_UNORM` (65535/32768 sampled as 1.0/0.5), an HDR file as float
(2.5, 0.5, 8.0 exactly), and two PNGs loaded into the layers of a 2D array; each error case (a missing
file, a file the wrong size, a layer past the end, a depth image) returned its error.

Sampling depth-stencil images and reading one image in two formats are done through image views (see
Image views).

### Copies

Every copy exists in two forms. **In a workload** it is an operation like `clear_image`: it reads one
version and writes the next, ordered by the version graph like any bind. **Immediately** it is a
proc on the resources themselves that goes into the staging batch, with a barrier on each side, so it is
ordered after earlier uploads and before later ones, and is submitted before the next workload. Like an
upload, it needs no wait before use, and `delete_*` waits for it.

| In a workload | Immediately | Does |
| --- | --- | --- |
| `copy_buffer(&w, source, destination, source_offset, destination_offset, size)` | `load_buffer_to_buffer(&source, &buffer, ...)` | Bytes between buffers; a zero size means the rest of the source |
| `copy_image(&w, source, destination, source_region, destination_region)` | `load_image_to_image(&source, &image, ...)` | Texels between images with the same texel size, samples and aspects; no conversion |
| `blit_image(&w, source, destination, source_region, destination_region, filter)` | `blit_image_to_image(&source, &image, ...)` | Scaling and format conversion, linear by default (`.NEAREST` for depth and for formats that cannot filter) |
| `copy_buffer_to_image(&w, source, destination, source_offset, destination_region)` | `load_buffer_to_image(&source, &image, ...)` | Tightly packed texels into an image region |
| `copy_image_to_buffer(&w, source, destination, source_region, destination_offset)` | `load_image_to_buffer(&source, &buffer, ...)` | An image region into a buffer, tightly packed |

- An `Image_Region` names `mip_level`, `first_layer`, `layers`, `offset` and `size`. The zero value is the
  whole of mip 0: zero `layers` means every remaining layer, and a zero `size` component runs to the
  mip's far edge. A copy's destination region takes its size and layer count from the source, so it
  usually only needs an offset; a blit's destination region defaults to the whole destination mip.
- A copy or blit can stay within one image or buffer when the two regions do not overlap: different
  mips or layers of an image (a blit from mip 0 to mip 1 starts a mip chain), separate byte ranges of a
  buffer.
- The `write_*` procs are the same operations named from the source's side, so `write_image_to_buffer`
  is `load_image_to_buffer`. The ones with a new destination are:
  - `write_image_to_file(&image, filename, encoded = true)` and `write_buffer_to_file(&buffer, filename)`
    read back through a one-shot workload, wait, and write PNG/HDR or raw bytes (see `write_readback`).
    They block.
  - `write_image_to_surface(&image, &surface, region, filter)` blits an image onto the surface and presents
    it; `write_buffer_to_surface(&buffer, &surface, offset)` copies texels already in the surface's format.
    Each is one workload that acquires, copies, presents and waits, for tools that only want to show a
    picture.
- **Mips.** `generate_mips(&image)` fills every mip level the image was made with from mip 0, each level
  a linear blit of the one above, every layer (cube faces and array layers) on its own. It never adds
  levels: an image needs them from `make_image(..., mip_levels = n)`, and one with a single level returns
  `.No_Mip_Levels`. It goes into the staging batch like the other immediate copies, and works on views
  too. `generate_mips(&workload, image)` is the workload form, returning the written version, ordered by
  the version graph (the image editor's display regenerates its chain this way whenever the graph runs);
  it asserts on a single-level image. sRGB formats average in linear light, since blits decode and
  encode them. Formats that cannot be blitted linearly (integers, depth, stencil) return
  `.Unsupported_Format`. Tested: a 7-level 64×64 image keeping its handle and mip 0 with every level
  averaging the one above, a 3-level sRGB checkerboard (half intensity encoding to 188), a cube with each
  face's chain kept apart, the workload form after a clear, a single-level image refused with
  `.No_Mip_Levels`, and `R32_UINT` refused.
- `make_image(&image, settings)` makes an image and copies mip 0 into it when the size, texel size and
  sample count match, and blits it (scaling, converting) otherwise. `image_settings(image)` returns the
  settings an image was made with, so `make_image(&image, image_settings(image))` clones it.
  `make_image(&buffer, settings)` fills mip 0 from tightly packed texels.
- Immediate copies need images in `GENERAL`, which every image Valhalla makes is; inside a workload,
  surface images work too (the surface procs above copy into the stand-in).

Tested with the validation layer silent: buffer clones and offset copies byte for byte, an upload, copy,
upload, copy sequence in one staging batch keeping its order, image regions at offsets, image to buffer
to image round trips, a PNG clone identical to the file, a half-size sRGB-to-UNORM blit, a workload
chain of buffer to image, mip blit, image copy, image to buffer and buffer copy, and 30 presents each
through the two surface procs.

### Image views

`make_image_view(image, mip_level = 0, mip_levels = 0, first_layer = 0, layers = 0, shape = nil)` makes an
`Image` that sees part of another: a range of mips and layers (zero counts mean the rest). It is an
ordinary `Image` to everything else (bind it, render into it, copy it, read it back, upload into it), with
the extent of its first mip, its own mip and layer counts, its own heap slots and a `View_Image` variant
holding its base mip, base layer and shape. `delete_image` destroys only the view; delete views before
their image.

- The shape follows the image unless given: one layer of a 2D array or cube is `.D2`, several are
  `.D2_Array`, six layers of a cube are `.Cube`, and a 3D image's views are 3D. A shape can be asked for
  explicitly, for example a one-layer `.D2_Array` for a shader that expects an array.
- A view rendered into is rendered at its first mip, through a single-mip attachment view. Its version is still the whole view's, so an image with mips can be rendered to, then blitted down its mip chain and sampled in the same workload (the image editor's display does this); only the check against sampling what a shader renders to narrows the attachment to its first mip.
- **Versions are per view.** The workload keys its version tracking by image and subresource range,
  so a view and the image it came from each have their own versions: writing mip 1 through a view does
  not make the image's version 0 stale. Barriers are still decided per image, so any write to an image
  orders every later access to any view of it, which is conservative but never wrong. A shader may
  sample one view while rendering into another of the same image when their ranges do not overlap
  (building a mip chain mip by mip); overlapping ones assert.
- Rendering scopes compare attachment views, not images, so two binds rendering into different mips of
  one image get separate scopes.
- **Aspect views.** `aspect = {.DEPTH}` or `{.STENCIL}` views one aspect of a combined depth-stencil
  image, which can then be sampled (`Texture2D<float>` for depth, `Texture2D<uint>` for stencil); the image
  itself has no descriptor, since a descriptor sees one aspect.
- **Format views.** `format = ...` reads the image as another format of the same texel size, such as
  `R8G8B8A8_UNORM` for an `R8G8B8A8_SRGB` texture, so one image serves as colour (decoded) and as data
  (raw). The image must list the formats when it is made: `make_image(..., view_formats = {0 =
  .R8G8B8A8_UNORM})` (also on `make_image_from_file` and `Image_Settings`; a fixed array with indexed
  literals, like `colour_formats`). That makes it `MUTABLE_FORMAT` with a format list, which keeps
  compression on drivers that honour lists. A view in an unlisted format asserts.
- An aspect or format view has its own versions (the tracking key includes both), with barriers still per
  image.
- Tested: a combined `D32_SFLOAT_S8_UINT` image cleared to depth 0.25 and stencil 7, sampled through
  depth and stencil views (0.25 and 7), and an sRGB image of 128s read through its own view (0.2158) and
  a UNORM view (0.502).

Tested with the validation layer silent: a 7-level mip chain rendered mip by mip, each pass sampling
the previous mip's view and rendering into the next (the 1×1 mip came out as the average of the whole
image), readbacks of each mip view, a clear of one face of a cube touching only that face, and an upload
into a mip view followed by a copy from its layer 0 to its layer 1.

### Samplers

A `Sampler` is a slot in the sampler heap and nothing more (`heap_index`); there is no `VkSampler`.
Implemented in `Sampler.odin`; the slot handling lives with the rest of the heap in `Heap.odin`. Making one writes its descriptor;
a shader reaches it through a `Sampler` field of its push struct, like any other resource.

```odin
linear := Valhalla.make_sampler() or_return
shadow := Valhalla.make_sampler(filter = .NEAREST, address_mode = .CLAMP_TO_BORDER, compare_op = .LESS_OR_EQUAL)
Valhalla.set_push_data(&shader, Push{albedo = texture, linear = linear})
```

`make_sampler`'s parameters, all defaulted since a settings struct would be its only parameter:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `filter` | `.LINEAR` | Minification and magnification filter |
| `mipmap_mode` | `.LINEAR` | Filtering between mips |
| `address_mode` | `.REPEAT` | Used for u, v and w alike |
| `anisotropy` | `1` (off) | Above 1 enables anisotropic filtering; must not exceed `device.properties.limits.maxSamplerAnisotropy` (`.Unsupported_Anisotropy`) |
| `compare_op` | `nil` | A comparison makes it a depth-compare sampler (`valhalla_comparison_sampler` in Slang) |
| `min_lod`, `max_lod` | `0`, unclamped | Mip range; `min_lod` must not be negative or above `max_lod` (`.Invalid_Lod_Range`) |
| `lod_bias` | `0` | Must be within the device's `maxSamplerLodBias` (`.Unsupported_Lod_Bias`) |
| `border_colour` | transparent black | For `.CLAMP_TO_BORDER` |

Out-of-range values are refused rather than clamped. The vk enum types are used directly for now, like
image formats. `delete_sampler` returns the slot, which can be reused at once, so a sampler must not be in
use by a workload when it is deleted.

- Samplers need no synchronisation, so binding one records nothing and a sampler cannot be resolved from
  a workload result.
- Per-axis address modes, separate min and mag filters, cubic filtering and unnormalised coordinates are
  left out until something needs them.

Tested with the image files above: a nearest sampler returned the texel itself next to a texel edge, a
linear one averaged the two texels at the edge, and a sampler index pointing at an image entry fell back
to the null (linear) sampler.

## Shaders

Shaders are bindless through the descriptor heap. They declare no bindings: any shader run inside a
workload can reach every resource bound to that workload, and nothing else. Each shader also takes push
constants, whose struct starts with Valhalla's `ValhallaHeader` (see Descriptor heap).

Implemented in `Shader.odin`. **A `Shader` is a `VkPipeline`** built from one or more entry points:
vertex + fragment (or mesh/task, tessellation, geometry) for graphics, or a single compute entry point.
Graphics or compute follows from the stages and is recorded in `shader.variant`: a `Graphics_Shader` (its stages and config) or a `Compute_Shader` (its thread-group size). Each kind carries only its own data, and the pipeline bind point is derived from the variant rather than stored.

**Creation.**

| Proc | Input |
| --- | --- |
| `make_shader(path, entry_points, settings, config)` | A Slang file; returns `(shader, diagnostics, err)` |
| `make_shader(code: []u8, entry_points, settings, config)` | Slang source in memory; returns `(shader, diagnostics, err)` |
| `make_shader(code: []u32, entry_points, config)` | SPIR-V from any compiler; returns `(shader, err)` |
| `make_shaders(...)` | Several shaders from one file, source or SPIR-V; compiled once, one entry point list and config per shader |
| `delete_shader`, `delete_shaders` | Destroy them |

**Diagnostics.** Compiling from Slang returns the compiler's diagnostics as a string instead of logging
them: the module, entry point, composition, link and code generation messages, warnings included, so
the text can be non-empty on success too. It is allocated with the trailing `allocator` parameter
(`context.temp_allocator` by default), so ignoring it with `_` leaks nothing. On failure the `Error` says
which step failed and the diagnostics say why, with Slang's source line and caret. Callers that use
`shader, _ := make_shader(...) or_return` drop the text; the image editor shows it in its shader editor.

Everything becomes SPIR-V first, and Valhalla reads the entry points, their stages and a compute shader's
thread-group size (`Compute_Shader.group_size`, for `dispatch_threads`) from the SPIR-V itself. So only the
source-compiling procs depend on the language. Entry points are found by name and must carry a
`[shader("...")]` attribute; Slang is told to keep entry point names in the SPIR-V, because with a
single entry point it otherwise renames it `main`.

**Source languages: Slang only, for now.** The goal is to accept any shader language (GLSL, HLSL,
Slang); this needs revisiting. SPIR-V from any compiler already works through the compiled path.

**Compiler settings.** `Compiler_Settings` holds include `search_paths` and preprocessor `defines`.
Valhalla always targets SPIR-V 1.6 with the `spvDescriptorHeapEXT` capability and column-major matrices.
One Slang global session is created on first compile and released by `shutdown`.

**The shader bakes the bare minimum.** Everything Vulkan allows to be dynamic is left to the workload:
viewport and scissor (with count), cull mode, front face, topology, depth test/write/compare/bounds/bias,
stencil, rasterizer discard, primitive restart, line width, blend constants, and through
`VK_EXT_extended_dynamic_state3` polygon mode, sample count and mask, alpha-to-coverage, depth clamp,
colour blend enable and equation, and colour write mask. Every `bind_shader` sets all of these to
defaults and the `set_*` procs recorded on the shader change them (see Workloads). Topology is dynamic only within the triangle class unless the device reports
`dynamicPrimitiveTopologyUnrestricted`.

**`Shader_Config` is a placeholder** holding what Vulkan requires at pipeline creation and cannot make
dynamic: the colour, depth and stencil attachment formats and the multiview view mask. Attachment
formats need revisiting.

`colour_formats` is a fixed `[MAX_COLOUR_ATTACHMENTS]vk.Format`, one entry per colour attachment slot,
written with indexed literals: `{colour_formats = {0 = surface.format.format}}`, or
`{0 = .R16G16B16A16_SFLOAT, 1 = .R8G8B8A8_UNORM}` for two targets. Odin does not accept a shorter
positional literal for a fixed array. The attachment count is the number of leading formats that are
set, and a gap asserts. A value type means a `Shader_Config` literal never points at stack memory, so
storing the shader anywhere raises no escape warning, and Valhalla has nothing to clone or free. Drawing
"straight into a surface" uses the surface's format, since `acquire` returns the stand-in, which has
the swapchain's format.

**Multiview.** A graphics shader made with a non-zero `view_mask` renders once per set bit in a single
pass: view *i* goes to layer *i* of every attachment, and the shader reads its view from `SV_ViewID`. The
rendering scope takes the mask from the shader (binds with different masks never share a scope), and
`bind_shader` asserts every attachment has a layer for the highest view. Rendering all six faces of a cube
is `view_mask = 0b111111` with a `.Cube` image as the attachment, as the point-light shadows in
`examples/lighting` do. To make that possible, images that are layered (arrays, cubes) or have several
mips get a second view, `attachment_view`, of type 2D array over mip 0 and every layer; attachments always
use it, while `view` (cube, array, all mips) stays the one shaders sample. Rendering into one chosen layer
of an image, or a subset of layers, still needs views of part of an image, which Valhalla does not have.

**Hot reload.** `reload_shader` (file, source or SPIR-V; the first two also return diagnostics) builds a new pipeline with the shader's existing
config and swaps it in. A recorded command buffer contains the old `VkPipeline` handle, so **reloading
invalidates every workload that used the shader**. Tracking that is the user's job.

`delete_shader` and `reload_shader` wait for the device to go idle before destroying a pipeline.
There is no pipeline cache yet.

**Reflection is out of scope.** Users who need Slang reflection import Slang themselves and write their
own loader, then hand the result to `make_shader` as code. Any other tool that generates shader code
works the same way. We may expose parts of reflection later.

## Workloads

A workload is a recorded set of GPU operations that can be executed many times without re-recording. It
covers compute as well as graphics, which is why it is not called a render, and it is not called a
pipeline because it is not a `VkPipeline`. Implemented in `Workload.odin`, with the shader side of the
recording in `Shader.odin`.

```odin
frame := make_workload() or_return

image := acquire(&frame, &surface) or_return
cleared := clear_image(&frame, image, {color = {float32 = {0, 0, 0, 1}}})

reset_shader(&triangle)
drawn := bind_shader_colour(&triangle, cleared)
draw(&triangle, 3, 1, 0, 0)
bind_shader(&frame, triangle) or_return

present(&frame, drawn)
finalize_workload(&frame) or_return
done := execute_workload(&frame) or_return
wait_execution(done) or_return
```

### Shaders carry a recording

A `Shader` is a pipeline, and it also holds a `Shader_Recording`: its bound resources, attachments,
index buffer, draws or dispatches, draw state and push data.

| Proc | Does |
| --- | --- |
| `reset_shader(&shader)` | Clears the whole recording |
| `reset_shader_bindings(&shader)` | Clears only the bindings, attachments and index buffer, keeping the draws, so the same draws can run on other resources; rebinding in the same order gives the same indices |
| `bind_shader_input(&shader, resource)` | A read of an image, buffer or sampler through the per-bind table; returns its local index. Most shaders put resources in their push struct instead (see Resources in push data) |
| `bind_shader_output(&shader, resource)` | A write through a storage image or buffer; returns the resource's next version and its local index |
| `bind_shader_colour(&shader, image)`, `bind_shader_depth(&shader, image)` | Attachments (read-modify-write); return the next version. Colour attachments fill the shader's colour formats in order, and the format must match |
| `bind_shader_index_buffer(&shader, buffer, index_type)` | The index buffer for `draw_indexed` (a read) |
| `set_push_data(&shader, value)` | The push data every draw of this binding sees, after Valhalla's 16-byte header; `value` must be the shader's `Shader_Config.push_type`. Its `Image`, `Buffer` and `Sampler` fields are bound as reads (or as the outputs they match) and packed as heap indices when the shader is bound |
| `draw_vertices`, `draw_indexed` (group `draw`), `dispatch`, `dispatch_threads` | Recorded as data |
| `draw_indirect`, `draw_indexed_indirect`, `draw_indirect_count`, `draw_indexed_indirect_count`, `dispatch_indirect` | Draws and dispatches whose parameters come from a buffer with `.Indirect` usage; see Indirect and mesh draws |
| `draw_mesh_tasks`, `draw_mesh_tasks_indirect`, `draw_mesh_tasks_indirect_count` | Mesh shader draws |
| `set_*` draw state | Recorded too; see below |

The recording is plain data, so binding it replays it. A shader is recorded once and bound as often as
needed: with new push data, with new resources after `reset_shader_bindings`, or into other workloads.
Resetting or re-recording a shader never affects a workload that already bound it.

### Indirect and mesh draws

Indirect draws take their parameters from a buffer made with `.Indirect` usage, laid out as Vulkan's
`DrawIndirectCommand`, `DrawIndexedIndirectCommand`, `DrawMeshTasksIndirectCommandEXT` or
`DispatchIndirectCommand`: `draw_indirect(&shader, buffer, offset = 0, draws = 1, stride, draw_data)`,
and the indexed and mesh forms likewise. The `_count` forms read the number of draws from a second
buffer at `count_offset`, up to `max_draws`. The buffers are reads of the bind, so a buffer written
earlier in the workload (a compute pass culling or building draws) is ordered before the draw by the
version graph like any other input: pass the written version. Checked when recorded: the usage, 4-byte
offsets and strides, a stride at least the command's size, the draws fitting the buffer, and the device
features (several draws per command need `multi_draw_indirect`, count draws `draw_indirect_count`).
Every draw of one command shares the command's `draw_data`; per-draw data comes from the draw's
instance index or the shader's own lookup.

A **mesh shader** is a graphics shader made with a `[shader("mesh")]` entry point (and optionally a
`[shader("amplification")]` task entry point) instead of a vertex one. It draws with `draw_mesh_tasks(&shader,
groups, draw_data)` or the indirect forms, and the vertex draw procs assert on it, as do `set_topology` and
`set_primitive_restart`, since a mesh shader chooses its own primitives (its pipeline leaves those two
states out). Binding one makes the next bind restate all of its draw state, because a pipeline without
those dynamic states makes them undefined.

Tested with the validation layer silent: two draws from one indirect command, an indexed indirect draw,
a count draw taking three of four commands, a draw whose command a compute shader wrote earlier in the
same workload, a five-group indirect dispatch, and a four-group mesh draw followed by a vertex draw in
the same workload. **Known issue (NVIDIA driver bug):** a task shader's payload reads as zero in the mesh shader when the
task and mesh entry points come from **one SPIR-V module**, which is how Valhalla builds every pipeline;
the group count still arrives. Found on an RTX 4060 Ti with driver 616.92. Isolated with a raw-Vulkan
repro outside Valhalla's pipeline code: the same shaders lose the payload in a combined module with or
without the descriptor heap flag, and keep it when each stage is compiled into its own module, also with
or without the flag. Loading the combined code as three separate module objects still loses it, so the
trigger is the module's contents: two entry points, each with its own `TaskPayloadWorkgroupEXT`
variable, which is valid SPIR-V (`spirv-val` accepts it). Not worked around: mesh shaders without task
shaders, and task shaders' group counts, are unaffected. If it matters before a driver fix, the
workaround is compiling the task entry point into its own module (a separate Slang compile per stage
for shaders with a task stage).

### Workloads compose shaders

`bind_shader(&workload, shader)` replays the shader's recording into the workload's command buffer, with
the shader's current bindings and push data. Each bind gets its own index table, so the bound resources
of every bind are independent.

**Order comes from versions.** Every write makes a new version of a resource, and the procs that write
return it: `bind_shader_output`, `bind_shader_colour`, `bind_shader_depth`, `clear_image` and
`clear_buffer`. The workload tracks the current version of every resource it touches.
- Reading or writing a version needs it to be the current one. Binding a version that has already been
  overwritten asserts ("bind its readers before its writer"), and so does a version that has not been
  written in this workload yet ("bind its writer first, or bind the original resource").
- **Readers of a version are bound before its writer**, so the order the code is written in is always a
  valid order. Valhalla never reorders anything and records as it goes.
- The one exception is binding the same recording again onto its own output, for example drawing more
  with new push data: that continues the version it already wrote, as long as nothing has read it yet.
- The tracking lives in the workload, not on the resource, so copies of a handle cannot dodge it and
  nothing outlives the workload. Versions are workload-local: every workload starts from the original
  handles.
- Writes are in place. Every version is the same memory as the original.

**Barriers come from the version graph.** When a bind reads something written earlier in the workload,
or writes something read or written earlier, Valhalla records a barrier first; work with no data
relationship gets none and can overlap. Barriers are coarse for now (all commands, all memory), and
any image not yet in `GENERAL` is transitioned in the same barrier.

**Rendering scopes are derived.** A graphics shader's attachments decide its rendering scope. Consecutive
graphics binds with exactly the same attachments, and nothing else needing a barrier, share one
`vkCmdBeginRendering`, so a chain of material shaders (each taking the previous one's attachment
versions) costs no extra passes. Attachments load and store; `clear_image` is the explicit clear, and is
folded into the load when it can be (see Recording costs).

**Checked at bind time:** a graphics shader binds one colour attachment per colour format it was made
with, and a depth attachment exactly when it has a depth or stencil format; all its attachments share a
size and sample count; it does not sample an image it renders to; `draw_indexed` has an index buffer;
draw state only touches attachments that exist (depth state needs depth, stencil needs stencil, blending
names a bound colour attachment).

**Draw state** is recorded per draw. Each bind starts from the defaults, and a setter changes the state
for the draws recorded after it:
- defaults: viewport and scissor covering the attachments, no culling, counter-clockwise front faces,
  triangle lists, fill mode, depth, stencil, bias and clamp off, blending off with RGBA writes, and the
  attachments' sample count;
- setters: `set_viewport`, `set_scissor`, `set_cull_mode`, `set_front_face`, `set_topology`,
  `set_primitive_restart`, `set_polygon_mode`, `set_depth_test`, `set_depth_write`, `set_depth_bias`,
  `set_depth_clamp`, `set_stencil_test`, `set_stencil` (every stencil value at once, per face),
  `set_blend` (`BLEND_ALPHA`, `BLEND_PREMULTIPLIED`, `BLEND_ADDITIVE`, or `nil` for off),
  `set_colour_write_mask`, `set_blend_constants`, `set_alpha_to_coverage`. They assert on compute shaders.
  Switching to a line or point topology needs `dynamicPrimitiveTopologyUnrestricted`.

**Other operations.**
- `clear_image(&workload, image, value)` and `clear_buffer(&workload, buffer, value)` are writes.
- `readback(&workload, image or buffer)` is a read that copies the resource into a host-readable buffer
  the workload owns, and returns a `Readback`. After an execution has finished (`wait_execution`),
  `readback_data(readback)` is the bytes: a buffer's contents, or an image's first mip with every layer,
  tightly packed in its own format. Every execution overwrites them, so read them before executing
  again. Images need transfer-source usage (every Valhalla image has it, and swapchain images do where the
  surface allows), a single aspect, and a format Valhalla knows the texel size of. The buffer is freed by
  `reset_workload` or `delete_workload`. A `Readback` of an image also carries its `format`, `extent`
  and `layers`.
- `write_readback(readback, file, encoded = true)` writes a readback to an open `^os.File` after the
  execution has finished. This is the file-handle counterpart of `readback_data`'s pointer. Encoded image
  readbacks go out as PNG (RGBA8, and BGRA8 swizzled) or Radiance HDR (RGBA32 float), streamed through
  `vendor:stb/image`'s write-to-callback. Buffer readbacks, and `encoded = false`, write the raw bytes.
  Layers and depth slices are stacked vertically. `write_readback_to_file(readback, filename, encoded)`
  opens the file and calls it. This is how an image is written to a file: draw it, read it back in the
  workload, execute, wait, write.
- `acquire(&workload, &surface)` and `present(&workload, image)`: see Surfaces in workloads, below.
- `raw_commands(&workload)` returns the workload's command buffer for raw Vulkan (there is exactly one,
  acquires or not). It closes any open rendering scope and
  records a barrier before and after, since Valhalla cannot see what raw commands touch.

### Recording costs

What a bind does to the command buffer, kept as cheap as the model allows:
- **Draw state is emitted as differences.** The workload keeps the last emitted state, including the
  resolved viewport and scissor, the sample count and the colour attachment count. Each draw state
  change sends only the fields that differ, and this carries across binds within a command buffer:
  every Valhalla pipeline declares the same dynamic state, so a pipeline bind does not reset it. The
  tracker restarts with each command buffer and after `raw_commands`, since raw Vulkan may change state.
  Equal front and back stencil state goes out as one call per setting. Line width, depth bounds and the
  depth-bounds test, rasterizer discard and the sample mask are fixed in every pipeline (1, 0..1, off,
  off, all samples) rather than being dynamic. A recording also stores consecutive identical draw states
  once, so a setter that does not change anything (imgui's repeated clip rectangles) costs nothing.
- **One push per bind.** `set_push_data` keeps the user data after a 16-byte gap, and the replay patches
  the index table's address into that gap, so the header and the data go out in one `CmdPushDataEXT`.
- **Hazards are epochs, not flags.** Each resource records the barrier epoch in which it was last
  written and last read. A barrier just advances the workload's epoch, instead of walking every
  resource to clear its flags.
- **One command buffer, reused.** A workload records into a single command buffer, reset (not freed
  and reallocated) when the workload is recorded again. It starts with one global barrier, which orders
  it after earlier submissions; everything inside it is ordered by the version graph.
- **Staging.** Before deleting a resource waits for outstanding uploads, it retires the batches that
  have already finished, so the wait only happens when uploads are genuinely still in flight.
- **Clears fold into rendering.** `clear_image` records its version and barrier at once, but holds the
  clear command back. If the next operation is a bind that starts a rendering scope with exactly that
  image (that view and the cleared version) as an attachment, the clear becomes the attachment's
  `loadOp = CLEAR` and costs nothing more; otherwise the held clear is emitted before that operation,
  and before any other operation, a second clear of the same image, `present`, `raw_commands` or
  `finalize_workload`, so ordering never changes. It folds when the image has one mip and the scope
  covers all its layers (one layer, or a multiview mask over every layer). In the textured cube every
  colour and depth clear folds, and in the lighting example all eight: the sun's shadow map, the four
  point-light cubes through multiview, the depth buffer and the colour.
- **Workloads are pooled.** `delete_workload` does not wait: it moves the workload's command pool, fences,
  semaphores and table chunk to a pool of up to eight retired workloads, and `make_workload` takes one
  whose fences have all signalled (`vkGetFenceStatus`, never a wait) before creating a new one. A
  workload made and deleted every frame therefore costs a command buffer reset, not object creation.
  The pool is destroyed by `shutdown`, after its device wait. Because the delete no longer waits, the
  application must wait for an execution before destroying what it used.

Not done yet, in rough order of value. These change the design, so they are open questions rather
than optimisations:
- **Deferred destruction.** One device timeline signalled by staging and workloads would let
  `delete_*` and `reload_shader` queue their handles instead of waiting (`settle_staging`,
  `vkDeviceWaitIdle`).
- **Finer barriers.** Every barrier is ALL_COMMANDS to ALL_COMMANDS. Stage and access masks could
  follow from each binding's kind and the shader's stages.

### Surfaces in workloads

`acquire(&workload, &surface)` returns the surface's **stand-in**: an Valhalla-owned image with the
swapchain's size and format (a `Swapchain_Image` variant marks it, and `delete_image` ignores it). It
is an ordinary image to every operation: draw into it, clear it, sample it, read it back. `acquire` can
come anywhere in a workload. A workload acquires from each surface at most once (asserted), and can
acquire from several surfaces.

**A workload is one prerecorded command buffer**, acquires included. Nothing is acquired while
recording, and nothing is recorded per swapchain image. The real swapchain image is only chosen when
the workload executes:
- `execute_workload` acquires every surface's next image, signalling a semaphore per surface.
- It submits, in one batch, the workload's command buffer, which waits on nothing, followed by one tiny
  prebuilt copy per acquired surface. Each copy waits on its acquire semaphore at the transfer stage,
  copies the stand-in into the acquired image, moves it to present layout and signals the present
  semaphore. Then it presents every surface in one `vkQueuePresentKHR`.
- The copies are built by the surface, one per swapchain image, whenever its swapchain is (re)built, so
  executing records nothing.

So the CPU never waits on an acquire, and the GPU starts the workload's work without waiting for the
presentation engine; only the copy waits for the image. The cost is one same-format image copy per
surface per execution, and one swapchain-sized image per surface. This replaced recording everything
after an `acquire` once per swapchain image (and once per combination of images for several surfaces).

Tested: a workload recorded once (clear the stand-in, read it back, present) executed 120 times across
both swapchain images with every readback correct and the validation layer silent.

- `present(&workload, image)` takes a version of the stand-in, as a read, and marks it presented, so it
  cannot be used again in that workload; the copy at execution time does the rest. A workload must
  present every image it acquires (asserted at finalize).
- **Recordings go stale when a swapchain is rebuilt** (resize, minimise, present mode or HDR change),
  because the stand-in is rebuilt with it. `execute_workload` checks first: it runs `update_surface` on
  every acquired surface, and if any was rebuilt since the workload recorded, or is minimised, it
  returns `.Swapchain_Changed` without executing. The application then records the workload again
  (`reset_workload` and the same calls). `acquire` reports `.Surface_Minimised` while there is nothing
  to draw to, and the frame loop can `wait_events`.
- **The stand-in can be a storage image.** When the swapchain format supports storage images, the
  stand-in is made with `.STORAGE` usage too, so a compute pass can write the final image with
  `bind_shader_output` instead of drawing it or copying it from another image. sRGB formats never
  support storage, so this needs `manual_encoding` (a UNORM swapchain, or the HDR10 format), and the
  shader encodes. Check `.STORAGE in surface.stand_in.usage`. The demo's post-process writes the
  stand-in this way.
- **The stand-in is shared** by every workload acquiring that surface. Executions are ordered on the
  queue, and every workload's command buffer starts with a global barrier, so one execution's copy
  finishes reading the stand-in before the next execution writes it.
- If a later surface's acquire fails after earlier ones succeeded, the earlier acquire semaphores are
  waited on by an empty submission so they can be reused, but those images stay acquired until their
  swapchains are rebuilt.

### Reusing workloads

A workload is recorded once and executed as often as needed, so what changes from one execution to the
next has to live outside the recording. The examples show four patterns:
- **Record every frame** (`hello_triangle`, `imgui`): make a workload, record, execute, wait, delete.
  The simplest loop; with the pool it costs a command buffer reset and the recording itself.
- **Record once, write data** (`textured_cube`, `lighting`, `two_windows`, `input`): values that change
  every frame (a rotation, the camera, light positions, a cursor-driven disc) go into a host-visible
  buffer the shader reads through an index in its push data. Each frame waits for the previous
  execution, writes the buffer and executes again. The workload is recorded again only when
  `execute_workload` returns `.Swapchain_Changed`, which is also where a depth buffer is resized.
- **Record on change** (`hdr`): values that change only on input stay in push data, and an input
  that changes one marks the recording stale. Nothing is written per frame, so executions overlap
  freely (up to `MAX_EXECUTIONS_IN_FLIGHT`).
- **Cache** (`image_editor`): the node graph is its own workload, recorded only when the graph's
  structure changes (detected by hashing nodes, links, images and shaders), and executed only when a
  parameter changes. Parameters live in a host-visible buffer indexed by each pass's `draw_data`, so
  dragging a slider or a Time node feeding the graph re-executes without re-recording. The imgui frame
  is recorded every frame into a ring of `MAX_EXECUTIONS_IN_FLIGHT` workloads, each reset before
  reuse, which bounds the frames in flight to what the imgui backend's geometry sets allow. Nothing
  waits per frame; the editor waits for its last execution only before resizing or deleting images,
  replacing a loaded image, deleting nodes or saving.

Rules that follow:
- `reset_workload` waits for that workload's own executions, so re-recording is always safe for the
  workload itself, but not for resources other workloads still use.
- `wait_execution` on a zero `Execution` returns at once, so "wait for the last one" needs no first-frame
  check. Executions on the queue complete in order (every workload starts with a global barrier), so
  waiting for the latest one waits for all before it.
- Wait before deleting or resizing anything a pending execution reads, including at shutdown: the
  examples `defer` a wait for their last execution after the deletes, so it runs first.

### Workload outputs

`workload_produces` and `workload_discards` say what a workload's writes are for. **They are optional:
they silence a warning and give Valhalla information it can use later, and a workload that never calls
them records and runs exactly as before.** Nothing is ever dropped or skipped because of them.

```odin
shown := Valhalla.workload_produces(&graph, Valhalla.generate_mips(&graph, display))
Valhalla.workload_discards(&frame, depth)
```

- `workload_produces(&workload, version) -> produced` (images and buffers) marks a version written in this
  workload as an output that outlives the execution. It returns the handle everything outside this
  recording uses: the same resource at version 0, tagged with the producing workload (`producer` on
  `Image` and `Buffer`). It must be the current version, and writing the resource again later in the same
  recording asserts, since the produced value would then be stale.
- `workload_discards(&workload, resource)` says a write is deliberately not used afterwards (a depth buffer,
  scratch). It can be called any time during the recording.
- Reads later in the same workload, `present` and `readback` already count as using a write. So does a
  read through any overlapping view of the same image: a depth view reads what a clear of the whole
  depth-stencil image wrote.

**The warning.** `finalize_workload` warns about every resource whose last operation in the workload is a
write that nothing uses, produces or discards, naming it by its debug name: *Workload "wasteful" writes
"scratch" and nothing uses it; mark it with workload_produces if another workload or the next execution
reads it, or workload_discards if it is scratch.* It is logged once per workload name and resource per
run, so a workload recorded every frame warns once.

**Across workloads.** A produced handle is an ordinary resource in any other workload, and in the next
execution of its own: version 0, whatever is in memory when that workload runs. Order is still the
queue's.
- When a workload runs that uses a produced handle whose producer has never been executed, Valhalla warns,
  once, that it reads whatever the resource held before. It does not stop it.
- Passing a raw written version (version above 0) from another workload into a workload asserts, as it
  always has, now with a message pointing at `workload_produces`.
- A resource kept from one execution to the next is produced by its workload and consumed by itself: a
  counter incremented by a compute pass, produced, and executed three times reads 3.
- Workloads have a stable `id` (a new one each time `make_workload` hands one out, pooled or not), and
  Valhalla keeps a small table of which ids have executed, cleared when the workload is deleted. A
  produced handle whose producer was deleted is not checked.

**Decided on the open questions:** depth buffers take a `workload_discards` like any other scratch (no
special case); a discard only silences the warning for now; the warning is on by default but logged once;
the producer tag lives on `Image` and `Buffer`.

**Later, using the same information:** ending a workload with barriers for its produced resources only,
instead of starting every workload with a global barrier; semaphores between producers and consumers on
different queues; and transient attachments (`storeOp = DONT_CARE`) for discarded attachments, which
needs a discard to be known before the attachment is first bound, since the store is chosen when the
rendering scope begins.

In the examples, the textured cube and lighting discard their depth buffers, the image editor produces
its node previews and display from the graph workload (the frame workload and saving read the produced
handles), and the imgui example only renders its pattern when imgui will draw it, which is what the
warning flagged. Every example runs without a warning. Tested: a consumer reading a producer's output
(and warning when run first), the warning silenced by discards and produces and logged once across two
recordings, the self-consuming counter, and the two asserting misuses.

## Surfaces

A `Surface` is something that can be presented to. It replaces the earlier Target idea, and **a surface is
always a window surface**: the file and image targets that idea included are gone. Implemented in
`Surface.odin`: `make_surface(&window, settings)` creates the Vulkan surface and its swapchain, and
`delete_surface` destroys both. Delete a surface before its window, and before `shutdown`.
The window is held by pointer, so it must stay at a stable address while the surface exists.

**Configuration goes through procs**, each of which rebuilds the swapchain when something changes:

| Proc | Does |
| --- | --- |
| `set_surface_present_mode(surface, mode)` | `.Fifo`, `.Fifo_Relaxed`, `.Mailbox` or `.Immediate`; `.Unsupported_Present_Mode` if the surface lacks it |
| `surface_supports_present_mode(surface, mode)` | Checks before switching |
| `set_surface_hdr(surface, enabled)` | `.HDR_Unavailable` if no HDR10 format is offered |
| `update_surface(surface)` | Rebuilds the swapchain if the framebuffer size changed, the swapchain is suboptimal, or the window was minimised. Optional: `acquire` calls it, so a frame loop never needs to; use it to rebuild eagerly (from a resize handler, say) |

`Surface_Settings` gives the starting `present_mode`, `prefer_hdr` and `manual_encoding` (see Colour
below). `.Fifo` is the zero value and is
the one mode Vulkan guarantees. A requested mode that is not supported fails creation, but `prefer_hdr`
falls back to SDR silently, so an app can default to HDR without failing on an SDR monitor.

Read state straight from the struct, as with `device`: `extent`, `format`, `hdr`, `hdr_available`,
`encodes_srgb`, `minimised`, and the swapchain `images` and `views`.

### Colour

Shaders work in **linear light**. The two places that convert are ones the hardware handles:
- **Sampling** an `_SRGB` image decodes it to linear. `make_image_from_file` makes colour images
  `R8G8B8A8_SRGB` by default (`srgb = false` for data such as normal maps).
- **Writing** to an SDR surface encodes linear to sRGB. SDR surfaces choose a `B8G8R8A8_SRGB` or
  `R8G8B8A8_SRGB` swapchain by default, and `surface.encodes_srgb` says so.

So a shader samples a photo, lights it, and writes the result, with no gamma code anywhere. The
exceptions are explicit:
- **HDR surfaces** take PQ, which hardware cannot encode, so the shader encodes (see the hdr example).
- **`manual_encoding = true`** picks a UNORM swapchain instead, for code that wants to encode itself
  (the hdr example sets it, since it encodes both PQ and SDR gamma).
- **Colours from outside**, such as a colour picker, a CSS-style constant or imgui's style colours, are
  sRGB values. `srgb_to_linear(colour)` converts them before they go into a clear or a shader on an
  encoding surface, and `linear_to_srgb` goes back. In Slang, `valhalla_srgb_to_linear` and
  `valhalla_linear_to_srgb` from `Valhalla.slang` do the same.

`is_srgb_format(format)` tells whether a format decodes and encodes. An image written by a shader and
then shown or saved as an ordinary picture should be `_SRGB`, or should be encoded by the shader into a
UNORM image (the image editor does the latter for its display and previews).

**Swapchain choices follow the old engine's `createSwapchain`:**
- **Format:** with HDR, an HDR10 (ST2084) 10-bit format. Otherwise BGRA8 or RGBA8 `_SRGB` in sRGB
  non-linear (UNORM with `manual_encoding`), then the other of the two, and failing those, whatever the
  surface lists first. The old engine used UNORM.
- **Images:** two (or the surface's minimum if higher), usable as a transfer destination and a colour
  attachment.
- **Sharing:** concurrent across the graphics, present and compute families when they differ.
- **Extent:** the surface's current extent, or the framebuffer size clamped to its limits.

**Differences from the old engine:**
- **Presentation is checked when the surface is made.** The device was picked before any window existed,
  so `make_surface` confirms the present queue can use this surface, and that it offers formats and
  present modes. The old engine does this while picking the GPU.
- **A minimised window does not block.** When the framebuffer is 0×0, Valhalla sets `minimised` and keeps
  the old swapchain until the window is restored. The old engine instead waits in `glfw.WaitEvents`.
- **Rebuilding waits for the whole device to go idle.** The old engine waits on its frame fences, which Valhalla
  does not have until presentation exists.

**Acquiring and presenting** happen inside workloads (see Surfaces in workloads). The acquired image is
a placeholder `Image` with a `Swapchain_Image` variant: the swapchain's format and extent, one layer and
mip, usage of transfer destination and colour attachment (and transfer source where the surface allows,
for readback), and an undefined layout, since the previous contents are not kept. It is used as a colour
attachment, cleared or read back like any other image.

- **The swapchain is kept in step with the window.** `acquire` and `execute_workload` both run
  `update_surface` first, so a resized window, a suboptimal swapchain or a restored window is rebuilt
  before anything is recorded or acquired; the frame loop needs no `update_surface` call. This also covers
  platforms that do not report out-of-date on resize.
- Every rebuild bumps `surface.generation`, which is how a workload knows its recordings are stale.
- An out-of-date result from the acquire itself rebuilds the swapchain and the execution reports
  `.Swapchain_Changed`. A suboptimal acquire or present still goes ahead and sets `surface.suboptimal`, so
  the next update rebuilds.
- Each swapchain image has a present semaphore (`surface.present_semaphores`, rebuilt with the
  swapchain) that the execution signals and `vkQueuePresentKHR` waits on. There is no copy path and no
  format check: the image is the swapchain's own.

**Not implemented yet:** present wait (see Device).

## Examples

`examples/` at the repository root holds one program per folder, each run with `odin run examples/<name>`
from the repository root. Shaders and textures are found through `#load` and `#directory`, so the working
directory only matters for files an example writes.

| Example | Shows |
| --- | --- |
| `hello_triangle` | The most basic Valhalla program: a window, a surface, a hard-coded triangle shader, and a workload recorded every frame that clears the acquired image, draws, and presents. It stays minimal on purpose, so it sets no frame callback and pauses while its window is dragged; every other windowed example keeps rendering through a drag |
| `textured_cube` | A spinning cube seen from an angle: vertex pulling from a storage buffer, an index buffer, a texture loaded from a PNG atlas (one coloured, checkered face per cell) with a sampler, depth testing, and a workload recorded once: the rotating transform is written to a host-visible buffer every frame, and the workload is recorded again, with the depth buffer resized, only when the swapchain changes |
| `offscreen` | No window: draws the triangle into an image, reads it back in the same workload, and writes `triangle.png` to the working directory |
| `hdr` | A surface made with `prefer_hdr`, and a two-pass pipeline: a scene in scene-linear light (1.0 = paper white) rendered into an `R16G16B16A16_SFLOAT` image, four colour ramps from 1/16 to 8 times paper white with a marker at 1.0; then an encode pass that, on an HDR surface, converts to Rec.2020, scales by a paper-white brightness in nits and PQ-encodes, and in SDR clips and gamma-encodes, so the ramps flatten above the marker. H switches HDR on and off (rebuilding the encode shader for the new swapchain format), Up/Down change the paper white, and the title shows the mode. Everything stays in push data and the workload is recorded again only when a key changes it or the swapchain changes, so no frame writes anything or waits |
| `lighting` | A small scene (ground plane, cubes, spheres) lit by a low sun with soft shadows and four coloured point lights orbiting it, each drawn as a glowing sphere and each casting shadows. A depth-only shader renders the sun's shadow map (vertex stage only, depth bias), and the lit shader samples that version through a comparison sampler with 3×3 filtering. Each point light has a `.Cube` depth image rendered in one multiview pass (`view_mask = 0b111111`, the face matrix picked by `SV_ViewID`, standard cube-face orientations); the draws are recorded once per frame and rebound to each light's cube with `reset_shader_bindings`, and the lit shader filters each cube with comparison samples whose depth is worked out per sample, so filtering across face seams stays correct. Blinn-Phong shading with sky/ground ambient and an ACES-style tonemap. Per-object data (transform, colour, material) comes from a storage buffer indexed by each draw's `draw_data`. All of it is recorded once: the camera, the lights, the light markers and the cube-face matrices are rewritten in host-visible buffers every frame. Drag to orbit the camera, scroll to zoom |
| `two_windows` | Two windows drawn by one workload (an acquire and present per surface, skipping a minimised window). The controller shows a colour field; clicking or dragging picks a colour, scrolling sets a size, the arrow keys nudge the pick, R resets and Escape quits. The viewer draws a disc in the picked colour and size, so input in one window drives the other. The workload is recorded once, with the pick and size in a shared host-visible buffer, and recorded again when a window is minimised or restored |
| `input` | A tour of the input API through callbacks and polling, with state reached via the window user pointer. WASD/arrows (`key_down`) and a gamepad's left stick (`gamepad_state`) move a disc, Space or the gamepad's A button changes its colour, scrolling sizes it, and clicking places it. Tab locks the mouse (`.Disabled` plus raw motion) so motion steers the disc; Escape or losing focus unlocks it. A crosshair cursor shape, C/V copy the position to the clipboard and paste clipboard text into the title, F11 toggles fullscreen on the nearest monitor (Escape leaves it), dropped files are listed, and key names, joystick connections and window events are logged. The workload is recorded once and the disc lives in a host-visible buffer |
| `imgui` | Dear ImGui on Valhalla through `Valhalla_ImGui` (see imgui and 2D drawing). Docking over the main window and a main menu that toggles imgui's demo window (nearly every widget and feature), metrics/debugger, style editor, debug log, ID stack tool and about windows. An Valhalla window shows an animated pattern rendered by another shader in the same workload, an image loaded from a file, a frame-time plot, a clear colour picker and custom draw-list primitives. Keyboard and gamepad navigation are on. Escape quits when no widget wants the keyboard |
| `image_editor` | A node-graph image editor. File > Open (Ctrl+O) picks an image with a tinyfiledialogs dialog. Each image node is one or two fullscreen passes into its own `R16G16B16A16_SFLOAT` image, all in one graph workload in dependency order. The graph is cached (see Reusing workloads): it is recorded when its structure changes, executed when a parameter or a Time node changes, and otherwise left alone, while the node images and previews keep their contents between frames. The nodes are Image, Adjust (exposure, contrast, saturation, gamma, temperature), Blur (separable Gaussian, two passes), Sharpen, Mix, Custom shader, Value, Time and Output. Every node shows an sRGB-encoded preview, and the Output node's result is encoded into the Viewer, which can fit or zoom with Ctrl+wheel. Zoomed in, it samples with a nearest filter at a whole-pixel position, so pixels stay sharp; zoomed out, it samples a mip chain: the Output pass renders into an `R8G8B8A8_SRGB` display image and the graph workload blits each mip from the one above (in linear light, since the format is sRGB), so a large image shrunk to fit does not alias into moiré. Node previews average the whole footprint of each preview pixel (up to 8×8 bilinear taps) for the same reason. File > Save output (Ctrl+S) reads the result back and writes a PNG. The Adjustments window lists every node's parameters as plain sliders, so the graph is optional for simple edits. In the Shader graph, drag from a pin to link (image pins teal, number pins orange). An unconnected number input is a static value on the node; wire a Value or Time node in to drive it. Right-click the canvas to add nodes or a node to delete it, right-click a linked input to unlink it, drag nodes by their body, pan with the middle or right button; a link that would form a cycle is refused. A Custom shader node holds Slang code defining `float4 effect(float2 uv, float4 p)` with `sample_a`, `sample_b` and `texel_size` helpers. The Shader editor compiles it (Ctrl+Enter) through `make_shader` from code, showing the diagnostics it returns, and a `#line` directive makes their line numbers match the editor; the last working shader keeps running while an edit fails to compile. Node deletion is deferred to the end of the frame, because imgui's draw commands for that frame still point at the node's preview, and it waits for the last execution first |

## The demo

`demo/` is the Valhalla demo program (package `Demo`), ported from the old engine onto this API, which
it uses as an ordinary client. The old engine is gone. `demo/src/Graphics.odin` keeps the procs the rest
of the demo always called (`initGraphics`, `updateSceneData`, `drawFrame`, `debugPreview`, ...) and
implements them with workloads:

- **A scene workload** per frame in flight: transform compute (skinning into a transforms and a
  positions buffer, one dispatch per mesh), one multiview shadow bind per light (each light's six
  layers are a `.D2_Array` view of one `.Cube_Array` colour image and one depth image), the scene pass
  and the light gizmos into a 1920×1080 `R16G16B16A16_SFLOAT` image. It is recorded only when
  something marks it dirty, and executed every frame; the scene colour is `workload_produces`d and the
  depths are discarded. Per-mesh values (instance range, vertex range, transform offset) live in a
  `MeshDraw` storage buffer indexed by `draw_data`. Scene textures are `R8G8B8A8_SRGB` images with
  mips and an `R8G8B8A8_UNORM` view (via `view_formats`), bound with `bind_shader_input` two per
  texture; the texture index buffer holds those local indices, so it depends only on texture order.
- **A frame workload** per frame in flight, recorded every frame: acquire, an optional debug-preview
  compute pass, imgui into the UI image (`linear_output`), a post-process compute pass that samples the
  scene into the letterbox, composites the UI, encodes gamma or PQ and writes the stand-in directly,
  then screenshot or dump readbacks and present.
- **Frames in flight.** Each set of per-frame host buffers (uniforms, instances, bones, lights) belongs
  to one scene workload, and `updateSceneData` waits for that set's last executions before writing
  it. A frame latency of 1 waits for both.
- **Input** comes from Valhalla's window callbacks, converted to the demo's `InputEvent`, installed
  before `valhalla_imgui.init` so imgui sees each event first. The external API's `handleInput` turns
  an `InputEvent` back into the matching `inject_*` call, so injected clicks and keys reach imgui and
  the demo by the same path as real ones. Tested: F1 opening the editor, a click picking an object,
  Ctrl+A, typing and Enter renaming it, menus, the Debug panel's preview, and switching HDR and the
  light gizmos at runtime.

Tested in HDR and SDR: the scene, shadows and gizmo match the old renderer; screenshots, dumps of
every debug image and the debug preview are correct; and a run ends with the validation layer
silent, no workload warnings and no live suballocations.

## imgui and 2D drawing

imgui stays out of the library. Third-party bindings live in `deps/`: `deps/imgui` (dear_bindings'
`dcimgui`, 1.92.6 docking branch, with a prebuilt Windows library) and `deps/tinyfiledialogs` (native
open/save dialogs, prebuilt for Windows, Linux and macOS; the demo uses it too). The code connecting
imgui to Valhalla is the package `Valhalla_ImGui` in `src/imgui/` beside the package (`ImGui.odin` plus its
`ImGui.slang`). It imports Valhalla and is built only from public Valhalla procs, and Valhalla never imports
it, so imgui stays optional: `import valhalla_imgui "<valhalla>/imgui"`, then `valhalla_imgui.init`,
`new_frame`, `render`, `texture` and `shutdown`. It started inside the imgui example and was promoted to
its own package when the image editor needed it too.

- **Platform.** `init(&window, target_format)` creates the context, then chains onto the
  window's key, char, mouse button, cursor position, cursor enter, scroll and focus callbacks. It saves
  each previous callback and calls it after feeding imgui, so install the application's own callbacks
  first. It also routes the clipboard through `clipboard_text`/`set_clipboard_text`, and maps
  imgui's mouse cursors onto `make_standard_cursor` (wait and progress fall back to the arrow).
  `new_frame` sets the display size, framebuffer scale and delta time, applies the cursor, and feeds
  the first gamepad to imgui's gamepad navigation. Printable keys are translated through `key_name`
  so shortcuts follow the keyboard layout.
- **Allocator.** The prebuilt library is compiled with `IMGUI_DISABLE_DEFAULT_ALLOCATORS`, so
  `SetAllocatorFunctions` must be called before `CreateContext`, or imgui asserts on its first
  allocation. The example routes imgui's allocations through the Odin context allocator.
- **Renderer.** Sets `RendererHasTextures` and `RendererHasVtxOffset`. Texture requests become Valhalla
  images (`R8G8B8A8_UNORM`; `Alpha8` is expanded to white plus alpha): create uploads the whole texture,
  each update uploads its rectangles with `load_memory_to_image`'s region, and destroy waits until imgui
  reports `GEOMETRY_SETS` unused frames. Vertex and index data go into host-visible buffers, one set per
  execution that can be in flight plus one (`MAX_EXECUTIONS_IN_FLIGHT + 1`). That is because a frame
  writes its set while recording, before `execute_workload` waits for an older execution's slot. So
  at most `MAX_EXECUTIONS_IN_FLIGHT` imgui frames may be in flight: wait for each frame, re-record one
  workload (`reset_workload` waits for it), or use a ring of that many workloads as the image editor does.
  Fresh workloads from the pool on their own do not bound it.
  `render(&workload, target)` records one bind of a single shader: each draw command becomes a
  `draw_indexed` with its clip rectangle as the scissor. Each distinct texture is bound once, and every
  draw passes its binding index as its `draw_data`. imgui works in sRGB-encoded values, so the backend
  sets bit 31 of that value, its own encoding of the integer it passes, for a texture with an `_SRGB`
  format, whose decoded texels the shader re-encodes. When the target is sRGB (`is_srgb_format`), the final colour is decoded so the surface's
  encode puts it back. `init(&window, target_format, linear_output = true)` asks for the same linear
  output on a non-sRGB target, for an application that composites imgui into a float image and
  encodes the result itself (the demo renders imgui into an `R16G16B16A16_SFLOAT` UI image this way). The result is that any image displays correctly whatever its format. Blending on
  an sRGB target happens in linear light, so translucent imgui edges look slightly lighter than on a
  UNORM target.
- **User textures.** `texture(&image)` turns an Valhalla image into an `ImTextureRef` by storing the
  image's address, which is read when the frame is rendered. Pointing it at a variable that is given an
  output version before `imgui_render` (the example's `pattern_written`) shows something rendered in the
  same workload, with the barrier coming from the version graph as usual. Any format works: `_SRGB`
  images are re-encoded for imgui, and UNORM images are taken to hold display-ready (encoded) values.
  `texture(&image, .Nearest)` samples with a nearest filter instead of the default `.Linear`, for
  magnified images that should stay crisp (the image editor's viewer uses it whenever it zooms in). The
  filter rides in bit 0 of the stored address, which `Valhalla.Image`'s alignment leaves free, and reaches
  the shader as bit 30 of the draw's `draw_data`, beside the sRGB flag in bit 31; the backend binds a
  linear and a nearest sampler and the shader picks per draw.

Not supported: multi-viewport (imgui windows dragged out into their own OS windows), which needs the
platform backend to create and drive extra windows and surfaces; and `ImDrawCallback`s that want raw
command buffer access, since the renderer records through Valhalla rather than raw Vulkan. Ordinary
callbacks are called, and `ResetRenderState` is a no-op because every draw already restates its state.
Valhalla-native 2D drawing (`draw_rect`, `draw_circle`) is still an open idea; imgui's draw lists cover it
for now.

## Deferred

| Area | Status |
| --- | --- |
| Extra draw commands | Indirect, count, indirect dispatch and mesh draws done (see Indirect and mesh draws); clears and blits are workload operations (see Copies); mip chains come from `generate_mips` (see Copies) |
| Buffer and image specifics (usage, memory placement, mapping, formats) | Later; expect to constrain what we offer. Copies, readback and image views are done |
| Monitors and fullscreen | Done (see Window); fullscreen untested on hardware |
| Debug tooling (object names, labels, validation, timing) | Names and labels done (see Device); validation is always on; GPU timing not started |
| Pipeline state split between workload and shader | Needs real design work |

## Open questions

- [x] Device setup: a single package-level `device`, created by `init(settings)` with the old engine's GPU
      picking, fields read directly for raw Vulkan.
- [x] Requesting features from extension feature structs (e.g. compute derivatives) through
      `init`'s `feature_chain` parameter.
- [x] The error type. A `#shared_nil` union of per-area enums, returned by every proc that can fail.
- [x] Frames during a window drag. `set_frame_callback` plus a per-platform modal-loop timer, as in
      the old engine (see Input). The macOS timer is still untested.
- [ ] Stale `hdr_available`. HDR availability depends on the window's monitor and the OS HDR toggle, so
      `recreate_swapchain` recounts it from the format list it already fetches. But it is only refreshed
      when something else causes a rebuild; moving the window to another monitor or toggling OS HDR does
      not. `set_surface_hdr` trusts the cached value, so it can wrongly return `.HDR_Unavailable`.
      Options: re-query formats inside `set_surface_hdr`; and/or have `update_surface` refresh formats
      when the window moves or its content scale changes, rebuilding if `prefer_hdr` would now pick a
      different format. The OS toggle would still need a periodic re-query.
- [ ] **HDR needs a revisit as a whole** (user, 2026-10-14): detecting whether the display is really in HDR
      (below), refreshing `hdr_available`, the display's peak brightness and HDR metadata
      (`vkSetHdrMetadataEXT`), and hue-preserving highlight roll-off instead of per-channel clipping, which
      makes saturated colours wash towards white in `examples/hdr`.
- [ ] `hdr_available` does not mean the display is in HDR mode. On Windows with an NVIDIA GPU the HDR10
      (ST2084) swapchain format is offered even with Windows HDR switched off, so a `prefer_hdr` surface
      picks it and the application PQ-encodes for a desktop that is in SDR (found with `examples/hdr`).
      Knowing whether the OS is actually in HDR needs a platform query (DXGI output colour space or the
      display configuration API on Windows; other platforms differ), which fits the cross-platform rule only
      with a real implementation per target.
- [x] A new name for `Render` that covers compute as well as graphics. `Workload`.
- [x] Where resources are bound. On shaders: `bind_shader_input`, `bind_shader_output` and the attachment
      procs record onto the shader, and `bind_shader` replays them into a workload.
- [x] Where `draw_indexed` gets its index buffer, since bindless covers only what shaders read.
      `bind_shader_index_buffer`.
- [x] Whether `draw_indexed` takes `first_instance`, which per-draw data under bindless usually indexes
      by. It does, but per-draw indices now go through `draw_data`, so instance indices can mean model
      instances.
- [x] `make_empty_image` takes a byte count; it needs width, height, depth, layers and format. It now
      takes format, size, kind, shape, layers, mips and samples.
- [ ] Allocator parameters on the `make_*` procs that allocate.
- [ ] Shader source languages other than Slang (GLSL, HLSL). SPIR-V from any compiler already works.
- [ ] Attachment formats in `Shader_Config`, including shaders that draw straight into a surface.
- [x] A pipeline cache, saved somewhere the application chooses. A `Pipeline_Cache` the application makes,
      loads and saves itself, passed through `Shader_Config.pipeline_cache`.
- [ ] The Slang bindings mark `Global_Session` and `Module` `@(private)`, so Valhalla names them through
      `intrinsics.type_proc_return_type`. Exporting them from `slang/` would remove the workaround.
- [x] How a workload's writes become usable elsewhere. Inside a workload, through versions; across
      workloads, through `workload_produces` or the original handle.
- [x] Whether a resource counts as in use from the moment its workload is executed, or only once that
      work is submitted. Moot: execution submits straight away.
- [x] Are the stages set up while recording replayed every time the finalised workload executes, or do they
      only apply to the first pass? Moot: there are no stages; order inside a workload comes from versions.
- [x] `workload_produces` and how versions cross workloads. See Workload outputs; optional, warnings only.
