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
