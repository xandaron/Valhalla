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
/** @file config.h
*  @brief Defines constants for configurable properties for the library
*
*  Typically these properties are set via
*  #Assimp::Importer::SetPropertyFloat,
*  #Assimp::Importer::SetPropertyInteger or
*  #Assimp::Importer::SetPropertyString,
*  depending on the data type of a property. All properties have a
*  default value. See the doc for the mentioned methods for more details.
*
*  <br><br>
*  The corresponding functions for use with the plain-c API are:
*  #aiSetImportPropertyInteger,
*  #aiSetImportPropertyFloat,
*  #aiSetImportPropertyString
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

CONFIG_GLOB_MEASURE_TIME :: "GLOB_MEASURE_TIME"

CONFIG_IMPORT_NO_SKELETON_MESHES :: "IMPORT_NO_SKELETON_MESHES"

CONFIG_PP_SBBC_MAX_BONES :: "PP_SBBC_MAX_BONES"

CONFIG_PP_CT_MAX_SMOOTHING_ANGLE :: "PP_CT_MAX_SMOOTHING_ANGLE"

CONFIG_PP_CT_TEXTURE_CHANNEL_INDEX :: "PP_CT_TEXTURE_CHANNEL_INDEX"

CONFIG_PP_GSN_MAX_SMOOTHING_ANGLE :: "PP_GSN_MAX_SMOOTHING_ANGLE"

CONFIG_IMPORT_MDL_COLORMAP :: "IMPORT_MDL_COLORMAP"

CONFIG_PP_RRM_EXCLUDE_LIST :: "PP_RRM_EXCLUDE_LIST"

CONFIG_PP_PTV_KEEP_HIERARCHY :: "PP_PTV_KEEP_HIERARCHY"

CONFIG_PP_PTV_NORMALIZE :: "PP_PTV_NORMALIZE"

CONFIG_PP_PTV_ADD_ROOT_TRANSFORMATION :: "PP_PTV_ADD_ROOT_TRANSFORMATION"

CONFIG_PP_PTV_ROOT_TRANSFORMATION :: "PP_PTV_ROOT_TRANSFORMATION"

CONFIG_CHECK_IDENTITY_MATRIX_EPSILON :: "CHECK_IDENTITY_MATRIX_EPSILON"

CONFIG_PP_FD_REMOVE :: "PP_FD_REMOVE"

CONFIG_PP_FD_CHECKAREA :: "PP_FD_CHECKAREA"

CONFIG_PP_OG_EXCLUDE_LIST :: "PP_OG_EXCLUDE_LIST"

CONFIG_PP_SLM_TRIANGLE_LIMIT :: "PP_SLM_TRIANGLE_LIMIT"

CONFIG_PP_SLM_VERTEX_LIMIT :: "PP_SLM_VERTEX_LIMIT"

CONFIG_PP_LBW_MAX_WEIGHTS :: "PP_LBW_MAX_WEIGHTS"

CONFIG_PP_DB_THRESHOLD :: "PP_DB_THRESHOLD"

CONFIG_PP_DB_ALL_OR_NONE :: "PP_DB_ALL_OR_NONE"

/** @brief Set the size of the post-transform vertex cache to optimize the
 *    vertices for. This configures the #aiProcess_ImproveCacheLocality step.
 *
 * The size is given in vertices. Of course you can't know how the vertex
 * format will exactly look like after the import returns, but you can still
 * guess what your meshes will probably have.
 * @note The default value is #PP_ICL_PTCACHE_SIZE. That results in slight
 * performance improvements for most nVidia/AMD cards since 2002.
 * Property type: integer.
 */
CONFIG_PP_ICL_PTCACHE_SIZE   :: "PP_ICL_PTCACHE_SIZE"

// ---------------------------------------------------------------------------
/** @brief Enumerates components of the aiScene and aiMesh data structures
*  that can be excluded from the import using the #aiProcess_RemoveComponent step.
*
*  See the documentation to #aiProcess_RemoveComponent for more details.
*/
Component_Flag :: enum c.int {
	NORMALS                 = 1,
	TANGENTS_AND_BITANGENTS = 2,

	/** ALL color sets
	* Use aiComponent_COLORn(N) to specify the N'th set */
	COLORS = 3,

	/** ALL texture UV sets
	* aiComponent_TEXCOORDn(N) to specify the N'th set  */
	TEXCOORDS = 4,

	/** Removes all bone weights from all meshes.
	* The scenegraph nodes corresponding to the bones are NOT removed.
	* use the #aiProcess_OptimizeGraph step to do this */
	BONEWEIGHTS = 5,

	/** Removes all node animations (aiScene::mAnimations).
	* The corresponding scenegraph nodes are NOT removed.
	* use the #aiProcess_OptimizeGraph step to do this */
	ANIMATIONS = 6,

	/** Removes all embedded textures (aiScene::mTextures) */
	TEXTURES = 7,

	/** Removes all light sources (aiScene::mLights).
	* The corresponding scenegraph nodes are NOT removed.
	* use the #aiProcess_OptimizeGraph step to do this */
	LIGHTS = 8,

	/** Removes all cameras (aiScene::mCameras).
	* The corresponding scenegraph nodes are NOT removed.
	* use the #aiProcess_OptimizeGraph step to do this */
	CAMERAS = 9,

	/** Removes all meshes (aiScene::mMeshes). */
	MESHES = 10,

	/** Removes all materials. One default material will
	* be generated, so aiScene::mNumMaterials will be 1. */
	MATERIALS = 11,
}

Component_Flags :: distinct bit_set[Component_Flag; c.int]

CONFIG_PP_RVC_FLAGS :: "PP_RVC_FLAGS"

CONFIG_PP_SBP_REMOVE :: "PP_SBP_REMOVE"

CONFIG_PP_FID_ANIM_ACCURACY :: "PP_FID_ANIM_ACCURACY"

CONFIG_PP_FID_IGNORE_TEXTURECOORDS :: "PP_FID_IGNORE_TEXTURECOORDS"

// TransformUVCoords evaluates UV scalings
UVTRAFO_SCALING :: 0x1

// TransformUVCoords evaluates UV rotations
UVTRAFO_ROTATION :: 0x2

// TransformUVCoords evaluates UV translation
UVTRAFO_TRANSLATION :: 0x4

// Everything baked together -> default value
// UVTRAFO_ALL :: Ai_Uvtrafo_Scaling | Ai_Uvtrafo_Rotation | Ai_Uvtrafo_Translation

CONFIG_PP_TUV_EVALUATE :: "PP_TUV_EVALUATE"

CONFIG_FAVOUR_SPEED :: "FAVOUR_SPEED"

CONFIG_IMPORT_SCHEMA_DOCUMENT_PROVIDER :: "IMPORT_SCHEMA_DOCUMENT_PROVIDER"

CONFIG_IMPORT_FBX_READ_ALL_GEOMETRY_LAYERS :: "IMPORT_FBX_READ_ALL_GEOMETRY_LAYERS"

CONFIG_IMPORT_FBX_READ_ALL_MATERIALS :: "IMPORT_FBX_READ_ALL_MATERIALS"

CONFIG_IMPORT_FBX_READ_MATERIALS :: "IMPORT_FBX_READ_MATERIALS"

CONFIG_IMPORT_FBX_READ_TEXTURES :: "IMPORT_FBX_READ_TEXTURES"

CONFIG_IMPORT_FBX_READ_CAMERAS :: "IMPORT_FBX_READ_CAMERAS"

CONFIG_IMPORT_FBX_READ_LIGHTS :: "IMPORT_FBX_READ_LIGHTS"

CONFIG_IMPORT_FBX_READ_ANIMATIONS :: "IMPORT_FBX_READ_ANIMATIONS"

CONFIG_IMPORT_FBX_READ_WEIGHTS :: "IMPORT_FBX_READ_WEIGHTS"

CONFIG_IMPORT_FBX_STRICT_MODE :: "IMPORT_FBX_STRICT_MODE"

CONFIG_IMPORT_FBX_PRESERVE_PIVOTS :: "IMPORT_FBX_PRESERVE_PIVOTS"

CONFIG_IMPORT_FBX_OPTIMIZE_EMPTY_ANIMATION_CURVES :: "IMPORT_FBX_OPTIMIZE_EMPTY_ANIMATION_CURVES"

CONFIG_IMPORT_FBX_EMBEDDED_TEXTURES_LEGACY_NAMING :: "AI_CONFIG_IMPORT_FBX_EMBEDDED_TEXTURES_LEGACY_NAMING"

CONFIG_IMPORT_REMOVE_EMPTY_BONES :: "AI_CONFIG_IMPORT_REMOVE_EMPTY_BONES"

CONFIG_FBX_CONVERT_TO_M :: "AI_CONFIG_FBX_CONVERT_TO_M"

CONFIG_IMPORT_FBX_IGNORE_UP_DIRECTION :: "AI_CONFIG_IMPORT_FBX_IGNORE_UP_DIRECTION"

CONFIG_FBX_USE_SKELETON_BONE_CONTAINER :: "AI_CONFIG_FBX_USE_SKELETON_BONE_CONTAINER"

/** @brief  Set the vertex animation keyframe to be imported
 *
 * ASSIMP does not support vertex keyframes (only bone animation is supported).
 * The library reads only one frame of models with vertex animations.
 * By default this is the first frame.
 * \note The default value is 0. This option applies to all importers.
 *   However, it is also possible to override the global setting
 *   for a specific loader. You can use the AI_CONFIG_IMPORT_XXX_KEYFRAME
 *   options (where XXX is a placeholder for the file format for which you
 *   want to override the global setting).
 * Property type: integer.
 */
CONFIG_IMPORT_GLOBAL_KEYFRAME    :: "IMPORT_GLOBAL_KEYFRAME"

CONFIG_IMPORT_MD3_KEYFRAME       :: "IMPORT_MD3_KEYFRAME"
CONFIG_IMPORT_MD2_KEYFRAME       :: "IMPORT_MD2_KEYFRAME"
CONFIG_IMPORT_MDL_KEYFRAME       :: "IMPORT_MDL_KEYFRAME"
CONFIG_IMPORT_MDC_KEYFRAME       :: "IMPORT_MDC_KEYFRAME"
CONFIG_IMPORT_SMD_KEYFRAME       :: "IMPORT_SMD_KEYFRAME"
CONFIG_IMPORT_UNREAL_KEYFRAME    :: "IMPORT_UNREAL_KEYFRAME"

/** @brief Set whether the MDL (HL1) importer will read animations.
 *
 * The default value is true (1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_READ_ANIMATIONS :: "IMPORT_MDL_HL1_READ_ANIMATIONS"

/** @brief Set whether the MDL (HL1) importer will read animation events.
 * \note This property requires AI_CONFIG_IMPORT_MDL_HL1_READ_ANIMATIONS to be set to true.
 *
 * The default value is true (1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_READ_ANIMATION_EVENTS :: "IMPORT_MDL_HL1_READ_ANIMATION_EVENTS"

/** @brief Set whether you want to convert the HS1 coordinate system in a special way.
 * The default value is true (S1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_TRANSFORM_COORD_SYSTEM :: "TRANSFORM COORDSYSTEM FOR HS! MODELS"

/** @brief Set whether the MDL (HL1) importer will read blend controllers.
 * \note This property requires AI_CONFIG_IMPORT_MDL_HL1_READ_ANIMATIONS to be set to true.
 *
 * The default value is true (1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_READ_BLEND_CONTROLLERS :: "IMPORT_MDL_HL1_READ_BLEND_CONTROLLERS"

/** @brief Set whether the MDL (HL1) importer will read sequence transition graph.
 * \note This property requires AI_CONFIG_IMPORT_MDL_HL1_READ_ANIMATIONS to be set to true.
 *
 * The default value is true (1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_READ_SEQUENCE_TRANSITIONS :: "IMPORT_MDL_HL1_READ_SEQUENCE_TRANSITIONS"

/** @brief Set whether the MDL (HL1) importer will read attachments info.
 *
 * The default value is true (1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_READ_ATTACHMENTS :: "IMPORT_MDL_HL1_READ_ATTACHMENTS"

/** @brief Set whether the MDL (HL1) importer will read bone controllers info.
 *
 * The default value is true (1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_READ_BONE_CONTROLLERS :: "IMPORT_MDL_HL1_READ_BONE_CONTROLLERS"

/** @brief Set whether the MDL (HL1) importer will read hitboxes info.
 *
 * The default value is true (1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_READ_HITBOXES :: "IMPORT_MDL_HL1_READ_HITBOXES"

/** @brief Set whether the MDL (HL1) importer will read miscellaneous global model info.
 *
 * The default value is true (1)
 * Property type: bool
 */
CONFIG_IMPORT_MDL_HL1_READ_MISC_GLOBAL_INFO :: "IMPORT_MDL_HL1_READ_MISC_GLOBAL_INFO"

/** Smd load multiple animations
 *
 *  Property type: bool. Default value: true.
 */
CONFIG_IMPORT_SMD_LOAD_ANIMATION_LIST :: "IMPORT_SMD_LOAD_ANIMATION_LIST"

CONFIG_IMPORT_AC_SEPARATE_BFCULL :: "IMPORT_AC_SEPARATE_BFCULL"

CONFIG_IMPORT_AC_EVAL_SUBDIVISION :: "IMPORT_AC_EVAL_SUBDIVISION"

CONFIG_IMPORT_UNREAL_HANDLE_FLAGS :: "UNREAL_HANDLE_FLAGS"

CONFIG_IMPORT_TER_MAKE_UVS :: "IMPORT_TER_MAKE_UVS"

CONFIG_IMPORT_ASE_RECONSTRUCT_NORMALS :: "IMPORT_ASE_RECONSTRUCT_NORMALS"

CONFIG_IMPORT_MD3_HANDLE_MULTIPART :: "IMPORT_MD3_HANDLE_MULTIPART"

CONFIG_IMPORT_MD3_SKIN_NAME :: "IMPORT_MD3_SKIN_NAME"

CONFIG_IMPORT_MD3_LOAD_SHADERS :: "IMPORT_MD3_LOAD_SHADERS"

CONFIG_IMPORT_MD3_SHADER_SRC :: "IMPORT_MD3_SHADER_SRC"

CONFIG_IMPORT_LWO_ONE_LAYER_ONLY :: "IMPORT_LWO_ONE_LAYER_ONLY"

CONFIG_IMPORT_MD5_NO_ANIM_AUTOLOAD :: "IMPORT_MD5_NO_ANIM_AUTOLOAD"

CONFIG_IMPORT_LWS_ANIM_START :: "IMPORT_LWS_ANIM_START"

CONFIG_IMPORT_LWS_ANIM_END :: "IMPORT_LWS_ANIM_END"

CONFIG_IMPORT_IRR_ANIM_FPS :: "IMPORT_IRR_ANIM_FPS"

CONFIG_IMPORT_OGRE_MATERIAL_FILE :: "IMPORT_OGRE_MATERIAL_FILE"

CONFIG_IMPORT_OGRE_TEXTURETYPE_FROM_FILENAME :: "IMPORT_OGRE_TEXTURETYPE_FROM_FILENAME"

 /** @brief Specifies whether the Android JNI asset extraction is supported.
  *
  * Turn on this option if you want to manage assets in native
  * Android application without having to keep the internal directory and asset
  * manager pointer.
  */
CONFIG_ANDROID_JNI_ASSIMP_MANAGER_SUPPORT :: "AI_CONFIG_ANDROID_JNI_ASSIMP_MANAGER_SUPPORT"

/** @brief Specifies whether the IFC loader skips over IfcSpace elements.
 *
 * IfcSpace elements (and their geometric representations) are used to
 * represent, well, free space in a building storey.<br>
 * Property type: Bool. Default value: true.
 */
CONFIG_IMPORT_IFC_SKIP_SPACE_REPRESENTATIONS :: "IMPORT_IFC_SKIP_SPACE_REPRESENTATIONS"

/** @brief Specifies whether the IFC loader will use its own, custom triangulation
 *   algorithm to triangulate wall and floor meshes.
 *
 * If this property is set to false, walls will be either triangulated by
 * #aiProcess_Triangulate or will be passed through as huge polygons with
 * faked holes (i.e. holes that are connected with the outer boundary using
 * a dummy edge). It is highly recommended to set this property to true
 * if you want triangulated data because #aiProcess_Triangulate is known to
 * have problems with the kind of polygons that the IFC loader spits out for
 * complicated meshes.
 * Property type: Bool. Default value: true.
 */
CONFIG_IMPORT_IFC_CUSTOM_TRIANGULATION :: "IMPORT_IFC_CUSTOM_TRIANGULATION"

/** @brief  Set the tessellation conic angle for IFC smoothing curves.
 *
 * This is used by the IFC importer to determine the tessellation parameter
 * for smoothing curves.
 * @note The default value is AI_IMPORT_IFC_DEFAULT_SMOOTHING_ANGLE and the
 * accepted values are in range [5.0, 120.0].
 * Property type: Float.
 */
CONFIG_IMPORT_IFC_SMOOTHING_ANGLE :: "IMPORT_IFC_SMOOTHING_ANGLE"

/** @brief  Set the tessellation for IFC cylindrical shapes.
 *
 * This is used by the IFC importer to determine the tessellation parameter
 * for cylindrical shapes, i.e. the number of segments used to approximate a circle.
 * @note The default value is AI_IMPORT_IFC_DEFAULT_CYLINDRICAL_TESSELLATION and the
 * accepted values are in range [3, 180].
 * Property type: Integer.
 */
CONFIG_IMPORT_IFC_CYLINDRICAL_TESSELLATION :: "IMPORT_IFC_CYLINDRICAL_TESSELLATION"

/** @brief Specifies whether the Collada loader will ignore the provided up direction.
 *
 * If this property is set to true, the up direction provided in the file header will
 * be ignored and the file will be loaded as is.
 * Property type: Bool. Default value: false.
 */
CONFIG_IMPORT_COLLADA_IGNORE_UP_DIRECTION :: "IMPORT_COLLADA_IGNORE_UP_DIRECTION"

/** @brief Specifies whether the Collada loader will ignore the provided unit size.
 *
 * If this property is set to true, the unit size provided in the file header will
 * be ignored and the file will be loaded without scaling the assets.
 * Property type: Bool. Default value: false.
 */
CONFIG_IMPORT_COLLADA_IGNORE_UNIT_SIZE :: "IMPORT_COLLADA_IGNORE_UNIT_SIZE"

/** @brief Specifies whether the Collada loader should use Collada names.
 *
 * If this property is set to true, the Collada names will be used as the node and
 * mesh names. The default is to use the id tag (resp. sid tag, if no id tag is present)
 * instead.
 * Property type: Bool. Default value: false.
 */
CONFIG_IMPORT_COLLADA_USE_COLLADA_NAMES :: "IMPORT_COLLADA_USE_COLLADA_NAMES"

/** @brief Specifies the xfile use double for real values of float
 *
 * Property type: Bool. Default value: false.
 */
CONFIG_EXPORT_XFILE_64BIT :: "EXPORT_XFILE_64BIT"

/** @brief Specifies whether the assimp export shall be able to export point clouds
 *
 *  When this flag is not defined the render data has to contain valid faces.
 *  Point clouds are only a collection of vertices which have nor spatial organization
 *  by a face and the validation process will remove them. Enabling this feature will
 *  switch off the flag and enable the functionality to export pure point clouds.
 *
 * Property type: Bool. Default value: false.
 */
CONFIG_EXPORT_POINT_CLOUDS :: "EXPORT_POINT_CLOUDS"

/** @brief Specifies whether to use the deprecated KHR_materials_pbrSpecularGlossiness extension
 * 
 * When this flag is undefined any material with specularity will use the new KHR_materials_specular
 * extension. Enabling this flag will revert to the deprecated extension. Note that exporting
 * KHR_materials_pbrSpecularGlossiness with extensions other than KHR_materials_unlit is unsupported,
 * including the basic pbrMetallicRoughness spec.
 *
 * Property type: Bool. Default value: false.
 */
CONFIG_USE_GLTF_PBR_SPECULAR_GLOSSINESS :: "USE_GLTF_PBR_SPECULAR_GLOSSINESS"

CONFIG_EXPORT_GLTF_UNLIMITED_SKINNING_BONES_PER_VERTEX :: "USE_UNLIMITED_BONES_PER VERTEX"

CONFIG_EXPORT_FBX_TRANSPARENCY_FACTOR_REFER_TO_OPACITY :: "EXPORT_FBX_TRANSPARENCY_FACTOR_REFER_TO_OPACITY"

/**
 * @brief Specifies the blob name, assimp uses for exporting.
 * 
 * Some formats require auxiliary files to be written, that need to be linked back into 
 * the original file. For example, OBJ files export materials to a separate MTL file and
 * use the `mtllib` keyword to reference this file.
 * 
 * When exporting blobs using #ExportToBlob, assimp does not know the name of the blob
 * file and thus outputs `mtllib $blobfile.mtl`, which might not be desired, since the 
 * MTL file might be called differently. 
 * 
 * This property can be used to give the exporter a hint on how to use the magic 
 * `$blobfile` keyword. If the exporter detects the keyword and is provided with a name
 * for the blob, it instead uses this name.
 */
CONFIG_EXPORT_BLOB_NAME :: "EXPORT_BLOB_NAME"

/**
 *  @brief  Specifies a global key factor for scale, float value
 */
CONFIG_GLOBAL_SCALE_FACTOR_KEY :: "GLOBAL_SCALE_FACTOR"

CONFIG_APP_SCALE_KEY :: "APP_SCALE_FACTOR"
