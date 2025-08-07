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
/** @file  version.h
*  @brief Functions to query the version of the Assimp runtime, check
*    compile flags, ...
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

//! Assimp was compiled as a shared object (Windows: DLL)
ASSIMP_CFLAGS_SHARED  :: 0x1

//! Assimp was compiled against STLport
ASSIMP_CFLAGS_STLPORT :: 0x2

//! Assimp was compiled as a debug build
ASSIMP_CFLAGS_DEBUG   :: 0x4

//! Assimp was compiled with ASSIMP_BUILD_BOOST_WORKAROUND defined
ASSIMP_CFLAGS_NOBOOST           :: 0x8

//! Assimp was compiled with ASSIMP_BUILD_SINGLETHREADED defined
ASSIMP_CFLAGS_SINGLETHREADED    :: 0x10

//! Assimp was compiled with ASSIMP_BUILD_SINGLETHREADED defined
ASSIMP_CFLAGS_DOUBLE_SUPPORT :: 0x20

@(default_calling_convention="c", link_prefix="ai")
foreign lib {
	// ---------------------------------------------------------------------------
	/** @brief Returns a string with legal copyright and licensing information
	*  about Assimp. The string may include multiple lines.
	*  @return Pointer to static string.
	*/
	GetLegalString :: proc() -> cstring ---

	// ---------------------------------------------------------------------------
	/** @brief Returns the current patch version number of Assimp.
	*  @return Patch version of the Assimp runtime the application was
	*    linked/built against
	*/
	GetVersionPatch :: proc() -> c.uint ---

	// ---------------------------------------------------------------------------
	/** @brief Returns the current minor version number of Assimp.
	*  @return Minor version of the Assimp runtime the application was
	*    linked/built against
	*/
	GetVersionMinor :: proc() -> c.uint ---

	// ---------------------------------------------------------------------------
	/** @brief Returns the current major version number of Assimp.
	*  @return Major version of the Assimp runtime the application was
	*    linked/built against
	*/
	GetVersionMajor :: proc() -> c.uint ---

	// ---------------------------------------------------------------------------
	/** @brief Returns the repository revision of the Assimp runtime.
	*  @return SVN Repository revision number of the Assimp runtime the
	*          application was linked/built against.
	*/
	GetVersionRevision :: proc() -> c.uint ---

	// ---------------------------------------------------------------------------
	/** @brief Returns the branch-name of the Assimp runtime.
	*  @return The current branch name.
	*/
	GetBranchName :: proc() -> cstring ---

	// ---------------------------------------------------------------------------
	/** @brief Returns assimp's compile flags
	*  @return Any bitwise combination of the ASSIMP_CFLAGS_xxx constants.
	*/
	GetCompileFlags :: proc() -> c.uint ---
}
