# TODO

## API direction

- [ ] Acquire and present stop being commands recorded into a workload. A workload only records that
      its output goes to a surface; `execute_workloads` adds the acquire, any scaling or format
      conversion, and the present each time it runs, so the surface's size and format can change
      between executions and a swapchain rebuild never forces a re-record (`Swapchain_Changed` goes
      away for resizes). Open: what a workload draws into when it does not know the swapchain's size
      (an image the user sizes, scaled onto the swapchain at present), how shaders' attachment formats
      follow a surface whose format changes (an HDR toggle), and minimised windows (skip the present,
      keep the workload valid).
- [ ] Clean up the public API: it is often unclear which procedure does a job, and some names need
      to change. Audit every public procedure for overlaps and naming. Already seen: a resource can
      reach a shader as a push field or through the binding table, with nothing saying which to
      prefer; `bind_shader_input`/`bind_shader_output` return a table index on every call although
      most callers pass resources as push fields and discard it; binding the same resource twice adds
      a second table entry instead of returning the first (imgui deduplicates by hand); and
      `bind_shader_output` both declares a write and adds a table entry.
- [ ] Executions run in parallel, ordered only by dependencies. Today `execute_workloads` runs its
      workloads in order because `begin_command_buffer` opens every workload with a full
      all-commands barrier; that barrier is not the design and goes. A workload synchronises only
      with the workloads it depends on: dependencies stated between workloads (or derived from
      `workload_produces`), timeline semaphores between them, and multiple queues (graphics, async
      compute, transfer). See the `workload_produces`/`workload_discards` item below.

## Examples

- [ ] Rewrite the examples for readability; they are the documentation, and today they are hard to
      follow. Each should read top to bottom as the steps of the one thing it shows, with setup,
      per-frame work and teardown easy to tell apart. Seen so far: `lighting` threads ~25 fields
      through a `Scene` struct of pointers and splits a frame across `draw_frame`/`record_frame` with
      a `recorded` flag; the same helpers are copied between examples (`raw_bytes` five times,
      `add_cube`/`add_plane`/`add_sphere` and `projection` three times, orbit-camera input callbacks
      in four or five); `image_editor` is 1391 lines in one file. Copies of `raw_bytes` suggest
      something the API should offer itself.

## HDR

- [ ] `hdr_available` is only refreshed when the swapchain is rebuilt, so moving the window to another
      monitor or toggling OS HDR leaves it stale and `set_surface_hdr` can wrongly return
      `.HDR_Unavailable`. Re-query formats in `set_surface_hdr`, and/or refresh them in
      `update_surface` when the window moves or its content scale changes.
- [ ] `hdr_available` does not mean the display is in HDR: on Windows with NVIDIA the HDR10 format is
      offered even with OS HDR off. Detecting the OS mode needs a platform query, implemented for
      every target.
- [ ] Display peak brightness and HDR metadata (`vkSetHdrMetadataEXT`).
- [ ] Hue-preserving highlight roll-off instead of per-channel clipping, which washes saturated
      colours towards white in `examples/hdr`.

## Device and memory

- [ ] Present wait (`VK_KHR_present_wait2`), enabled at device creation when supported.
- [ ] Multiple devices: the device becomes a handle that resources, shaders and workloads belong to,
      with per-device function tables (`vk.load_proc_addresses_device_vtable`).
- [ ] Deferred destruction on one device timeline, so `delete_*` and `reload_shader` queue handles
      instead of waiting (`settle_staging`, `vkDeviceWaitIdle`).
- [ ] Allocator parameters on the `make_*` procedures that allocate.

## Resources

- [ ] Descriptors for multisampled images.
- [ ] Uploads of block-compressed and 3-channel 32-bit formats.
- [ ] Decide what buffer and image specifics (usage, memory placement, mapping, formats) to expose;
      image formats and sampler enums are raw `vk` types for now.

## Shaders and workloads

- [ ] Shader languages other than Slang (GLSL, HLSL). SPIR-V from any compiler already works.
- [ ] Attachment formats in `Shader_Config`, including shaders that draw straight into a surface.
- [ ] How pipeline state is split between the shader and the workload.
- [ ] Finer barriers: stage and access masks from each binding's kind and the shader's stages,
      instead of all commands to all commands.
- [ ] Use `workload_produces`/`workload_discards` beyond warnings: barriers for produced resources
      at the end of a workload instead of a global one at the start, semaphores between producers and
      consumers on different queues, and transient attachments (`storeOp = DONT_CARE`) for discarded
      ones, which needs the discard known before the attachment is first bound. Workloads stay
      independent: a consumer waits on the timeline value of its producer's latest execution, if
      it has one, and never makes the producer run again or waits for a future run of it.
- [ ] GPU timing.
- [ ] Acceleration structure builds inside a workload. `update_top_level` moves instances by
      rebuilding in place on the staging queue, which waits on the CPU and allocates a scratch and an
      instance buffer each call. Compaction and AABB geometry too.
- [ ] The Slang bindings mark `Global_Session` and `Module` `@(private)`, so `Shader.odin` names them
      through `intrinsics.type_proc_return_type`. Export them from `src/slang`.

## Drawing and imgui

- [ ] Native 2D drawing (`draw_rect`, `draw_circle`); imgui's draw lists cover it for now.
- [ ] imgui multi-viewport (windows dragged out into their own OS windows).
- [ ] imgui draw callbacks that need raw command buffer access.

## Untested

- [ ] The macOS modal-loop timer in `IO_darwin.odin` (written without a Mac).
- [ ] Fullscreen (`set_window_fullscreen`) on real hardware.

## Known issues

- NVIDIA task shader payload: on an RTX 4060 Ti (driver 616.92) a task shader's payload reads as zero
  in the mesh shader when both entry points are in one SPIR-V module, which is how every pipeline is
  built. Valid SPIR-V; separate per-stage modules work. Not worked around; if needed, compile the task
  entry point into its own module.
- NVIDIA acceleration structures through the descriptor heap (drivers 610.x to 617.42): tracing an
  acceleration structure that a shader reads from the resource heap loses the device or hangs. It
  fails with both lowerings: Slang 2026.8's typed `OpLoad` of `OpTypeAccelerationStructureKHR`, and
  Slang 2026.17 onwards' 64-bit address load plus `OpConvertUToAccelerationStructureKHR` (Slang
  #10671, #11494; that form also needs `shaderInt64`). Reported with GLSL and Slang on RTX 4070 Ti
  SUPER, 4090 and Linux (NVIDIA developer forum thread 376527); storage images and buffers in the
  same heap work. Valhalla passes the structure's device address in push data instead
  (`valhalla_acceleration_structure`), which never touches the heap and works. Revisit when NVIDIA
  fixes it.
