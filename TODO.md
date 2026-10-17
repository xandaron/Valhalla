# TODO

## Now

- [ ] Rewrite the examples for readability; they are the documentation, and today they are hard to
      follow. Each should read top to bottom as the steps of the one thing it shows, with setup,
      per-frame work and teardown easy to tell apart. Seen so far: `lighting` threads ~25 fields
      through a `Scene` struct of pointers and splits a frame across `draw_frame`/`record_frame` with
      a `recorded` flag; the same helpers are copied between examples (`raw_bytes` five times,
      `add_cube`/`add_plane`/`add_sphere` and `projection` three times, orbit-camera input callbacks
      in four or five); `image_editor` is 1391 lines in one file; every example that passes
      `&surface` into a frame procedure trips Odin's "may keep a reference to stack memory" warning.
      Copies of `raw_bytes` suggest something the API should offer itself.
- [ ] `Valhalla_ImGui.init(window, format)`: decide whether it should take the surface instead and
      follow its format through an HDR toggle; not yet discussed.
- [ ] `Valhalla_ImGui` sizes its geometry ring to `MAX_EXECUTIONS_IN_FLIGHT + 1`, which only holds if
      the caller throttles its workloads the way the examples do; deferred until the coupling is
      explained and reviewed.

## Design

- [ ] Executions run in parallel, ordered only by dependencies. Today `execute_workloads` runs its
      workloads in order because every workload opens with a full all-commands barrier; that barrier
      is not the design and goes. A workload synchronises only with the workloads it depends on:
      dependencies stated between workloads (or derived from `workload_produces`), timeline
      semaphores between them, and multiple queues (graphics, async compute, transfer).
- [ ] Finer barriers: stage and access masks from each binding's kind and the shader's stages,
      instead of all commands to all commands.
- [ ] Use `workload_produces`/`workload_discards` beyond warnings: barriers for produced resources
      at the end of a workload instead of a global one at the start, semaphores between producers and
      consumers on different queues, and transient attachments (`storeOp = DONT_CARE`) for discarded
      ones, which needs the discard known before the attachment is first bound. Workloads stay
      independent: a consumer waits on the timeline value of its producer's latest execution, if
      it has one, and never makes the producer run again or waits for a future run of it.
- [ ] Staging and workloads keep separate timelines, so a deferred deletion tracks both; one device
      timeline would simplify the graves and let staging batches use `wait_value`.
- [ ] The present blit is re-recorded every execution; it only changes when the swapchain image, the
      source or either extent does.
- [ ] Acceleration structure builds inside a workload. `update_top_level` rebuilds in place on the
      staging queue and allocates a scratch and an instance buffer each call. Compaction and AABB
      geometry too.

## Later

- [ ] HDR: `hdr_available` is only refreshed when the swapchain is rebuilt, so moving the window to
      another monitor or toggling OS HDR leaves it stale; it also does not mean the display is in HDR
      (on Windows with NVIDIA the HDR10 format is offered with OS HDR off), which needs a platform
      query for every target; display peak brightness and metadata (`vkSetHdrMetadataEXT`);
      hue-preserving highlight roll-off instead of per-channel clipping in `examples/hdr`.
- [ ] Present wait (`VK_KHR_present_wait2`), enabled at device creation when supported.
- [ ] Multiple devices: the device becomes a handle that resources, shaders and workloads belong to,
      with per-device function tables (`vk.load_proc_addresses_device_vtable`).
- [ ] Allocator parameters on the `make_*` procedures that allocate.
- [ ] Descriptors for multisampled images.
- [ ] Uploads of block-compressed and 3-channel 32-bit formats.
- [ ] Which Vulkan types stay in the API: formats and the small enums are aliased
      (`Format`, `Filter`, `Cull_Mode`, ...); `Image.usage`, `Image.layout`, `Buffer.size` and the
      handles are still raw.
- [ ] Shader source languages other than Slang (GLSL, HLSL) through Slang's front ends. SPIR-V from
      any compiler already works.
- [ ] GPU timing.
- [ ] Native 2D drawing (`draw_rect`, `draw_circle`); imgui's draw lists cover it for now.
- [ ] imgui multi-viewport (windows dragged out into their own OS windows).
- [ ] imgui draw callbacks, which need raw command buffer access at replay time; `end_frame` asserts
      on them.
- [ ] Fullscreen (`set_window_fullscreen`) is untested on real hardware.

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
