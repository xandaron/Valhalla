package Valhalla

import "base:intrinsics"

Camera :: struct($Base: typeid) where intrinsics.type_is_struct(Base) {
	using _: Base `imrefl:"flatten"`,
	mode:    CameraMode `imrefl:"label=Mode"`,
	eye:     Vec3 `imrefl:"label=Eye,speed=0.1"`,
	center:  Vec3 `imrefl:"label=Center,speed=0.1"`,
	up:      Vec3 `imrefl:"label=Up,speed=0.1,normalized"`,
	fov:     f32 `imrefl:"label=FOV,min=1,max=179,speed=0.1"`,
	near:    f32 `imrefl:"label=Near plane,min=0.001,max=1000,speed=0.1"`,
	far:     f32 `imrefl:"label=Far plane,min=0.002,max=10000,speed=0.1"`,
}

CameraMode :: enum {
	PERSPECTIVE,
	ORTHOGRAPHIC,
}

view :: #force_inline proc(camera: Camera($B)) -> Mat4 {
	return lookAt(camera.eye, camera.center, camera.up)
}

projection :: proc(camera: Camera($B), aspect: f32) -> Mat4 {
	switch camera.mode {
	case .PERSPECTIVE:
		return perspective(radians(camera.fov), aspect, camera.near, camera.far)
	case .ORTHOGRAPHIC:
		return orthographic(radians(camera.fov), aspect, camera.near, camera.far)
	}
	panic("Unreachable!")
}

viewProjection :: proc(camera: Camera($B), aspect: f32) -> Mat4 {
	return projection(camera, aspect) * view(camera)
}
