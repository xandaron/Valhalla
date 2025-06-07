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
/** @file defs.h
*  @brief Assimp build configuration setup. See the notes in the comment
*  blocks to find out how to customize _your_ Assimp build.
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

// AI_FORCE_INLINE :: Inline
// AI_WONT_RETURN :: _Declspec(Noreturn)

ASSIMP_AI_REAL_TEXT_PRECISION :: 9

Real :: f32

Int :: c.int

Uint :: c.uint

/* Useful constants */
//////////////////////////////////////////////////////////////////////////

/* This is PI. Hi PI. */
AI_MATH_PI :: 3.141592653589793238462643383279
AI_MATH_TWO_PI :: AI_MATH_PI * 2.0
AI_MATH_HALF_PI :: AI_MATH_PI * 0.5

AI_MATH_PI_F :: 3.1415926538
AI_MATH_TWO_PI_F :: AI_MATH_PI_F * 2.0
AI_MATH_HALF_PI_F :: AI_MATH_PI_F * 0.5
