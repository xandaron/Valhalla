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
/** @file scene.h
*  @brief Defines the data structures in which the imported scene is returned.
*/
package assimp

import "core:c"

_ :: c

when ODIN_OS == .Windows {
    foreign import lib {
        "vendor:zlib/libz.lib",
        "libassimp.lib",
    }
}
else {
    foreign import lib {
        "system:z",
        "system:assimp",
    }
}

// SCENE_H_INC :: 

// -------------------------------------------------------------------------------
/**
* A node in the imported hierarchy.
*
* Each node has name, a parent node (except for the root node),
* a transformation relative to its parent and possibly several child nodes.
* Simple file formats don't support hierarchical structures - for these formats
* the imported scene does consist of only a single root node without children.
*/
// -------------------------------------------------------------------------------
Node :: struct {
	/** The name of the node.
	*
	* The name might be empty (length of zero) but all nodes which
	* need to be referenced by either bones or animations are named.
	* Multiple nodes may have the same name, except for nodes which are referenced
	* by bones (see #aiBone and #aiMesh::mBones). Their names *must* be unique.
	*
	* Cameras and lights reference a specific node by name - if there
	* are multiple nodes with this name, they are assigned to each of them.
	* <br>
	* There are no limitations with regard to the characters contained in
	* the name string as it is usually taken directly from the source file.
	*
	* Implementations should be able to handle tokens such as whitespace, tabs,
	* line feeds, quotation marks, ampersands etc.
	*
	* Sometimes assimp introduces new nodes not present in the source file
	* into the hierarchy (usually out of necessity because sometimes the
	* source hierarchy format is simply not compatible). Their names are
	* surrounded by @verbatim <> @endverbatim e.g.
	*  @verbatim<DummyRootNode> @endverbatim.
	*/
	mName: String,

	/** The transformation relative to the node's parent. */
	mTransformation: Matrix4x4,

	/** Parent node. nullptr if this node is the root node. */
	mParent: ^Node,

	/** The number of child nodes of this node. */
	mNumChildren: c.uint,

	/** The child nodes of this node. nullptr if mNumChildren is 0. */
	mChildren: [^]^Node,

	/** The number of meshes of this node. */
	mNumMeshes: c.uint,

	/** The meshes of this node. Each entry is an index into the
	* mesh list of the #aiScene.
	*/
	mMeshes: [^]c.uint,

	/** Metadata associated with this node or nullptr if there is no metadata.
	*  Whether any metadata is generated depends on the source file format. See the
	* @link importer_notes @endlink page for more information on every source file
	* format. Importers that don't document any metadata don't write any.
	*/
	mMetaData: ^Metadata,
}

SCENE_FLAGS_INCOMPLETE :: 0x1

SCENE_FLAGS_VALIDATED :: 0x2

SCENE_FLAGS_VALIDATION_WARNING :: 0x4

SCENE_FLAGS_NON_VERBOSE_FORMAT :: 0x8

SCENE_FLAGS_TERRAIN :: 0x10

SCENE_FLAGS_ALLOW_SHARED :: 0x20

// -------------------------------------------------------------------------------
/** The root structure of the imported data.
*
*  Everything that was imported from the given file can be accessed from here.
*  Objects of this class are generally maintained and owned by Assimp, not
*  by the caller. You shouldn't want to instance it, nor should you ever try to
*  delete a given scene on your own.
*/
// -------------------------------------------------------------------------------
Scene :: struct {
	/** Any combination of the AI_SCENE_FLAGS_XXX flags. By default
	* this value is 0, no flags are set. Most applications will
	* want to reject all scenes with the AI_SCENE_FLAGS_INCOMPLETE
	* bit set.
	*/
	mFlags: c.uint,

	/** The root node of the hierarchy.
	*
	* There will always be at least the root node if the import
	* was successful (and no special flags have been set).
	* Presence of further nodes depends on the format and content
	* of the imported file.
	*/
	mRootNode: ^Node,

	/** The number of meshes in the scene. */
	mNumMeshes: c.uint,

	/** The array of meshes.
	*
	* Use the indices given in the aiNode structure to access
	* this array. The array is mNumMeshes in size. If the
	* AI_SCENE_FLAGS_INCOMPLETE flag is not set there will always
	* be at least ONE material.
	*/
	mMeshes: [^]^Mesh,

	/** The number of materials in the scene. */
	mNumMaterials: c.uint,

	/** The array of materials.
	*
	* Use the index given in each aiMesh structure to access this
	* array. The array is mNumMaterials in size. If the
	* AI_SCENE_FLAGS_INCOMPLETE flag is not set there will always
	* be at least ONE material.
	*/
	mMaterials: [^]^Material,

	/** The number of animations in the scene. */
	mNumAnimations: c.uint,

	/** The array of animations.
	*
	* All animations imported from the given file are listed here.
	* The array is mNumAnimations in size.
	*/
	mAnimations: [^]^Animation,

	/** The number of textures embedded into the file */
	mNumTextures: c.uint,

	/** The array of embedded textures.
	*
	* Not many file formats embed their textures into the file.
	* An example is Quake's MDL format (which is also used by
	* some GameStudio versions)
	*/
	mTextures: [^]^Texture,

	/** The number of light sources in the scene. Light sources
	* are fully optional, in most cases this attribute will be 0
	*/
	mNumLights: c.uint,

	/** The array of light sources.
	*
	* All light sources imported from the given file are
	* listed here. The array is mNumLights in size.
	*/
	mLights: [^]^Light,

	/** The number of cameras in the scene. Cameras
	* are fully optional, in most cases this attribute will be 0
	*/
	mNumCameras: c.uint,

	/** The array of cameras.
	*
	* All cameras imported from the given file are listed here.
	* The array is mNumCameras in size. The first camera in the
	* array (if existing) is the default camera view into
	* the scene.
	*/
	mCameras: [^]^Camera,

	/**
	*  @brief  The global metadata assigned to the scene itself.
	*
	*  This data contains global metadata which belongs to the scene like
	*  unit-conversions, versions, vendors or other model-specific data. This
	*  can be used to store format-specific metadata as well.
	*/
	mMetaData: ^Metadata,

	/** The name of the scene itself.
	*/
	mName: String,

	/**
	*
	*/
	mNumSkeletons: c.uint,

	/**
	*
	*/
	mSkeletons: [^]^Skeleton,
	mPrivate: cstring,
}

