package Valhalla

import "core:math"
import "core:math/linalg"

pow :: linalg.pow
ceil :: math.ceil

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

normalize :: linalg.normalize
cross :: linalg.cross
dot :: linalg.dot

tan :: math.tan

Quat :: linalg.Quaternionf32
IQUAT :: linalg.QUATERNIONF32_IDENTITY

lerp :: linalg.lerp
slerp :: linalg.quaternion_slerp_f32

Mat4 :: linalg.Matrix4f32
IMAT4 :: linalg.MATRIX4F32_IDENTITY

translate :: linalg.matrix4_translate
quatToMat4 :: linalg.matrix4_from_quaternion
scale :: linalg.matrix4_scale

transform :: #force_inline proc(p: Vec3, r: Quat, s: Vec3) -> Mat4 {
	return translate(p) * quatToMat4(r) * scale(s)
}

lookAt :: proc(eye, center, up: Vec3) -> Mat4 {
	f := normalize(center - eye)
	s := normalize(cross(up, f))
	u := cross(f, s)

	return {
		s.x,
		s.y,
		s.z,
		-dot(s, eye),
		u.x,
		u.y,
		u.z,
		-dot(u, eye),
		f.x,
		f.y,
		f.z,
		-dot(f, eye),
		0,
		0,
		0,
		1,
	}
}

perspective :: proc(fov, aspect, near, far: f32) -> (m: Mat4) {
	assert(aspect != 0, "Aspect ratio can't be zero!")
	tanHalfFov := tan(0.5 * fov)
	m[0, 0] = 1 / (aspect * tanHalfFov)
	m[1, 1] = -1 / (tanHalfFov)
	m[2, 2] = far / (far - near)
	m[2, 3] = -(far * near) / (far - near)
	m[3, 2] = 1
	return
}

orthographic :: proc(fov, aspect, near, far: f32) -> (m: Mat4) {
	assert(aspect != 0, "Aspect ratio can't be zero!")
	top := near * tan(0.5 * fov)
    right := top * aspect

	m[0, 0] = 1 / right
    m[1, 1] = -1 / top
    m[2, 2] = 1 / (far - near)
    m[2, 3] = -near / (far - near)
    m[3, 3] = 1
	return
}
