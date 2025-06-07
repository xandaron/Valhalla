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
/** @file material.h
*  @brief Defines the material system of the library
*/
package assimp

import "core:c"

_ :: c

import zlib "vendor:zlib"

// I need to figue out this linker flag out as the compiler will complain that zlib is missing
// @(extra_linker_flags="")
when ODIN_OS == .Windows {
    foreign import lib "libassimp.lib"
}
else {
    foreign import lib "system:assimp"
}

// Name for default materials (2nd is used if meshes have UV coords)
AI_DEFAULT_MATERIAL_NAME :: "DefaultMaterial"

// ---------------------------------------------------------------------------
/** @brief Defines how the Nth texture of a specific type is combined with
*  the result of all previous layers.
*
*  Example (left: key, right: value): <br>
*  @code
*  DiffColor0     - gray
*  DiffTextureOp0 - aiTextureOpMultiply
*  DiffTexture0   - tex1.png
*  DiffTextureOp0 - aiTextureOpAdd
*  DiffTexture1   - tex2.png
*  @endcode
*  Written as equation, the final diffuse term for a specific pixel would be:
*  @code
*  diffFinal = DiffColor0 * sampleTex(DiffTexture0,UV0) +
*     sampleTex(DiffTexture1,UV0) * diffContrib;
*  @endcode
*  where 'diffContrib' is the intensity of the incoming light for that pixel.
*/
Texture_Op :: enum c.int {
	/** T = T1 * T2 */
	Multiply = 0,

	/** T = T1 + T2 */
	Add = 1,

	/** T = T1 - T2 */
	Subtract = 2,

	/** T = T1 / T2 */
	Divide = 3,

	/** T = (T1 + T2) - (T1 * T2) */
	SmoothAdd = 4,

	/** T = T1 + (T2-0.5) */
	SignedAdd = 5,
}

// ---------------------------------------------------------------------------
/** @brief Defines how UV coordinates outside the [0...1] range are handled.
*
*  Commonly referred to as 'wrapping mode'.
*/
Texture_Map_Mode :: enum c.int {
	/** A texture coordinate u|v is translated to u%1|v%1
	*/
	Wrap = 0,

	/** Texture coordinates outside [0...1]
	*  are clamped to the nearest valid value.
	*/
	Clamp = 1,

	/** If the texture coordinates for a pixel are outside [0...1]
	*  the texture is not applied to that pixel
	*/
	Decal = 3,

	/** A texture coordinate u|v becomes u%1|v%1 if (u-(u%1))%2 is zero and
	*  1-(u%1)|1-(v%1) otherwise
	*/
	Mirror = 2,
}

// ---------------------------------------------------------------------------
/** @brief Defines how the mapping coords for a texture are generated.
*
*  Real-time applications typically require full UV coordinates, so the use of
*  the aiProcess_GenUVCoords step is highly recommended. It generates proper
*  UV channels for non-UV mapped objects, as long as an accurate description
*  how the mapping should look like (e.g spherical) is given.
*  See the #AI_MATKEY_MAPPING property for more details.
*/
Texture_Mapping :: enum c.int {
	/** The mapping coordinates are taken from an UV channel.
	*
	*  #AI_MATKEY_UVWSRC property specifies from which UV channel
	*  the texture coordinates are to be taken from (remember,
	*  meshes can have more than one UV channel).
	*/
	UV = 0,

	/** Spherical mapping */
	SPHERE = 1,

	/** Cylindrical mapping */
	CYLINDER = 2,

	/** Cubic mapping */
	BOX = 3,

	/** Planar mapping */
	PLANE = 4,

	/** Undefined mapping. Have fun. */
	OTHER = 5,
}

// ---------------------------------------------------------------------------
/** @brief Defines the purpose of a texture
*
*  This is a very difficult topic. Different 3D packages support different
*  kinds of textures. For very common texture types, such as bumpmaps, the
*  rendering results depend on implementation details in the rendering
*  pipelines of these applications. Assimp loads all texture references from
*  the model file and tries to determine which of the predefined texture
*  types below is the best choice to match the original use of the texture
*  as closely as possible.<br>
*
*  In content pipelines you'll usually define how textures have to be handled,
*  and the artists working on models have to conform to this specification,
*  regardless which 3D tool they're using.
*/
Texture_Type :: enum c.int {
	/** Dummy value.
	*
	*  No texture, but the value to be used as 'texture semantic'
	*  (#aiMaterialProperty::mSemantic) for all material properties
	*  *not* related to textures.
	*/
	NONE = 0,

	/** The texture is combined with the result of the diffuse
	*  lighting equation.
	*  OR
	*  PBR Specular/Glossiness
	*/
	DIFFUSE = 1,

	/** The texture is combined with the result of the specular
	*  lighting equation.
	*  OR
	*  PBR Specular/Glossiness
	*/
	SPECULAR = 2,

	/** The texture is combined with the result of the ambient
	*  lighting equation.
	*/
	AMBIENT = 3,

	/** The texture is added to the result of the lighting
	*  calculation. It isn't influenced by incoming light.
	*/
	EMISSIVE = 4,

	/** The texture is a height map.
	*
	*  By convention, higher gray-scale values stand for
	*  higher elevations from the base height.
	*/
	HEIGHT = 5,

	/** The texture is a (tangent space) normal-map.
	*
	*  Again, there are several conventions for tangent-space
	*  normal maps. Assimp does (intentionally) not
	*  distinguish here.
	*/
	NORMALS = 6,

	/** The texture defines the glossiness of the material.
	*
	*  The glossiness is in fact the exponent of the specular
	*  (phong) lighting equation. Usually there is a conversion
	*  function defined to map the linear color values in the
	*  texture to a suitable exponent. Have fun.
	*/
	SHININESS = 7,

	/** The texture defines per-pixel opacity.
	*
	*  Usually 'white' means opaque and 'black' means
	*  'transparency'. Or quite the opposite. Have fun.
	*/
	OPACITY = 8,

	/** Displacement texture
	*
	*  The exact purpose and format is application-dependent.
	*  Higher color values stand for higher vertex displacements.
	*/
	DISPLACEMENT = 9,

	/** Lightmap texture (aka Ambient Occlusion)
	*
	*  Both 'Lightmaps' and dedicated 'ambient occlusion maps' are
	*  covered by this material property. The texture contains a
	*  scaling value for the final color value of a pixel. Its
	*  intensity is not affected by incoming light.
	*/
	LIGHTMAP = 10,

	/** Reflection texture
	*
	* Contains the color of a perfect mirror reflection.
	* Rarely used, almost never for real-time applications.
	*/
	REFLECTION = 11,

	/** PBR Materials
	* PBR definitions from maya and other modelling packages now use this standard.
	* This was originally introduced around 2012.
	* Support for this is in game engines like Godot, Unreal or Unity3D.
	* Modelling packages which use this are very common now.
	*/
	BASE_COLOR = 12,

	/** PBR Materials
	* PBR definitions from maya and other modelling packages now use this standard.
	* This was originally introduced around 2012.
	* Support for this is in game engines like Godot, Unreal or Unity3D.
	* Modelling packages which use this are very common now.
	*/
	NORMAL_CAMERA = 13,

	/** PBR Materials
	* PBR definitions from maya and other modelling packages now use this standard.
	* This was originally introduced around 2012.
	* Support for this is in game engines like Godot, Unreal or Unity3D.
	* Modelling packages which use this are very common now.
	*/
	EMISSION_COLOR = 14,

	/** PBR Materials
	* PBR definitions from maya and other modelling packages now use this standard.
	* This was originally introduced around 2012.
	* Support for this is in game engines like Godot, Unreal or Unity3D.
	* Modelling packages which use this are very common now.
	*/
	METALNESS = 15,

	/** PBR Materials
	* PBR definitions from maya and other modelling packages now use this standard.
	* This was originally introduced around 2012.
	* Support for this is in game engines like Godot, Unreal or Unity3D.
	* Modelling packages which use this are very common now.
	*/
	DIFFUSE_ROUGHNESS = 16,

	/** PBR Materials
	* PBR definitions from maya and other modelling packages now use this standard.
	* This was originally introduced around 2012.
	* Support for this is in game engines like Godot, Unreal or Unity3D.
	* Modelling packages which use this are very common now.
	*/
	AMBIENT_OCCLUSION = 17,

	/** Unknown texture
	*
	*  A texture reference that does not match any of the definitions
	*  above is considered to be 'unknown'. It is still imported,
	*  but is excluded from any further post-processing.
	*/
	UNKNOWN = 18,

	/** Sheen
	* Generally used to simulate textiles that are covered in a layer of microfibers
	* eg velvet
	* https://github.com/KhronosGroup/glTF/tree/master/extensions/2.0/Khronos/KHR_materials_sheen
	*/
	SHEEN = 19,

	/** Clearcoat
	* Simulates a layer of 'polish' or 'lacquer' layered on top of a PBR substrate
	* https://autodesk.github.io/standard-surface/#closures/coating
	* https://github.com/KhronosGroup/glTF/tree/master/extensions/2.0/Khronos/KHR_materials_clearcoat
	*/
	CLEARCOAT = 20,

	/** Transmission
	* Simulates transmission through the surface
	* May include further information such as wall thickness
	*/
	TRANSMISSION = 21,

	/**
	* Maya material declarations
	*/
	MAYA_BASE = 22,

	/**
	* Maya material declarations
	*/
	MAYA_SPECULAR = 23,

	/**
	* Maya material declarations
	*/
	MAYA_SPECULAR_COLOR = 24,

	/**
	* Maya material declarations
	*/
	MAYA_SPECULAR_ROUGHNESS = 25,

	/** Anisotropy
	* Simulates a surface with directional properties
	*/
	ANISOTROPY = 26,

	/**
	* gltf material declarations
	* Refs: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#metallic-roughness-material
	*           "textures for metalness and roughness properties are packed together in a single
	*           texture called metallicRoughnessTexture. Its green channel contains roughness
	*           values and its blue channel contains metalness values..."
	*       https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#_material_pbrmetallicroughness_metallicroughnesstexture
	*           "The metalness values are sampled from the B channel. The roughness values are
	*           sampled from the G channel..."
	*/
	GLTF_METALLIC_ROUGHNESS = 27,
}

// AI_TEXTURE_TYPE_MAX :: Texture_Type_Gltf_Metallic_Roughness

// ---------------------------------------------------------------------------
/** @brief Defines all shading models supported by the library
*
*  Property: #AI_MATKEY_SHADING_MODEL
*
*  The list of shading modes has been taken from Blender.
*  See Blender documentation for more information. The API does
*  not distinguish between "specular" and "diffuse" shaders (thus the
*  specular term for diffuse shading models like Oren-Nayar remains
*  undefined). <br>
*  Again, this value is just a hint. Assimp tries to select the shader whose
*  most common implementation matches the original rendering results of the
*  3D modeler which wrote a particular model as closely as possible.
*
*/
Shading_Mode :: enum c.int {
	/** Flat shading. Shading is done on per-face base,
	*  diffuse only. Also known as 'faceted shading'.
	*/
	Flat = 1,

	/** Simple Gouraud shading.
	*/
	Gouraud = 2,

	/** Phong-Shading -
	*/
	Phong = 3,

	/** Phong-Blinn-Shading
	*/
	Blinn = 4,

	/** Toon-Shading per pixel
	*
	*  Also known as 'comic' shader.
	*/
	Toon = 5,

	/** OrenNayar-Shading per pixel
	*
	*  Extension to standard Lambertian shading, taking the
	*  roughness of the material into account
	*/
	OrenNayar = 6,

	/** Minnaert-Shading per pixel
	*
	*  Extension to standard Lambertian shading, taking the
	*  "darkness" of the material into account
	*/
	Minnaert = 7,

	/** CookTorrance-Shading per pixel
	*
	*  Special shader for metallic surfaces.
	*/
	CookTorrance = 8,

	/** No shading at all. Constant light influence of 1.0.
	* Also known as "Unlit"
	*/
	NoShading = 9,
	Unlit        = 9, // Alias

	/** Fresnel shading
	*/
	Fresnel = 10,

	/** Physically-Based Rendering (PBR) shading using
	* Bidirectional scattering/reflectance distribution function (BSDF/BRDF)
	* There are multiple methods under this banner, and model files may provide
	* data for more than one PBR-BRDF method.
	* Applications should use the set of provided properties to determine which
	* of their preferred PBR rendering methods are likely to be available
	* eg:
	* - If AI_MATKEY_METALLIC_FACTOR is set, then a Metallic/Roughness is available
	* - If AI_MATKEY_GLOSSINESS_FACTOR is set, then a Specular/Glossiness is available
	* Note that some PBR methods allow layering of techniques
	*/
	PBR_BRDF = 11,
}

// ---------------------------------------------------------------------------
/**
*  @brief Defines some mixed flags for a particular texture.
*
*  Usually you'll instruct your cg artists how textures have to look like ...
*  and how they will be processed in your application. However, if you use
*  Assimp for completely generic loading purposes you might also need to
*  process these flags in order to display as many 'unknown' 3D models as
*  possible correctly.
*
*  This corresponds to the #AI_MATKEY_TEXFLAGS property.
*/
Texture_Flag :: enum c.int {
	/** The texture's color values have to be inverted (component-wise 1-n)
	*/
	Invert = 0,

	/** Explicit request to the application to process the alpha channel
	*  of the texture.
	*
	*  Mutually exclusive with #aiTextureFlags_IgnoreAlpha. These
	*  flags are set if the library can say for sure that the alpha
	*  channel is used/is not used. If the model format does not
	*  define this, it is left to the application to decide whether
	*  the texture alpha channel - if any - is evaluated or not.
	*/
	UseAlpha = 1,

	/** Explicit request to the application to ignore the alpha channel
	*  of the texture.
	*
	*  Mutually exclusive with #aiTextureFlags_UseAlpha.
	*/
	IgnoreAlpha = 2,
}

Texture_Flags :: distinct bit_set[Texture_Flag; c.int]

// ---------------------------------------------------------------------------
/**
*  @brief Defines alpha-blend flags.
*
*  If you're familiar with OpenGL or D3D, these flags aren't new to you.
*  They define *how* the final color value of a pixel is computed, basing
*  on the previous color at that pixel and the new color value from the
*  material.
*  The blend formula is:
*  @code
*    SourceColor * SourceBlend + DestColor * DestBlend
*  @endcode
*  where DestColor is the previous color in the frame-buffer at this
*  position and SourceColor is the material color before the transparency
*  calculation.<br>
*  This corresponds to the #AI_MATKEY_BLEND_FUNC property.
*/
Blend_Mode :: enum c.int {
	/**
	*  Formula:
	*  @code
	*  SourceColor*SourceAlpha + DestColor*(1-SourceAlpha)
	*  @endcode
	*/
	Default = 0,

	/** Additive blending
	*
	*  Formula:
	*  @code
	*  SourceColor*1 + DestColor*1
	*  @endcode
	*/
	Additive = 1,
}

// ---------------------------------------------------------------------------
/**
*  @brief Defines how an UV channel is transformed.
*
*  This is just a helper structure for the #AI_MATKEY_UVTRANSFORM key.
*  See its documentation for more details.
*
*  Typically you'll want to build a matrix of this information. However,
*  we keep separate scaling/translation/rotation values to make it
*  easier to process and optimize UV transformations internally.
*/
Uvtransform :: struct {
	/** Translation on the u and v axes.
	*
	*  The default value is (0|0).
	*/
	mTranslation: Vector2D,

	/** Scaling on the u and v axes.
	*
	*  The default value is (1|1).
	*/
	mScaling: Vector2D,

	/** Rotation - in counter-clockwise direction.
	*
	*  The rotation angle is specified in radians. The
	*  rotation center is 0.5f|0.5f. The default value
	*  0.f.
	*/
	mRotation: Real,
}

//! @cond AI_DOX_INCLUDE_INTERNAL
// ---------------------------------------------------------------------------
/**
*  @brief A very primitive RTTI system for the contents of material properties.
*/
Property_Type_Info :: enum c.int {
	/** Array of single-precision (32 Bit) floats
	*
	*  It is possible to use aiGetMaterialInteger[Array]() (or the C++-API
	*  aiMaterial::Get()) to query properties stored in floating-point format.
	*  The material system performs the type conversion automatically.
	*/
	Float = 1,

	/** Array of double-precision (64 Bit) floats
	*
	*  It is possible to use aiGetMaterialInteger[Array]() (or the C++-API
	*  aiMaterial::Get()) to query properties stored in floating-point format.
	*  The material system performs the type conversion automatically.
	*/
	Double = 2,

	/** The material property is an aiString.
	*
	*  Arrays of strings aren't possible, aiGetMaterialString() (or the
	*  C++-API aiMaterial::Get()) *must* be used to query a string property.
	*/
	String = 3,

	/** Array of (32 Bit) integers
	*
	*  It is possible to use aiGetMaterialFloat[Array]() (or the C++-API
	*  aiMaterial::Get()) to query properties stored in integer format.
	*  The material system performs the type conversion automatically.
	*/
	Integer = 4,

	/** Simple binary buffer, content undefined. Not convertible to anything.
	*/
	Buffer = 5,
}

// ---------------------------------------------------------------------------
/** @brief Data structure for a single material property
*
*  As an user, you'll probably never need to deal with this data structure.
*  Just use the provided aiGetMaterialXXX() or aiMaterial::Get() family
*  of functions to query material properties easily. Processing them
*  manually is faster, but it is not the recommended way. It isn't worth
*  the effort. <br>
*  Material property names follow a simple scheme:
*  @code
*    $<name>
*    ?<name>
*       A public property, there must be corresponding AI_MATKEY_XXX define
*       2nd: Public, but ignored by the #aiProcess_RemoveRedundantMaterials
*       post-processing step.
*    ~<name>
*       A temporary property for internal use.
*  @endcode
*  @see aiMaterial
*/
Material_Property :: struct {
	/** Specifies the name of the property (key)
	*  Keys are generally case insensitive.
	*/
	mKey: String,

	/** Textures: Specifies their exact usage semantic.
	* For non-texture properties, this member is always 0
	* (or, better-said, #aiTextureType_NONE).
	*/
	mSemantic: c.uint,

	/** Textures: Specifies the index of the texture.
	*  For non-texture properties, this member is always 0.
	*/
	mIndex: c.uint,

	/** Size of the buffer mData is pointing to, in bytes.
	*  This value may not be 0.
	*/
	mDataLength: c.uint,

	/** Type information for the property.
	*
	* Defines the data layout inside the data buffer. This is used
	* by the library internally to perform debug checks and to
	* utilize proper type conversions.
	* (It's probably a hacky solution, but it works.)
	*/
	mType: Property_Type_Info,

	/** Binary buffer to hold the property's value.
	* The size of the buffer is always mDataLength.
	*/
	mData: cstring,
}

Material :: struct {
	/** List of all material properties loaded. */
	mProperties: [^]^Material_Property,

	/** Number of properties in the data base */
	mNumProperties: c.uint,

	/** Storage allocated */
	mNumAllocated: c.uint,
}

// ---------------------------------------------------------------------------
// Pure key names for all texture-related properties
//! @cond MATS_DOC_FULL
AI_MATKEY_TEXTURE_BASE       :: "$tex.file"
AI_MATKEY_UVWSRC_BASE        :: "$tex.uvwsrc"
AI_MATKEY_TEXOP_BASE         :: "$tex.op"
AI_MATKEY_MAPPING_BASE       :: "$tex.mapping"
AI_MATKEY_TEXBLEND_BASE      :: "$tex.blend"
AI_MATKEY_MAPPINGMODE_U_BASE :: "$tex.mapmodeu"
AI_MATKEY_MAPPINGMODE_V_BASE :: "$tex.mapmodev"
AI_MATKEY_TEXMAP_AXIS_BASE   :: "$tex.mapaxis"
AI_MATKEY_UVTRANSFORM_BASE   :: "$tex.uvtrafo"
AI_MATKEY_TEXFLAGS_BASE      :: "$tex.flags"

@(default_calling_convention="c", link_prefix="ai")
foreign lib {
	// -------------------------------------------------------------------------------
	/**
	* @brief  Get a string for a given aiTextureType
	*
	* @param  in  The texture type
	* @return The description string for the texture type.
	*/
	TextureTypeToString :: proc(_in: Texture_Type) -> cstring ---

	//! @endcond
	//!
	// ---------------------------------------------------------------------------
	/** @brief Retrieve a material property with a specific key from the material
	*
	* @param pMat Pointer to the input material. May not be NULL
	* @param pKey Key to search for. One of the AI_MATKEY_XXX constants.
	* @param type Specifies the type of the texture to be retrieved (
	*    e.g. diffuse, specular, height map ...)
	* @param index Index of the texture to be retrieved.
	* @param pPropOut Pointer to receive a pointer to a valid aiMaterialProperty
	*        structure or NULL if the key has not been found. */
	// ---------------------------------------------------------------------------
	GetMaterialProperty :: proc(pMat: ^Material, pKey: cstring, type: c.uint, index: c.uint, pPropOut: ^^Material_Property) -> Return ---

	// ---------------------------------------------------------------------------
	/** @brief Retrieve an array of float values with a specific key
	*  from the material
	*
	* Pass one of the AI_MATKEY_XXX constants for the last three parameters (the
	* example reads the #AI_MATKEY_UVTRANSFORM property of the first diffuse texture)
	* @code
	* aiUVTransform trafo;
	* unsigned int max = sizeof(aiUVTransform);
	* if (AI_SUCCESS != aiGetMaterialFloatArray(mat, AI_MATKEY_UVTRANSFORM(aiTextureType_DIFFUSE,0),
	*    (float*)&trafo, &max) || sizeof(aiUVTransform) != max)
	* {
	*   // error handling
	* }
	* @endcode
	*
	* @param pMat Pointer to the input material. May not be NULL
	* @param pKey Key to search for. One of the AI_MATKEY_XXX constants.
	* @param pOut Pointer to a buffer to receive the result.
	* @param pMax Specifies the size of the given buffer, in float's.
	*        Receives the number of values (not bytes!) read.
	* @param type (see the code sample above)
	* @param index (see the code sample above)
	* @return Specifies whether the key has been found. If not, the output
	*   arrays remains unmodified and pMax is set to 0.*/
	// ---------------------------------------------------------------------------
	GetMaterialFloatArray :: proc(pMat: ^Material, pKey: cstring, type: c.uint, index: c.uint, pOut: ^Real, pMax: ^c.uint) -> Return ---

	// ---------------------------------------------------------------------------
	/** @brief Retrieve a single float property with a specific key from the material.
	*
	* Pass one of the AI_MATKEY_XXX constants for the last three parameters (the
	* example reads the #AI_MATKEY_SHININESS_STRENGTH property of the first diffuse texture)
	* @code
	* float specStrength = 1.f; // default value, remains unmodified if we fail.
	* aiGetMaterialFloat(mat, AI_MATKEY_SHININESS_STRENGTH,
	*    (float*)&specStrength);
	* @endcode
	*
	* @param pMat Pointer to the input material. May not be NULL
	* @param pKey Key to search for. One of the AI_MATKEY_XXX constants.
	* @param pOut Receives the output float.
	* @param type (see the code sample above)
	* @param index (see the code sample above)
	* @return Specifies whether the key has been found. If not, the output
	*   float remains unmodified.*/
	// ---------------------------------------------------------------------------
	GetMaterialFloat :: proc(pMat: ^Material, pKey: cstring, type: c.uint, index: c.uint, pOut: ^Real) -> Return ---

	// ---------------------------------------------------------------------------
	/** @brief Retrieve an array of integer values with a specific key
	*  from a material
	*
	* See the sample for aiGetMaterialFloatArray for more information.*/
	GetMaterialIntegerArray :: proc(pMat: ^Material, pKey: cstring, type: c.uint, index: c.uint, pOut: ^c.int, pMax: ^c.uint) -> Return ---

	// ---------------------------------------------------------------------------
	/** @brief Retrieve an integer property with a specific key from a material
	*
	* See the sample for aiGetMaterialFloat for more information.*/
	// ---------------------------------------------------------------------------
	GetMaterialInteger :: proc(pMat: ^Material, pKey: cstring, type: c.uint, index: c.uint, pOut: ^c.int) -> Return ---

	// ---------------------------------------------------------------------------
	/** @brief Retrieve a color value from the material property table
	*
	* See the sample for aiGetMaterialFloat for more information*/
	// ---------------------------------------------------------------------------
	GetMaterialColor :: proc(pMat: ^Material, pKey: cstring, type: c.uint, index: c.uint, pOut: ^Color4D) -> Return ---

	// ---------------------------------------------------------------------------
	/** @brief Retrieve a aiUVTransform value from the material property table
	*
	* See the sample for aiGetMaterialFloat for more information*/
	// ---------------------------------------------------------------------------
	GetMaterialUVTransform :: proc(pMat: ^Material, pKey: cstring, type: c.uint, index: c.uint, pOut: ^Uvtransform) -> Return ---

	// ---------------------------------------------------------------------------
	/** @brief Retrieve a string from the material property table
	*
	* See the sample for aiGetMaterialFloat for more information.*/
	// ---------------------------------------------------------------------------
	GetMaterialString :: proc(pMat: ^Material, pKey: cstring, type: c.uint, index: c.uint, pOut: ^String) -> Return ---

	// ---------------------------------------------------------------------------
	/** Get the number of textures for a particular texture type.
	*  @param[in] pMat Pointer to the input material. May not be NULL
	*  @param type Texture type to check for
	*  @return Number of textures for this type.
	*  @note A texture can be easily queried using #aiGetMaterialTexture() */
	// ---------------------------------------------------------------------------
	GetMaterialTextureCount :: proc(pMat: ^Material, type: Texture_Type) -> c.uint ---
	GetMaterialTexture      :: proc(mat: ^Material, type: Texture_Type, index: c.uint, path: ^String, mapping: ^Texture_Mapping, uvindex: ^c.uint, blend: ^Real, op: ^Texture_Op, mapmode: ^Texture_Map_Mode, flags: ^c.uint) -> Return ---
}
