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
/** @file texture.h
*  @brief Defines texture helper structures for the library
*
* Used for file formats which embed their textures into the model file.
* Supported are both normal textures, which are stored as uncompressed
* pixels, and "compressed" textures, which are stored in a file format
* such as PNG or TGA.
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

// --------------------------------------------------------------------------------
/** @brief Helper structure to represent a texel in a ARGB8888 format
*
*  Used by aiTexture.
*/
Texel :: struct {
	b, g, r, a: c.uchar,
}

HINTMAXTEXTURELEN :: 9

// --------------------------------------------------------------------------------
/** Helper structure to describe an embedded texture
*
* Normally textures are contained in external files but some file formats embed
* them directly in the model file. There are two types of embedded textures:
* 1. Uncompressed textures. The color data is given in an uncompressed format.
* 2. Compressed textures stored in a file format like png or jpg. The raw file
* bytes are given so the application must utilize an image decoder (e.g. DevIL) to
* get access to the actual color data.
*
* Embedded textures are referenced from materials using strings like "*0", "*1", etc.
* as the texture paths (a single asterisk character followed by the
* zero-based index of the texture in the aiScene::mTextures array).
*/
Texture :: struct {
	/** Width of the texture, in pixels
	*
	* If mHeight is zero the texture is compressed in a format
	* like JPEG. In this case mWidth specifies the size of the
	* memory area pcData is pointing to, in bytes.
	*/
	mWidth: c.uint,

	/** Height of the texture, in pixels
	*
	* If this value is zero, pcData points to an compressed texture
	* in any format (e.g. JPEG).
	*/
	mHeight: c.uint,
	achFormatHint: [9]c.char, // 8 for string + 1 for terminator.

	/** Data of the texture.
	*
	* Points to an array of mWidth * mHeight aiTexel's.
	* The format of the texture data shall always be ARGB8888 if the texture-hint of the type is empty.
	* If the hint is not empty you can interpret the format by looking into this hint.
	* make the implementation for user of the library as easy
	* as possible. If mHeight = 0 this is a pointer to a memory
	* buffer of size mWidth containing the compressed texture
	* data. Good luck, have fun!
	*/
	pcData: [^]Texel,

	/** Texture original filename
	*
	* Used to get the texture reference
	*/
	mFilename: String,
}

