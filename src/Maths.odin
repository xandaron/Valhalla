package Valhalla

import "core:math"
import "core:math/linalg"

pow :: linalg.pow
ceil :: math.ceil

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

Quat :: linalg.Quaternionf32
IQUAT :: linalg.QUATERNIONF32_IDENTITY

slerp :: linalg.quaternion_slerp_f32

Mat4 :: linalg.Matrix4f32
IMAT4 :: linalg.MATRIX4F32_IDENTITY

translate :: linalg.matrix4_translate
quatToMat4 :: linalg.matrix4_from_quaternion
scale :: linalg.matrix4_scale

transform :: #force_inline proc(p: Vec3, r: Quat, s: Vec3) -> Mat4 {
	return translate(p) * quatToMat4(r) * scale(s)
}

lerp :: linalg.lerp
