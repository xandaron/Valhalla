package Valhalla

import "core:math"
import "core:math/linalg"

sin :: math.sin
cos :: math.cos
tan :: math.tan

floor :: math.floor
log2 :: math.log2

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

f64Vec2 :: linalg.Vector2f64
f64Vec3 :: linalg.Vector3f64
f64Vec4 :: linalg.Vector4f64

Quat :: linalg.Quaternionf32
IQuat :: linalg.QUATERNIONF32_IDENTITY

quatFromX :: linalg.quaternion_from_euler_angle_x
quatFromY :: linalg.quaternion_from_euler_angle_y
quatFromZ :: linalg.quaternion_from_euler_angle_z

Mat2 :: linalg.Matrix2f32
Mat3 :: linalg.Matrix3f32
Mat4 :: linalg.Matrix4f32

IMAT2 :: linalg.MATRIX2F32_IDENTITY
IMAT3 :: linalg.MATRIX3F32_IDENTITY
IMAT4 :: linalg.MATRIX4F32_IDENTITY

radians :: linalg.to_radians

transpose :: linalg.transpose

distance :: linalg.distance

length :: linalg.length
length2 :: linalg.length2

normalize :: linalg.normalize

cross :: linalg.cross

dot :: linalg.dot

translate :: linalg.matrix4_translate

scale :: linalg.matrix4_scale

rotation3 :: linalg.matrix3_rotate
rotation4 :: linalg.matrix4_rotate
quatToRotation :: linalg.matrix4_from_quaternion

invert :: linalg.matrix4_inverse

lerp :: linalg.lerp
quatLerp :: linalg.quaternion_nlerp

pow :: linalg.pow

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

// Is this really correct?
orthographic :: proc(fov, aspect, near, far: f32) -> (m: Mat4) {
	assert(aspect != 0, "Aspect ratio can't be zero!")
	tanHalfFov := tan(0.5 * fov)
	top := tanHalfFov * near
	right := top * aspect

	m[0, 0] = 1 / right
	m[1, 1] = -1 / top
	m[2, 2] = 1 / (far - near)
	m[2, 3] = -near / (far - near)
	m[3, 2] = 1
	return
}
