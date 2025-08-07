package Demo

import "core:math"
import "core:math/linalg"

PI :: math.PI

sqrt :: math.sqrt
abs :: math.abs
min :: math.min
max :: math.max
clamp :: math.clamp
sign :: math.sign

round :: linalg.round

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

angle :: linalg.angle_between
distance :: linalg.distance
length :: linalg.length
length2 :: linalg.length2
normalize :: linalg.normalize
cross :: linalg.cross
dot :: linalg.dot

minVec3 :: proc(a, b: Vec3) -> Vec3 {
	return {
		min(a.x, b.x),
		min(a.y, b.y),
		min(a.z, b.z),
	}
}

maxVec3 :: proc(a, b: Vec3) -> Vec3 {
	return {
		max(a.x, b.x),
		max(a.y, b.y),
		max(a.z, b.z),
	}
}

vec3Lerp :: proc(a, b: Vec3, t: f32) -> Vec3 {
	return a + (b - a) * t
}

vec4Lerp :: proc(a, b: Vec4, t: f32) -> Vec4 {
	return a + (b - a) * t
}

lerp :: proc {
	linalg.lerp,
	vec3Lerp,
	vec4Lerp,
}

Quat :: linalg.Quaternionf32
IQUAT :: linalg.QUATERNIONF32_IDENTITY

slerp :: linalg.quaternion_slerp

quatToMat4 :: linalg.matrix4_from_quaternion
quatMulVec3 :: linalg.quaternion_mul_vector3
quatFromAxisAngle :: linalg.quaternion_angle_axis
quatToEuler :: linalg.euler_angles_xyz_from_quaternion
quatFromEuler :: linalg.quaternion_from_euler_angles_f32

Mat3 :: linalg.Matrix3f32
Mat4 :: linalg.Matrix4f32

IMAT3 :: linalg.MATRIX3F32_IDENTITY
IMAT4 :: linalg.MATRIX4F32_IDENTITY

inverse :: linalg.inverse
transpose :: linalg.transpose

translate :: linalg.matrix4_translate
rotate3 :: linalg.matrix3_rotate
rotate :: linalg.matrix4_rotate
scale :: linalg.matrix4_scale

sin :: math.sin
cos :: math.cos
tan :: math.tan

asin :: math.asin
acos :: math.acos
atan :: math.atan

degrees :: linalg.to_degrees
radians :: linalg.to_radians

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
