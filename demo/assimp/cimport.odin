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
/** @file  cimport.h
*  @brief Defines the C-API to the Open Asset Import Library.
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

// ASSIMP_H_INC :: 

Log_Stream_Callback :: proc "c" (cstring, cstring)

// --------------------------------------------------------------------------------
/** C-API: Represents a log stream. A log stream receives all log messages and
*  streams them _somewhere_.
*  @see aiGetPredefinedLogStream
*  @see aiAttachLogStream
*  @see aiDetachLogStream */
// --------------------------------------------------------------------------------
Log_Stream :: struct {
	/** callback to be called */
	callback: Log_Stream_Callback,

	/** user data to be passed to the callback */
	user: cstring,
}

// --------------------------------------------------------------------------------
/** C-API: Represents an opaque set of settings to be used during importing.
*  @see aiCreatePropertyStore
*  @see aiReleasePropertyStore
*  @see aiImportFileExWithProperties
*  @see aiSetPropertyInteger
*  @see aiSetPropertyFloat
*  @see aiSetPropertyString
*  @see aiSetPropertyMatrix
*/
// --------------------------------------------------------------------------------
Property_Store :: struct {
	sentinel: c.char,
}

/** Our own C boolean type */
Bool :: c.int

FALSE :: 0
TRUE :: 1

@(default_calling_convention="c", link_prefix="ai")
foreign lib {
	// --------------------------------------------------------------------------------
	/** Reads the given file and returns its content.
	*
	* If the call succeeds, the imported data is returned in an aiScene structure.
	* The data is intended to be read-only, it stays property of the ASSIMP
	* library and will be stable until aiReleaseImport() is called. After you're
	* done with it, call aiReleaseImport() to free the resources associated with
	* this file. If the import fails, NULL is returned instead. Call
	* aiGetErrorString() to retrieve a human-readable error text.
	* @param pFile Path and filename of the file to be imported,
	*   expected to be a null-terminated c-string. NULL is not a valid value.
	* @param pFlags Optional post processing steps to be executed after
	*   a successful import. Provide a bitwise combination of the
	*   #aiPostProcessSteps flags.
	* @return Pointer to the imported data or NULL if the import failed.
	*/
	ImportFile :: proc(pFile: cstring, pFlags: Post_Process_Step_Flags) -> ^Scene ---

	// --------------------------------------------------------------------------------
	/** Reads the given file using user-defined I/O functions and returns
	*   its content.
	*
	* If the call succeeds, the imported data is returned in an aiScene structure.
	* The data is intended to be read-only, it stays property of the ASSIMP
	* library and will be stable until aiReleaseImport() is called. After you're
	* done with it, call aiReleaseImport() to free the resources associated with
	* this file. If the import fails, NULL is returned instead. Call
	* aiGetErrorString() to retrieve a human-readable error text.
	* @param pFile Path and filename of the file to be imported,
	*   expected to be a null-terminated c-string. NULL is not a valid value.
	* @param pFlags Optional post processing steps to be executed after
	*   a successful import. Provide a bitwise combination of the
	*   #aiPostProcessSteps flags.
	* @param pFS aiFileIO structure. Will be used to open the model file itself
	*   and any other files the loader needs to open.  Pass NULL to use the default
	*   implementation.
	* @return Pointer to the imported data or NULL if the import failed.
	* @note Include <aiFileIO.h> for the definition of #aiFileIO.
	*/
	ImportFileEx :: proc(pFile: cstring, pFlags: Post_Process_Step_Flags, pFS: ^File_Io) -> ^Scene ---

	// --------------------------------------------------------------------------------
	/** Same as #aiImportFileEx, but adds an extra parameter containing importer settings.
	*
	* @param pFile Path and filename of the file to be imported,
	*   expected to be a null-terminated c-string. NULL is not a valid value.
	* @param pFlags Optional post processing steps to be executed after
	*   a successful import. Provide a bitwise combination of the
	*   #aiPostProcessSteps flags.
	* @param pFS aiFileIO structure. Will be used to open the model file itself
	*   and any other files the loader needs to open.  Pass NULL to use the default
	*   implementation.
	* @param pProps #aiPropertyStore instance containing import settings.
	* @return Pointer to the imported data or NULL if the import failed.
	* @note Include <aiFileIO.h> for the definition of #aiFileIO.
	* @see aiImportFileEx
	*/
	ImportFileExWithProperties :: proc(pFile: cstring, pFlags: Post_Process_Step_Flags, pFS: ^File_Io, pProps: ^Property_Store) -> ^Scene ---

	// --------------------------------------------------------------------------------
	/** Reads the given file from a given memory buffer,
	*
	* If the call succeeds, the imported data is returned in an aiScene structure.
	* The data is intended to be read-only, it stays property of the ASSIMP
	* library and will be stable until aiReleaseImport() is called. After you're
	* done with it, call aiReleaseImport() to free the resources associated with
	* this file. If the import fails, NULL is returned.
	* A human-readable error description can be retrieved by calling aiGetErrorString().
	* @param pBuffer Pointer to the file data
	* @param pLength Length of pBuffer, in bytes
	* @param pFlags Optional post processing steps to be executed after
	*   a successful import. Provide a bitwise combination of the
	*   #aiPostProcessSteps flags. If you wish to inspect the imported
	*   scene first in order to fine-tune your post-processing setup,
	*   consider to use #aiApplyPostProcessing().
	* @param pHint An additional hint to the library. If this is a non empty string,
	*   the library looks for a loader to support the file extension specified by pHint
	*   and passes the file to the first matching loader. If this loader is unable to
	*   completely the request, the library continues and tries to determine the file
	*   format on its own, a task that may or may not be successful.
	*   Check the return value, and you'll know ...
	* @return A pointer to the imported data, NULL if the import failed.
	*
	* @note This is a straightforward way to decode models from memory
	* buffers, but it doesn't handle model formats that spread their
	* data across multiple files or even directories. Examples include
	* OBJ or MD3, which outsource parts of their material info into
	* external scripts. If you need full functionality, provide
	* a custom IOSystem to make Assimp find these files and use
	* the regular aiImportFileEx()/aiImportFileExWithProperties() API.
	*/
	ImportFileFromMemory :: proc(pBuffer: cstring, pLength: c.uint, pFlags: Post_Process_Step_Flags, pHint: cstring) -> ^Scene ---

	// --------------------------------------------------------------------------------
	/** Same as #aiImportFileFromMemory, but adds an extra parameter containing importer settings.
	*
	* @param pBuffer Pointer to the file data
	* @param pLength Length of pBuffer, in bytes
	* @param pFlags Optional post processing steps to be executed after
	*   a successful import. Provide a bitwise combination of the
	*   #aiPostProcessSteps flags. If you wish to inspect the imported
	*   scene first in order to fine-tune your post-processing setup,
	*   consider to use #aiApplyPostProcessing().
	* @param pHint An additional hint to the library. If this is a non empty string,
	*   the library looks for a loader to support the file extension specified by pHint
	*   and passes the file to the first matching loader. If this loader is unable to
	*   completely the request, the library continues and tries to determine the file
	*   format on its own, a task that may or may not be successful.
	*   Check the return value, and you'll know ...
	* @param pProps #aiPropertyStore instance containing import settings.
	* @return A pointer to the imported data, NULL if the import failed.
	*
	* @note This is a straightforward way to decode models from memory
	* buffers, but it doesn't handle model formats that spread their
	* data across multiple files or even directories. Examples include
	* OBJ or MD3, which outsource parts of their material info into
	* external scripts. If you need full functionality, provide
	* a custom IOSystem to make Assimp find these files and use
	* the regular aiImportFileEx()/aiImportFileExWithProperties() API.
	* @see aiImportFileFromMemory
	*/
	ImportFileFromMemoryWithProperties :: proc(pBuffer: cstring, pLength: c.uint, pFlags: Post_Process_Step_Flags, pHint: cstring, pProps: ^Property_Store) -> ^Scene ---

	// --------------------------------------------------------------------------------
	/** Apply post-processing to an already-imported scene.
	*
	* This is strictly equivalent to calling #aiImportFile()/#aiImportFileEx with the
	* same flags. However, you can use this separate function to inspect the imported
	* scene first to fine-tune your post-processing setup.
	* @param pScene Scene to work on.
	* @param pFlags Provide a bitwise combination of the #aiPostProcessSteps flags.
	* @return A pointer to the post-processed data. Post processing is done in-place,
	*   meaning this is still the same #aiScene which you passed for pScene. However,
	*   _if_ post-processing failed, the scene could now be NULL. That's quite a rare
	*   case, post processing steps are not really designed to 'fail'. To be exact,
	*   the #aiProcess_ValidateDataStructure flag is currently the only post processing step
	*   which can actually cause the scene to be reset to NULL.
	*/
	ApplyPostProcessing :: proc(pScene: ^Scene, pFlags: Post_Process_Step_Flags) -> ^Scene ---

	// --------------------------------------------------------------------------------
	/** Get one of the predefine log streams. This is the quick'n'easy solution to
	*  access Assimp's log system. Attaching a log stream can slightly reduce Assimp's
	*  overall import performance.
	*
	*  Usage is rather simple (this will stream the log to a file, named log.txt, and
	*  the stdout stream of the process:
	*  @code
	*    struct aiLogStream c;
	*    c = aiGetPredefinedLogStream(aiDefaultLogStream_FILE,"log.txt");
	*    aiAttachLogStream(&c);
	*    c = aiGetPredefinedLogStream(aiDefaultLogStream_STDOUT,NULL);
	*    aiAttachLogStream(&c);
	*  @endcode
	*
	*  @param pStreams One of the #aiDefaultLogStream enumerated values.
	*  @param file Solely for the #aiDefaultLogStream_FILE flag: specifies the file to write to.
	*    Pass NULL for all other flags.
	*  @return The log stream. callback is set to NULL if something went wrong.
	*/
	GetPredefinedLogStream :: proc(pStreams: Default_Log_Stream_Flag, file: cstring) -> Log_Stream ---

	// --------------------------------------------------------------------------------
	/** Attach a custom log stream to the libraries' logging system.
	*
	*  Attaching a log stream can slightly reduce Assimp's overall import
	*  performance. Multiple log-streams can be attached.
	*  @param stream Describes the new log stream.
	*  @note To ensure proper destruction of the logging system, you need to manually
	*    call aiDetachLogStream() on every single log stream you attach.
	*    Alternatively (for the lazy folks) #aiDetachAllLogStreams is provided.
	*/
	AttachLogStream :: proc(stream: ^Log_Stream) ---

	// --------------------------------------------------------------------------------
	/** Enable verbose logging. Verbose logging includes debug-related stuff and
	*  detailed import statistics. This can have severe impact on import performance
	*  and memory consumption. However, it might be useful to find out why a file
	*  didn't read correctly.
	*  @param d AI_TRUE or AI_FALSE, your decision.
	*/
	EnableVerboseLogging :: proc(d: Bool) ---

	// --------------------------------------------------------------------------------
	/** Detach a custom log stream from the libraries' logging system.
	*
	*  This is the counterpart of #aiAttachLogStream. If you attached a stream,
	*  don't forget to detach it again.
	*  @param stream The log stream to be detached.
	*  @return AI_SUCCESS if the log stream has been detached successfully.
	*  @see aiDetachAllLogStreams
	*/
	DetachLogStream :: proc(stream: ^Log_Stream) -> Return ---

	// --------------------------------------------------------------------------------
	/** Detach all active log streams from the libraries' logging system.
	*  This ensures that the logging system is terminated properly and all
	*  resources allocated by it are actually freed. If you attached a stream,
	*  don't forget to detach it again.
	*  @see aiAttachLogStream
	*  @see aiDetachLogStream
	*/
	DetachAllLogStreams :: proc() ---

	// --------------------------------------------------------------------------------
	/** Releases all resources associated with the given import process.
	*
	* Call this function after you're done with the imported data.
	* @param pScene The imported data to release. NULL is a valid value.
	*/
	ReleaseImport :: proc(pScene: ^Scene) ---

	// --------------------------------------------------------------------------------
	/** Returns the error text of the last failed import process.
	*
	* @return A textual description of the error that occurred at the last
	* import process. NULL if there was no error. There can't be an error if you
	* got a non-NULL #aiScene from #aiImportFile/#aiImportFileEx/#aiApplyPostProcessing.
	*/
	GetErrorString :: proc() -> cstring ---

	// --------------------------------------------------------------------------------
	/** Returns whether a given file extension is supported by ASSIMP
	*
	* @param szExtension Extension for which the function queries support for.
	* Must include a leading dot '.'. Example: ".3ds", ".md3"
	* @return AI_TRUE if the file extension is supported.
	*/
	IsExtensionSupported :: proc(szExtension: cstring) -> Bool ---

	// --------------------------------------------------------------------------------
	/** Get a list of all file extensions supported by ASSIMP.
	*
	* If a file extension is contained in the list this does, of course, not
	* mean that ASSIMP is able to load all files with this extension.
	* @param szOut String to receive the extension list.
	* Format of the list: "*.3ds;*.obj;*.dae". NULL is not a valid parameter.
	*/
	GetExtensionList :: proc(szOut: ^String) ---

	// --------------------------------------------------------------------------------
	/** Get the approximated storage required by an imported asset
	* @param pIn Input asset.
	* @param in Data structure to be filled.
	*/
	GetMemoryRequirements :: proc(pIn: ^Scene, _in: ^Memory_Info) ---

	// --------------------------------------------------------------------------------
	/** Returns an embedded texture, or nullptr.
	* @param pIn Input asset.
	* @param filename Texture path extracted from aiGetMaterialString.
	*/
	GetEmbeddedTexture :: proc(pIn: ^Scene, filename: cstring) -> ^Texture ---

	// --------------------------------------------------------------------------------
	/** Create an empty property store. Property stores are used to collect import
	*  settings.
	* @return New property store. Property stores need to be manually destroyed using
	*   the #aiReleasePropertyStore API function.
	*/
	CreatePropertyStore :: proc() -> ^Property_Store ---

	// --------------------------------------------------------------------------------
	/** Delete a property store.
	* @param p Property store to be deleted.
	*/
	ReleasePropertyStore :: proc(p: ^Property_Store) ---

	// --------------------------------------------------------------------------------
	/** Set an integer property.
	*
	*  This is the C-version of #Assimp::Importer::SetPropertyInteger(). In the C
	*  interface, properties are always shared by all imports. It is not possible to
	*  specify them per import.
	*
	* @param store Store to modify. Use #aiCreatePropertyStore to obtain a store.
	* @param szName Name of the configuration property to be set. All supported
	*   public properties are defined in the config.h header file (AI_CONFIG_XXX).
	* @param value New value for the property
	*/
	SetImportPropertyInteger :: proc(store: ^Property_Store, szName: cstring, value: c.int) ---

	// --------------------------------------------------------------------------------
	/** Set a floating-point property.
	*
	*  This is the C-version of #Assimp::Importer::SetPropertyFloat(). In the C
	*  interface, properties are always shared by all imports. It is not possible to
	*  specify them per import.
	*
	* @param store Store to modify. Use #aiCreatePropertyStore to obtain a store.
	* @param szName Name of the configuration property to be set. All supported
	*   public properties are defined in the config.h header file (AI_CONFIG_XXX).
	* @param value New value for the property
	*/
	SetImportPropertyFloat :: proc(store: ^Property_Store, szName: cstring, value: Real) ---

	// --------------------------------------------------------------------------------
	/** Set a string property.
	*
	*  This is the C-version of #Assimp::Importer::SetPropertyString(). In the C
	*  interface, properties are always shared by all imports. It is not possible to
	*  specify them per import.
	*
	* @param store Store to modify. Use #aiCreatePropertyStore to obtain a store.
	* @param szName Name of the configuration property to be set. All supported
	*   public properties are defined in the config.h header file (AI_CONFIG_XXX).
	* @param st New value for the property
	*/
	SetImportPropertyString :: proc(store: ^Property_Store, szName: cstring, st: ^String) ---

	// --------------------------------------------------------------------------------
	/** Set a matrix property.
	*
	*  This is the C-version of #Assimp::Importer::SetPropertyMatrix(). In the C
	*  interface, properties are always shared by all imports. It is not possible to
	*  specify them per import.
	*
	* @param store Store to modify. Use #aiCreatePropertyStore to obtain a store.
	* @param szName Name of the configuration property to be set. All supported
	*   public properties are defined in the config.h header file (AI_CONFIG_XXX).
	* @param mat New value for the property
	*/
	SetImportPropertyMatrix :: proc(store: ^Property_Store, szName: cstring, mat: ^Matrix4x4) ---

	// --------------------------------------------------------------------------------
	/** Construct a quaternion from a 3x3 rotation matrix.
	*  @param quat Receives the output quaternion.
	*  @param mat Matrix to 'quaternionize'.
	*  @see aiQuaternion(const aiMatrix3x3& pRotMatrix)
	*/
	CreateQuaternionFromMatrix :: proc(quat: ^Quaternion, mat: ^Matrix3x3) ---

	// --------------------------------------------------------------------------------
	/** Decompose a transformation matrix into its rotational, translational and
	*  scaling components.
	*
	* @param mat Matrix to decompose
	* @param scaling Receives the scaling component
	* @param rotation Receives the rotational component
	* @param position Receives the translational component.
	* @see aiMatrix4x4::Decompose (aiVector3D&, aiQuaternion&, aiVector3D&) const;
	*/
	DecomposeMatrix :: proc(mat: ^Matrix4x4, scaling: ^Vector3D, rotation: ^Quaternion, position: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Transpose a 4x4 matrix.
	*  @param mat Pointer to the matrix to be transposed
	*/
	TransposeMatrix4 :: proc(mat: ^Matrix4x4) ---

	// --------------------------------------------------------------------------------
	/** Transpose a 3x3 matrix.
	*  @param mat Pointer to the matrix to be transposed
	*/
	TransposeMatrix3 :: proc(mat: ^Matrix3x3) ---

	// --------------------------------------------------------------------------------
	/** Transform a vector by a 3x3 matrix
	*  @param vec Vector to be transformed.
	*  @param mat Matrix to transform the vector with.
	*/
	TransformVecByMatrix3 :: proc(vec: ^Vector3D, mat: ^Matrix3x3) ---

	// --------------------------------------------------------------------------------
	/** Transform a vector by a 4x4 matrix
	*  @param vec Vector to be transformed.
	*  @param mat Matrix to transform the vector with.
	*/
	TransformVecByMatrix4 :: proc(vec: ^Vector3D, mat: ^Matrix4x4) ---

	// --------------------------------------------------------------------------------
	/** Multiply two 4x4 matrices.
	*  @param dst First factor, receives result.
	*  @param src Matrix to be multiplied with 'dst'.
	*/
	MultiplyMatrix4 :: proc(dst: ^Matrix4x4, src: ^Matrix4x4) ---

	// --------------------------------------------------------------------------------
	/** Multiply two 3x3 matrices.
	*  @param dst First factor, receives result.
	*  @param src Matrix to be multiplied with 'dst'.
	*/
	MultiplyMatrix3 :: proc(dst: ^Matrix3x3, src: ^Matrix3x3) ---

	// --------------------------------------------------------------------------------
	/** Get a 3x3 identity matrix.
	*  @param mat Matrix to receive its personal identity
	*/
	IdentityMatrix3 :: proc(mat: ^Matrix3x3) ---

	// --------------------------------------------------------------------------------
	/** Get a 4x4 identity matrix.
	*  @param mat Matrix to receive its personal identity
	*/
	IdentityMatrix4 :: proc(mat: ^Matrix4x4) ---

	// --------------------------------------------------------------------------------
	/** Returns the number of import file formats available in the current Assimp build.
	* Use aiGetImportFormatDescription() to retrieve infos of a specific import format.
	*/
	GetImportFormatCount :: proc() -> c.size_t ---

	// --------------------------------------------------------------------------------
	/** Returns a description of the nth import file format. Use #aiGetImportFormatCount()
	* to learn how many import formats are supported.
	* @param pIndex Index of the import format to retrieve information for. Valid range is
	*    0 to #aiGetImportFormatCount()
	* @return A description of that specific import format. NULL if pIndex is out of range.
	*/
	GetImportFormatDescription :: proc(pIndex: c.size_t) -> ^Importer_Desc ---

	// --------------------------------------------------------------------------------
	/** Check if 2D vectors are equal.
	*  @param a First vector to compare
	*  @param b Second vector to compare
	*  @return 1 if the vectors are equal
	*  @return 0 if the vectors are not equal
	*/
	Vector2AreEqual :: proc(a: ^Vector2D, b: ^Vector2D) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Check if 2D vectors are equal using epsilon.
	*  @param a First vector to compare
	*  @param b Second vector to compare
	*  @param epsilon Epsilon
	*  @return 1 if the vectors are equal
	*  @return 0 if the vectors are not equal
	*/
	Vector2AreEqualEpsilon :: proc(a: ^Vector2D, b: ^Vector2D, epsilon: f32) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Add 2D vectors.
	*  @param dst First addend, receives result.
	*  @param src Vector to be added to 'dst'.
	*/
	Vector2Add :: proc(dst: ^Vector2D, src: ^Vector2D) ---

	// --------------------------------------------------------------------------------
	/** Subtract 2D vectors.
	*  @param dst Minuend, receives result.
	*  @param src Vector to be subtracted from 'dst'.
	*/
	Vector2Subtract :: proc(dst: ^Vector2D, src: ^Vector2D) ---

	// --------------------------------------------------------------------------------
	/** Multiply a 2D vector by a scalar.
	*  @param dst Vector to be scaled by \p s
	*  @param s Scale factor
	*/
	Vector2Scale :: proc(dst: ^Vector2D, s: f32) ---

	// --------------------------------------------------------------------------------
	/** Multiply each component of a 2D vector with
	*  the components of another vector.
	*  @param dst First vector, receives result
	*  @param other Second vector
	*/
	Vector2SymMul :: proc(dst: ^Vector2D, other: ^Vector2D) ---

	// --------------------------------------------------------------------------------
	/** Divide a 2D vector by a scalar.
	*  @param dst Vector to be divided by \p s
	*  @param s Scalar divisor
	*/
	Vector2DivideByScalar :: proc(dst: ^Vector2D, s: f32) ---

	// --------------------------------------------------------------------------------
	/** Divide each component of a 2D vector by
	*  the components of another vector.
	*  @param dst Vector as the dividend
	*  @param v Vector as the divisor
	*/
	Vector2DivideByVector :: proc(dst: ^Vector2D, v: ^Vector2D) ---

	// --------------------------------------------------------------------------------
	/** Get the length of a 2D vector.
	*  @return v Vector to evaluate
	*/
	Vector2Length :: proc(v: ^Vector2D) -> Real ---

	// --------------------------------------------------------------------------------
	/** Get the squared length of a 2D vector.
	*  @return v Vector to evaluate
	*/
	Vector2SquareLength :: proc(v: ^Vector2D) -> Real ---

	// --------------------------------------------------------------------------------
	/** Negate a 2D vector.
	*  @param dst Vector to be negated
	*/
	Vector2Negate :: proc(dst: ^Vector2D) ---

	// --------------------------------------------------------------------------------
	/** Get the dot product of 2D vectors.
	*  @param a First vector
	*  @param b Second vector
	*  @return The dot product of vectors
	*/
	Vector2DotProduct :: proc(a: ^Vector2D, b: ^Vector2D) -> Real ---

	// --------------------------------------------------------------------------------
	/** Normalize a 2D vector.
	*  @param v Vector to normalize
	*/
	Vector2Normalize :: proc(v: ^Vector2D) ---

	// --------------------------------------------------------------------------------
	/** Check if 3D vectors are equal.
	*  @param a First vector to compare
	*  @param b Second vector to compare
	*  @return 1 if the vectors are equal
	*  @return 0 if the vectors are not equal
	*/
	Vector3AreEqual :: proc(a: ^Vector3D, b: ^Vector3D) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Check if 3D vectors are equal using epsilon.
	*  @param a First vector to compare
	*  @param b Second vector to compare
	*  @param epsilon Epsilon
	*  @return 1 if the vectors are equal
	*  @return 0 if the vectors are not equal
	*/
	Vector3AreEqualEpsilon :: proc(a: ^Vector3D, b: ^Vector3D, epsilon: f32) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Check if vector \p a is less than vector \p b.
	*  @param a First vector to compare
	*  @param b Second vector to compare
	*  @param epsilon Epsilon
	*  @return 1 if \p a is less than \p b
	*  @return 0 if \p a is equal or greater than \p b
	*/
	Vector3LessThan :: proc(a: ^Vector3D, b: ^Vector3D) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Add 3D vectors.
	*  @param dst First addend, receives result.
	*  @param src Vector to be added to 'dst'.
	*/
	Vector3Add :: proc(dst: ^Vector3D, src: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Subtract 3D vectors.
	*  @param dst Minuend, receives result.
	*  @param src Vector to be subtracted from 'dst'.
	*/
	Vector3Subtract :: proc(dst: ^Vector3D, src: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Multiply a 3D vector by a scalar.
	*  @param dst Vector to be scaled by \p s
	*  @param s Scale factor
	*/
	Vector3Scale :: proc(dst: ^Vector3D, s: f32) ---

	// --------------------------------------------------------------------------------
	/** Multiply each component of a 3D vector with
	*  the components of another vector.
	*  @param dst First vector, receives result
	*  @param other Second vector
	*/
	Vector3SymMul :: proc(dst: ^Vector3D, other: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Divide a 3D vector by a scalar.
	*  @param dst Vector to be divided by \p s
	*  @param s Scalar divisor
	*/
	Vector3DivideByScalar :: proc(dst: ^Vector3D, s: f32) ---

	// --------------------------------------------------------------------------------
	/** Divide each component of a 3D vector by
	*  the components of another vector.
	*  @param dst Vector as the dividend
	*  @param v Vector as the divisor
	*/
	Vector3DivideByVector :: proc(dst: ^Vector3D, v: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Get the length of a 3D vector.
	*  @return v Vector to evaluate
	*/
	Vector3Length :: proc(v: ^Vector3D) -> Real ---

	// --------------------------------------------------------------------------------
	/** Get the squared length of a 3D vector.
	*  @return v Vector to evaluate
	*/
	Vector3SquareLength :: proc(v: ^Vector3D) -> Real ---

	// --------------------------------------------------------------------------------
	/** Negate a 3D vector.
	*  @param dst Vector to be negated
	*/
	Vector3Negate :: proc(dst: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Get the dot product of 3D vectors.
	*  @param a First vector
	*  @param b Second vector
	*  @return The dot product of vectors
	*/
	Vector3DotProduct :: proc(a: ^Vector3D, b: ^Vector3D) -> Real ---

	// --------------------------------------------------------------------------------
	/** Get cross product of 3D vectors.
	*  @param dst Vector to receive the result.
	*  @param a First vector
	*  @param b Second vector
	*  @return The dot product of vectors
	*/
	Vector3CrossProduct :: proc(dst: ^Vector3D, a: ^Vector3D, b: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Normalize a 3D vector.
	*  @param v Vector to normalize
	*/
	Vector3Normalize :: proc(v: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Check for division by zero and normalize a 3D vector.
	*  @param v Vector to normalize
	*/
	Vector3NormalizeSafe :: proc(v: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Rotate a 3D vector by a quaternion.
	*  @param v The vector to rotate by \p q
	*  @param q Quaternion to use to rotate \p v
	*/
	Vector3RotateByQuaternion :: proc(v: ^Vector3D, q: ^Quaternion) ---

	// --------------------------------------------------------------------------------
	/** Construct a 3x3 matrix from a 4x4 matrix.
	*  @param dst Receives the output matrix
	*  @param mat The 4x4 matrix to use
	*/
	Matrix3FromMatrix4 :: proc(dst: ^Matrix3x3, mat: ^Matrix4x4) ---

	// --------------------------------------------------------------------------------
	/** Construct a 3x3 matrix from a quaternion.
	*  @param mat Receives the output matrix
	*  @param q The quaternion matrix to use
	*/
	Matrix3FromQuaternion :: proc(mat: ^Matrix3x3, q: ^Quaternion) ---

	// --------------------------------------------------------------------------------
	/** Check if 3x3 matrices are equal.
	*  @param a First matrix to compare
	*  @param b Second matrix to compare
	*  @return 1 if the matrices are equal
	*  @return 0 if the matrices are not equal
	*/
	Matrix3AreEqual :: proc(a: ^Matrix3x3, b: ^Matrix3x3) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Check if 3x3 matrices are equal.
	*  @param a First matrix to compare
	*  @param b Second matrix to compare
	*  @param epsilon Epsilon
	*  @return 1 if the matrices are equal
	*  @return 0 if the matrices are not equal
	*/
	Matrix3AreEqualEpsilon :: proc(a: ^Matrix3x3, b: ^Matrix3x3, epsilon: f32) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Invert a 3x3 matrix.
	*  @param mat Matrix to invert
	*/
	Matrix3Inverse :: proc(mat: ^Matrix3x3) ---

	// --------------------------------------------------------------------------------
	/** Get the determinant of a 3x3 matrix.
	*  @param mat Matrix to get the determinant from
	*/
	Matrix3Determinant :: proc(mat: ^Matrix3x3) -> Real ---

	// --------------------------------------------------------------------------------
	/** Get a 3x3 rotation matrix around the Z axis.
	*  @param mat Receives the output matrix
	*  @param angle Rotation angle, in radians
	*/
	Matrix3RotationZ :: proc(mat: ^Matrix3x3, angle: f32) ---

	// --------------------------------------------------------------------------------
	/** Returns a 3x3 rotation matrix for a rotation around an arbitrary axis.
	*  @param mat Receives the output matrix
	*  @param axis Rotation axis, should be a normalized vector
	*  @param angle Rotation angle, in radians
	*/
	Matrix3FromRotationAroundAxis :: proc(mat: ^Matrix3x3, axis: ^Vector3D, angle: f32) ---

	// --------------------------------------------------------------------------------
	/** Get a 3x3 translation matrix.
	*  @param mat Receives the output matrix
	*  @param translation The translation vector
	*/
	Matrix3Translation :: proc(mat: ^Matrix3x3, translation: ^Vector2D) ---

	// --------------------------------------------------------------------------------
	/** Create a 3x3 matrix that rotates one vector to another vector.
	*  @param mat Receives the output matrix
	*  @param from Vector to rotate from
	*  @param to Vector to rotate to
	*/
	Matrix3FromTo :: proc(mat: ^Matrix3x3, from: ^Vector3D, to: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Construct a 4x4 matrix from a 3x3 matrix.
	*  @param dst Receives the output matrix
	*  @param mat The 3x3 matrix to use
	*/
	Matrix4FromMatrix3 :: proc(dst: ^Matrix4x4, mat: ^Matrix3x3) ---

	// --------------------------------------------------------------------------------
	/** Construct a 4x4 matrix from scaling, rotation and position.
	*  @param mat Receives the output matrix.
	*  @param scaling The scaling for the x,y,z axes
	*  @param rotation The rotation as a hamilton quaternion
	*  @param position The position for the x,y,z axes
	*/
	Matrix4FromScalingQuaternionPosition :: proc(mat: ^Matrix4x4, scaling: ^Vector3D, rotation: ^Quaternion, position: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Add 4x4 matrices.
	*  @param dst First addend, receives result.
	*  @param src Matrix to be added to 'dst'.
	*/
	Matrix4Add :: proc(dst: ^Matrix4x4, src: ^Matrix4x4) ---

	// --------------------------------------------------------------------------------
	/** Check if 4x4 matrices are equal.
	*  @param a First matrix to compare
	*  @param b Second matrix to compare
	*  @return 1 if the matrices are equal
	*  @return 0 if the matrices are not equal
	*/
	Matrix4AreEqual :: proc(a: ^Matrix4x4, b: ^Matrix4x4) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Check if 4x4 matrices are equal.
	*  @param a First matrix to compare
	*  @param b Second matrix to compare
	*  @param epsilon Epsilon
	*  @return 1 if the matrices are equal
	*  @return 0 if the matrices are not equal
	*/
	Matrix4AreEqualEpsilon :: proc(a: ^Matrix4x4, b: ^Matrix4x4, epsilon: f32) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Invert a 4x4 matrix.
	*  @param result Matrix to invert
	*/
	Matrix4Inverse :: proc(mat: ^Matrix4x4) ---

	// --------------------------------------------------------------------------------
	/** Get the determinant of a 4x4 matrix.
	*  @param mat Matrix to get the determinant from
	*  @return The determinant of the matrix
	*/
	Matrix4Determinant :: proc(mat: ^Matrix4x4) -> Real ---

	// --------------------------------------------------------------------------------
	/** Returns true of the matrix is the identity matrix.
	*  @param mat Matrix to get the determinant from
	*  @return 1 if \p mat is an identity matrix.
	*  @return 0 if \p mat is not an identity matrix.
	*/
	Matrix4IsIdentity :: proc(mat: ^Matrix4x4) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Decompose a transformation matrix into its scaling,
	*  rotational as euler angles, and translational components.
	*
	* @param mat Matrix to decompose
	* @param scaling Receives the output scaling for the x,y,z axes
	* @param rotation Receives the output rotation as a Euler angles
	* @param position Receives the output position for the x,y,z axes
	*/
	Matrix4DecomposeIntoScalingEulerAnglesPosition :: proc(mat: ^Matrix4x4, scaling: ^Vector3D, rotation: ^Vector3D, position: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Decompose a transformation matrix into its scaling,
	*  rotational split into an axis and rotational angle,
	*  and it's translational components.
	*
	* @param mat Matrix to decompose
	* @param rotation Receives the rotational component
	* @param axis Receives the output rotation axis
	* @param angle Receives the output rotation angle
	* @param position Receives the output position for the x,y,z axes.
	*/
	Matrix4DecomposeIntoScalingAxisAnglePosition :: proc(mat: ^Matrix4x4, scaling: ^Vector3D, axis: ^Vector3D, angle: ^Real, position: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Decompose a transformation matrix into its rotational and
	*  translational components.
	*
	* @param mat Matrix to decompose
	* @param rotation Receives the rotational component
	* @param position Receives the translational component.
	*/
	Matrix4DecomposeNoScaling :: proc(mat: ^Matrix4x4, rotation: ^Quaternion, position: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Creates a 4x4 matrix from a set of euler angles.
	*  @param mat Receives the output matrix
	*  @param x Rotation angle for the x-axis, in radians
	*  @param y Rotation angle for the y-axis, in radians
	*  @param z Rotation angle for the z-axis, in radians
	*/
	Matrix4FromEulerAngles :: proc(mat: ^Matrix4x4, x: f32, y: f32, z: f32) ---

	// --------------------------------------------------------------------------------
	/** Get a 4x4 rotation matrix around the X axis.
	*  @param mat Receives the output matrix
	*  @param angle Rotation angle, in radians
	*/
	Matrix4RotationX :: proc(mat: ^Matrix4x4, angle: f32) ---

	// --------------------------------------------------------------------------------
	/** Get a 4x4 rotation matrix around the Y axis.
	*  @param mat Receives the output matrix
	*  @param angle Rotation angle, in radians
	*/
	Matrix4RotationY :: proc(mat: ^Matrix4x4, angle: f32) ---

	// --------------------------------------------------------------------------------
	/** Get a 4x4 rotation matrix around the Z axis.
	*  @param mat Receives the output matrix
	*  @param angle Rotation angle, in radians
	*/
	Matrix4RotationZ :: proc(mat: ^Matrix4x4, angle: f32) ---

	// --------------------------------------------------------------------------------
	/** Returns a 4x4 rotation matrix for a rotation around an arbitrary axis.
	*  @param mat Receives the output matrix
	*  @param axis Rotation axis, should be a normalized vector
	*  @param angle Rotation angle, in radians
	*/
	Matrix4FromRotationAroundAxis :: proc(mat: ^Matrix4x4, axis: ^Vector3D, angle: f32) ---

	// --------------------------------------------------------------------------------
	/** Get a 4x4 translation matrix.
	*  @param mat Receives the output matrix
	*  @param translation The translation vector
	*/
	Matrix4Translation :: proc(mat: ^Matrix4x4, translation: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Get a 4x4 scaling matrix.
	*  @param mat Receives the output matrix
	*  @param scaling The scaling vector
	*/
	Matrix4Scaling :: proc(mat: ^Matrix4x4, scaling: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Create a 4x4 matrix that rotates one vector to another vector.
	*  @param mat Receives the output matrix
	*  @param from Vector to rotate from
	*  @param to Vector to rotate to
	*/
	Matrix4FromTo :: proc(mat: ^Matrix4x4, from: ^Vector3D, to: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Create a Quaternion from euler angles.
	*  @param q Receives the output quaternion
	*  @param x Rotation angle for the x-axis, in radians
	*  @param y Rotation angle for the y-axis, in radians
	*  @param z Rotation angle for the z-axis, in radians
	*/
	QuaternionFromEulerAngles :: proc(q: ^Quaternion, x: f32, y: f32, z: f32) ---

	// --------------------------------------------------------------------------------
	/** Create a Quaternion from an axis angle pair.
	*  @param q Receives the output quaternion
	*  @param axis The orientation axis
	*  @param angle The rotation angle, in radians
	*/
	QuaternionFromAxisAngle :: proc(q: ^Quaternion, axis: ^Vector3D, angle: f32) ---

	// --------------------------------------------------------------------------------
	/** Create a Quaternion from a normalized quaternion stored
	*  in a 3D vector.
	*  @param q Receives the output quaternion
	*  @param normalized The vector that stores the quaternion
	*/
	QuaternionFromNormalizedQuaternion :: proc(q: ^Quaternion, normalized: ^Vector3D) ---

	// --------------------------------------------------------------------------------
	/** Check if quaternions are equal.
	*  @param a First quaternion to compare
	*  @param b Second quaternion to compare
	*  @return 1 if the quaternions are equal
	*  @return 0 if the quaternions are not equal
	*/
	QuaternionAreEqual :: proc(a: ^Quaternion, b: ^Quaternion) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Check if quaternions are equal using epsilon.
	*  @param a First quaternion to compare
	*  @param b Second quaternion to compare
	*  @param epsilon Epsilon
	*  @return 1 if the quaternions are equal
	*  @return 0 if the quaternions are not equal
	*/
	QuaternionAreEqualEpsilon :: proc(a: ^Quaternion, b: ^Quaternion, epsilon: f32) -> c.int ---

	// --------------------------------------------------------------------------------
	/** Normalize a quaternion.
	*  @param q Quaternion to normalize
	*/
	QuaternionNormalize :: proc(q: ^Quaternion) ---

	// --------------------------------------------------------------------------------
	/** Compute quaternion conjugate.
	*  @param q Quaternion to compute conjugate,
	*           receives the output quaternion
	*/
	QuaternionConjugate :: proc(q: ^Quaternion) ---

	// --------------------------------------------------------------------------------
	/** Multiply quaternions.
	*  @param dst First quaternion, receives the output quaternion
	*  @param q Second quaternion
	*/
	QuaternionMultiply :: proc(dst: ^Quaternion, q: ^Quaternion) ---

	// --------------------------------------------------------------------------------
	/** Performs a spherical interpolation between two quaternions.
	* @param dst Receives the quaternion resulting from the interpolation.
	* @param start Quaternion when factor == 0
	* @param end Quaternion when factor == 1
	* @param factor Interpolation factor between 0 and 1
	*/
	QuaternionInterpolate :: proc(dst: ^Quaternion, start: ^Quaternion, end: ^Quaternion, factor: f32) ---
}
