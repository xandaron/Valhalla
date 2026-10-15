# TODO

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
      ones, which needs the discard known before the attachment is first bound.
- [ ] GPU timing.
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
