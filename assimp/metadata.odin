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
/** @file metadata.h
*  @brief Defines the data structures for holding node meta information.
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

// -------------------------------------------------------------------------------
/**
* Enum used to distinguish data types
*/
// -------------------------------------------------------------------------------
Metadata_Type :: enum c.int {
	BOOL       = 0,
	INT32      = 1,
	UINT64     = 2,
	FLOAT      = 3,
	DOUBLE     = 4,
	AISTRING   = 5,
	AIVECTOR3D = 6,
	AIMETADATA = 7,
	INT64      = 8,
	UINT32     = 9,
	META_MAX   = 10,
}

// -------------------------------------------------------------------------------
/**
* Metadata entry
*
* The type field uniquely identifies the underlying type of the data field
*/
// -------------------------------------------------------------------------------
Metadata_Entry :: struct {
	mType: Metadata_Type,
	mData: rawptr,
}

// -------------------------------------------------------------------------------
/**
* Container for holding metadata.
*
* Metadata is a key-value store using string keys and values.
*/
// -------------------------------------------------------------------------------
Metadata :: struct {
	/** Length of the mKeys and mValues arrays, respectively */
	mNumProperties: c.uint,

	/** Arrays of keys, may not be NULL. Entries in this array may not be NULL as well. */
	mKeys: [^]String,

	/** Arrays of values, may not be NULL. Entries in this array may be NULL if the
	* corresponding property key has no assigned value. */
	mValues: [^]Metadata_Entry,
}

