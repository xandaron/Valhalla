/*
---------------------------------------------------------------------------
Open Asset Import Library (assimp)
---------------------------------------------------------------------------

Copyright (c) 2006-2025, assimp team

All rights reserved.

Redistribution and use of this software in source and binary forms,
with or without modification, are permitted provided that the following
conditions are met:

* Redistributions of source code must retain the above
copyright notice, this list of conditions and the
following disclaimer.

* Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other
materials provided with the distribution.

* Neither the name of the assimp team, nor the names of its
contributors may be used to endorse or promote products
derived from this software without specific prior
written permission of the assimp team.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
---------------------------------------------------------------------------
*/
/** @file mesh.h
*  @brief Declares the data structures in which the imported geometry is
returned by ASSIMP: aiMesh, aiFace and aiBone data structures.
*/
package assimp

import "core:c"

_ :: c

@(require)
import zlib "vendor:zlib"

when ODIN_OS == .Windows {
    foreign import lib "libassimp.lib"
}
else {
    foreign import lib "system:assimp"
}

MAX_FACE_INDICES :: 0x7fff

MAX_BONE_WEIGHTS :: 0x7fffffff

MAX_VERTICES :: 0x7fffffff

MAX_FACES :: 0x7fffffff

MAX_NUMBER_OF_COLOR_SETS :: 0x8

MAX_NUMBER_OF_TEXTURECOORDS :: 0x8

// ---------------------------------------------------------------------------
/**
* @brief A single face in a mesh, referring to multiple vertices.
*
* If mNumIndices is 3, we call the face 'triangle', for mNumIndices > 3
* it's called 'polygon' (hey, that's just a definition!).
* <br>
* aiMesh::mPrimitiveTypes can be queried to quickly examine which types of
* primitive are actually present in a mesh. The #aiProcess_SortByPType flag
* executes a special post-processing algorithm which splits meshes with
* *different* primitive types mixed up (e.g. lines and triangles) in several
* 'clean' sub-meshes. Furthermore there is a configuration option (
* #AI_CONFIG_PP_SBP_REMOVE) to force #aiProcess_SortByPType to remove
* specific kinds of primitives from the imported scene, completely and forever.
* In many cases you'll probably want to set this setting to
* @code
* aiPrimitiveType_LINE|aiPrimitiveType_POINT
* @endcode
* Together with the #aiProcess_Triangulate flag you can then be sure that
* #aiFace::mNumIndices is always 3.
* @note Take a look at the @link data Data Structures page @endlink for
* more information on the layout and winding order of a face.
*/
Face :: struct {
	//! Number of indices defining this face.
	//! The maximum value for this member is #AI_MAX_FACE_INDICES.
	mNumIndices: c.uint,

	//! Pointer to the indices array. Size of the array is given in numIndices.
	mIndices: [^]c.uint,
}

// ---------------------------------------------------------------------------
/** @brief A single influence of a bone on a vertex.
*/
Vertex_Weight :: struct {
	//! Index of the vertex which is influenced by the bone.
	mVertexId: c.uint,

	//! The strength of the influence in the range (0...1).
	//! The influence from all bones at one vertex amounts to 1.
	mWeight: Real,
}

// ---------------------------------------------------------------------------
/** @brief A single bone of a mesh.
*
*  A bone has a name by which it can be found in the frame hierarchy and by
*  which it can be addressed by animations. In addition it has a number of
*  influences on vertices, and a matrix relating the mesh position to the
*  position of the bone at the time of binding.
*/
Bone :: struct {
	/**
	* The name of the bone.
	*/
	mName: String,

	/**
	* The number of vertices affected by this bone.
	* The maximum value for this member is #AI_MAX_BONE_WEIGHTS.
	*/
	mNumWeights: c.uint,

	/**
	* The bone armature node - used for skeleton conversion
	* you must enable aiProcess_PopulateArmatureData to populate this
	*/
	mArmature: ^Node,

	/**
	* The bone node in the scene - used for skeleton conversion
	* you must enable aiProcess_PopulateArmatureData to populate this
	*/
	mNode: ^Node,

	/**
	* The influence weights of this bone, by vertex index.
	*/
	mWeights: [^]Vertex_Weight,

	/**
	* Matrix that transforms from mesh space to bone space in bind pose.
	*
	* This matrix describes the position of the mesh
	* in the local space of this bone when the skeleton was bound.
	* Thus it can be used directly to determine a desired vertex position,
	* given the world-space transform of the bone when animated,
	* and the position of the vertex in mesh space.
	*
	* It is sometimes called an inverse-bind matrix,
	* or inverse bind pose matrix.
	*/
	mOffsetMatrix: Matrix4x4,
}

// ---------------------------------------------------------------------------
/** @brief Enumerates the types of geometric primitives supported by Assimp.
*
*  @see aiFace Face data structure
*  @see aiProcess_SortByPType Per-primitive sorting of meshes
*  @see aiProcess_Triangulate Automatic triangulation
*  @see AI_CONFIG_PP_SBP_REMOVE Removal of specific primitive types.
*/
Primitive_Type_Flag :: enum c.int {
	/**
	* @brief A point primitive.
	*
	* This is just a single vertex in the virtual world,
	* #aiFace contains just one index for such a primitive.
	*/
	POINT = 0,

	/**
	* @brief A line primitive.
	*
	* This is a line defined through a start and an end position.
	* #aiFace contains exactly two indices for such a primitive.
	*/
	LINE = 1,

	/**
	* @brief A triangular primitive.
	*
	* A triangle consists of three indices.
	*/
	TRIANGLE = 2,

	/**
	* @brief A higher-level polygon with more than 3 edges.
	*
	* A triangle is a polygon, but polygon in this context means
	* "all polygons that are not triangles". The "Triangulate"-Step
	* is provided for your convenience, it splits all polygons in
	* triangles (which are much easier to handle).
	*/
	POLYGON = 3,

	/**
	* @brief A flag to determine whether this triangles only mesh is NGON encoded.
	*
	* NGON encoding is a special encoding that tells whether 2 or more consecutive triangles
	* should be considered as a triangle fan. This is identified by looking at the first vertex index.
	* 2 consecutive triangles with the same 1st vertex index are part of the same
	* NGON.
	*
	* At the moment, only quads (concave or convex) are supported, meaning that polygons are 'seen' as
	* triangles, as usual after a triangulation pass.
	*
	* To get an NGON encoded mesh, please use the aiProcess_Triangulate post process.
	*
	* @see aiProcess_Triangulate
	* @link https://github.com/KhronosGroup/glTF/pull/1620
	*/
	NGONEncodingFlag = 4,
}

Primitive_Type_Flags :: distinct bit_set[Primitive_Type_Flag; c.int]

// ---------------------------------------------------------------------------
/** @brief An AnimMesh is an attachment to an #aiMesh stores per-vertex
*  animations for a particular frame.
*
*  You may think of an #aiAnimMesh as a `patch` for the host mesh, which
*  replaces only certain vertex data streams at a particular time.
*  Each mesh stores n attached attached meshes (#aiMesh::mAnimMeshes).
*  The actual relationship between the time line and anim meshes is
*  established by #aiMeshAnim, which references singular mesh attachments
*  by their ID and binds them to a time offset.
*/
Anim_Mesh :: struct {
	/**Anim Mesh name */
	mName: String,

	/** Replacement for aiMesh::mVertices. If this array is non-nullptr,
	*  it *must* contain mNumVertices entries. The corresponding
	*  array in the host mesh must be non-nullptr as well - animation
	*  meshes may neither add or nor remove vertex components (if
	*  a replacement array is nullptr and the corresponding source
	*  array is not, the source data is taken instead)*/
	mVertices: [^]Vector3D,

	/** Replacement for aiMesh::mNormals.  */
	mNormals: [^]Vector3D,

	/** Replacement for aiMesh::mTangents. */
	mTangents: [^]Vector3D,

	/** Replacement for aiMesh::mBitangents. */
	mBitangents: [^]Vector3D,

	/** Replacement for aiMesh::mColors */
	mColors: ^[8]Color4D,

	/** Replacement for aiMesh::mTextureCoords */
	mTextureCoords: ^[8]Vector3D,

	/** The number of vertices in the aiAnimMesh, and thus the length of all
	* the member arrays.
	*
	* This has always the same value as the mNumVertices property in the
	* corresponding aiMesh. It is duplicated here merely to make the length
	* of the member arrays accessible even if the aiMesh is not known, e.g.
	* from language bindings.
	*/
	mNumVertices: c.uint,

	/**
	* Weight of the AnimMesh.
	*/
	mWeight: f32,
}

// ---------------------------------------------------------------------------
/** @brief Enumerates the methods of mesh morphing supported by Assimp.
*/
Morphing_Method :: enum c.int {
	/** Morphing method to be determined */
	UNKNOWN = 0,

	/** Interpolation between morph targets */
	VERTEX_BLEND = 1,

	/** Normalized morphing between morph targets  */
	MORPH_NORMALIZED = 2,

	/** Relative morphing between morph targets  */
	MORPH_RELATIVE = 3,
}

// ---------------------------------------------------------------------------
/** @brief A mesh represents a geometry or model with a single material.
*
* It usually consists of a number of vertices and a series of primitives/faces
* referencing the vertices. In addition there might be a series of bones, each
* of them addressing a number of vertices with a certain weight. Vertex data
* is presented in channels with each channel containing a single per-vertex
* information such as a set of texture coordinates or a normal vector.
* If a data pointer is non-null, the corresponding data stream is present.
* From C++-programs you can also use the comfort functions Has*() to
* test for the presence of various data streams.
*
* A Mesh uses only a single material which is referenced by a material ID.
* @note The mPositions member is usually not optional. However, vertex positions
* *could* be missing if the #AI_SCENE_FLAGS_INCOMPLETE flag is set in
* @code
* aiScene::mFlags
* @endcode
*/
Mesh :: struct {
	/**
	* Bitwise combination of the members of the #aiPrimitiveType enum.
	* This specifies which types of primitives are present in the mesh.
	* The "SortByPrimitiveType"-Step can be used to make sure the
	* output meshes consist of one primitive type each.
	*/
	mPrimitiveTypes: Primitive_Type_Flags,

	/**
	* The number of vertices in this mesh.
	* This is also the size of all of the per-vertex data arrays.
	* The maximum value for this member is #AI_MAX_VERTICES.
	*/
	mNumVertices: c.uint,

	/**
	* The number of primitives (triangles, polygons, lines) in this  mesh.
	* This is also the size of the mFaces array.
	* The maximum value for this member is #AI_MAX_FACES.
	*/
	mNumFaces: c.uint,

	/**
	* @brief Vertex positions.
	*
	* This array is always present in a mesh. The array is
	* mNumVertices in size.
	*/
	mVertices: [^]Vector3D,

	/**
	* @brief Vertex normals.
	*
	* The array contains normalized vectors, nullptr if not present.
	* The array is mNumVertices in size. Normals are undefined for
	* point and line primitives. A mesh consisting of points and
	* lines only may not have normal vectors. Meshes with mixed
	* primitive types (i.e. lines and triangles) may have normals,
	* but the normals for vertices that are only referenced by
	* point or line primitives are undefined and set to QNaN (WARN:
	* qNaN compares to inequal to *everything*, even to qNaN itself.
	* Using code like this to check whether a field is qnan is:
	* @code
	* #define IS_QNAN(f) (f != f)
	* @endcode
	* still dangerous because even 1.f == 1.f could evaluate to false! (
	* remember the subtleties of IEEE754 artithmetics). Use stuff like
	* @c fpclassify instead.
	* @note Normal vectors computed by Assimp are always unit-length.
	* However, this needn't apply for normals that have been taken
	* directly from the model file.
	*/
	mNormals: [^]Vector3D,

	/**
	* @brief Vertex tangents.
	*
	* The tangent of a vertex points in the direction of the positive
	* X texture axis. The array contains normalized vectors, nullptr if
	* not present. The array is mNumVertices in size. A mesh consisting
	* of points and lines only may not have normal vectors. Meshes with
	* mixed primitive types (i.e. lines and triangles) may have
	* normals, but the normals for vertices that are only referenced by
	* point or line primitives are undefined and set to qNaN.  See
	* the #mNormals member for a detailed discussion of qNaNs.
	* @note If the mesh contains tangents, it automatically also
	* contains bitangents.
	*/
	mTangents: [^]Vector3D,

	/**
	* @brief Vertex bitangents.
	*
	* The bitangent of a vertex points in the direction of the positive
	* Y texture axis. The array contains normalized vectors, nullptr if not
	* present. The array is mNumVertices in size.
	* @note If the mesh contains tangents, it automatically also contains
	* bitangents.
	*/
	mBitangents: [^]Vector3D,

	/**
	* @brief Vertex color sets.
	*
	* A mesh may contain 0 to #AI_MAX_NUMBER_OF_COLOR_SETS vertex
	* colors per vertex. nullptr if not present. Each array is
	* mNumVertices in size if present.
	*/
	mColors: [8][^]Color4D,

	/**
	* @brief Vertex texture coordinates, also known as UV channels.
	*
	* A mesh may contain 0 to AI_MAX_NUMBER_OF_TEXTURECOORDS channels per
	* vertex. Used and unused (nullptr) channels may go in any order.
	* The array is mNumVertices in size.
	*/
	mTextureCoords: [8][^]Vector3D,

	/**
	* @brief Specifies the number of components for a given UV channel.
	*
	* Up to three channels are supported (UVW, for accessing volume
	* or cube maps). If the value is 2 for a given channel n, the
	* component p.z of mTextureCoords[n][p] is set to 0.0f.
	* If the value is 1 for a given channel, p.y is set to 0.0f, too.
	* @note 4D coordinates are not supported
	*/
	mNumUVComponents: [8]c.uint,

	/**
	* @brief The faces the mesh is constructed from.
	*
	* Each face refers to a number of vertices by their indices.
	* This array is always present in a mesh, its size is given
	*  in mNumFaces. If the #AI_SCENE_FLAGS_NON_VERBOSE_FORMAT
	* is NOT set each face references an unique set of vertices.
	*/
	mFaces: [^]Face,

	/**
	* The number of bones this mesh contains. Can be 0, in which case the mBones array is nullptr.
	*/
	mNumBones: c.uint,

	/**
	* @brief The bones of this mesh.
	*
	* A bone consists of a name by which it can be found in the
	* frame hierarchy and a set of vertex weights.
	*/
	mBones: [^]^Bone,

	/**
	* @brief The material used by this mesh.
	*
	* A mesh uses only a single material. If an imported model uses
	* multiple materials, the import splits up the mesh. Use this value
	* as index into the scene's material list.
	*/
	mMaterialIndex: c.uint,

	/**
	*  Name of the mesh. Meshes can be named, but this is not a
	*  requirement and leaving this field empty is totally fine.
	*  There are mainly three uses for mesh names:
	*   - some formats name nodes and meshes independently.
	*   - importers tend to split meshes up to meet the
	*      one-material-per-mesh requirement. Assigning
	*      the same (dummy) name to each of the result meshes
	*      aids the caller at recovering the original mesh
	*      partitioning.
	*   - Vertex animations refer to meshes by their names.
	*/
	mName: String,

	/**
	* The number of attachment meshes.
	* Currently known to work with loaders:
	* - Collada
	* - gltf
	*/
	mNumAnimMeshes: c.uint,

	/**
	* Attachment meshes for this mesh, for vertex-based animation.
	* Attachment meshes carry replacement data for some of the
	* mesh'es vertex components (usually positions, normals).
	* Currently known to work with loaders:
	* - Collada
	* - gltf
	*/
	mAnimMeshes: [^]^Anim_Mesh,

	/**
	*  Method of morphing when anim-meshes are specified.
	*  @see aiMorphingMethod to learn more about the provided morphing targets.
	*/
	mMethod: Morphing_Method,

	/**
	*  The bounding box.
	*/
	mAABB: Aabb,

	/**
	* Vertex UV stream names. Pointer to array of size AI_MAX_NUMBER_OF_TEXTURECOORDS
	*/
	mTextureCoordsNames: [^]^String,
}

/**
* @brief  A skeleton bone represents a single bone is a skeleton structure.
*
* Skeleton-Animations can be represented via a skeleton struct, which describes
* a hierarchical tree assembled from skeleton bones. A bone is linked to a mesh.
* The bone knows its parent bone. If there is no parent bone the parent id is
* marked with -1.
* The skeleton-bone stores a pointer to its used armature. If there is no
* armature this value if set to nullptr.
* A skeleton bone stores its offset-matrix, which is the absolute transformation
* for the bone. The bone stores the locale transformation to its parent as well.
* You can compute the offset matrix by multiplying the hierarchy like:
* Tree: s1 -> s2 -> s3
* Offset-Matrix s3 = locale-s3 * locale-s2 * locale-s1
*/
Skeleton_Bone :: struct {
	/// The parent bone index, is -1 one if this bone represents the root bone.
	mParent: c.int,

	/// @brief The bone armature node - used for skeleton conversion
	/// you must enable aiProcess_PopulateArmatureData to populate this
	mArmature: ^Node,

	/// @brief The bone node in the scene - used for skeleton conversion
	/// you must enable aiProcess_PopulateArmatureData to populate this
	mNode: ^Node,

	/// @brief The number of weights
	mNumnWeights: c.uint,

	/// The mesh index, which will get influenced by the weight.
	mMeshId: ^Mesh,

	/// The influence weights of this bone, by vertex index.
	mWeights: [^]Vertex_Weight,

	/** Matrix that transforms from bone space to mesh space in bind pose.
	*
	* This matrix describes the position of the mesh
	* in the local space of this bone when the skeleton was bound.
	* Thus it can be used directly to determine a desired vertex position,
	* given the world-space transform of the bone when animated,
	* and the position of the vertex in mesh space.
	*
	* It is sometimes called an inverse-bind matrix,
	* or inverse bind pose matrix.
	*/
	mOffsetMatrix: Matrix4x4,

	/// Matrix that transforms the locale bone in bind pose.
	mLocalMatrix: Matrix4x4,
}

/**
* @brief A skeleton represents the bone hierarchy of an animation.
*
* Skeleton animations can be described as a tree of bones:
*                  root
*                    |
*                  node1
*                  /   \
*               node3  node4
* If you want to calculate the transformation of node three you need to compute the
* transformation hierarchy for the transformation chain of node3:
* root->node1->node3
* Each node is represented as a skeleton instance.
*/
Skeleton :: struct {
	/**
	*  @brief The name of the skeleton instance.
	*/
	mName: String,

	/**
	*  @brief  The number of bones in the skeleton.
	*/
	mNumBones: c.uint,

	/**
	*  @brief The bone instance in the skeleton.
	*/
	mBones: [^]^Skeleton_Bone,
}

