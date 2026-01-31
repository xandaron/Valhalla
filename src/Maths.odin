package Valhalla

import "core:math"
import "core:math/linalg"

PI :: math.PI

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

ZEROVEC2 :: Vec2{0, 0}
ZEROVEC3 :: Vec3{0, 0, 0}
ZEROVEC4 :: Vec4{0, 0, 0, 0}

ONEVEC2 :: Vec2{1, 1}
ONEVEC3 :: Vec3{1, 1, 1}
ONEVEC4 :: Vec4{1, 1, 1, 1}

Quat :: linalg.Quaternionf32

IQUAT :: linalg.QUATERNIONF32_IDENTITY

Mat2 :: linalg.Matrix2f32
Mat3 :: linalg.Matrix3f32
Mat4 :: linalg.Matrix4f32

IMAT2 :: linalg.MATRIX2F32_IDENTITY
IMAT3 :: linalg.MATRIX3F32_IDENTITY
IMAT4 :: linalg.MATRIX4F32_IDENTITY

// Functions
degrees :: linalg.to_degrees
radians :: linalg.to_radians

sin :: math.sin
cos :: math.cos
tan :: math.tan

asin :: math.asin
acos :: math.acos
atan :: math.atan

normalize :: linalg.normalize
cross :: linalg.cross
dot :: linalg.dot

lerp :: proc {
	linalg.lerp,
	vec3Lerp,
}
slerp :: linalg.quaternion_slerp_f32

translate :: linalg.matrix4_translate
quatToMat4 :: linalg.matrix4_from_quaternion
scale :: linalg.matrix4_scale

abs :: math.abs
sign :: math.sign
clamp :: math.clamp
round :: linalg.round
ceil :: math.ceil
floor :: math.floor
floor_div :: math.floor_div

pow :: linalg.pow
sqrt :: math.sqrt

min :: math.min
max :: math.max

angle :: linalg.angle_between
distance :: linalg.distance
length :: linalg.length
length2 :: linalg.length2

quatMulVec3 :: linalg.quaternion_mul_vector3
quatFromAxisAngle :: linalg.quaternion_angle_axis
quatToEuler :: linalg.euler_angles_xyz_from_quaternion
quatFromEuler :: linalg.quaternion_from_euler_angles_f32

inverse :: linalg.inverse
transpose :: linalg.transpose

rotate3 :: linalg.matrix3_rotate
rotate :: linalg.matrix4_rotate

minVec3 :: proc(a, b: Vec3) -> Vec3 {
	return {min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)}
}

maxVec3 :: proc(a, b: Vec3) -> Vec3 {
	return {max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)}
}

vec3Lerp :: proc(a, b: Vec3, t: f32) -> Vec3 {
	return a + (b - a) * t
}

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

