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
/** @file cfileio.h
*  @brief Defines generic C routines to access memory-mapped files
*/
package assimp

import "core:c"

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

// FILEIO_H_INC :: 

// aiFile callbacks
File_Write_Proc :: proc "c" (^File, cstring, c.size_t, c.size_t) -> c.size_t

File_Read_Proc :: proc "c" (^File, cstring, c.size_t, c.size_t) -> c.size_t

File_Tell_Proc :: proc "c" (^File) -> c.size_t

File_Flush_Proc :: proc "c" (^File)

File_Seek :: proc "c" (^File, c.size_t, Origin) -> Return

// aiFileIO callbacks
File_Open_Proc :: struct {}

File_Close_Proc :: proc "c" (^File_Io, ^File)

// Represents user-defined data
User_Data :: cstring

// ----------------------------------------------------------------------------------
/** @brief C-API: File system callbacks
*
*  Provided are functions to open and close files. Supply a custom structure to
*  the import function. If you don't, a default implementation is used. Use custom
*  file systems to enable reading from other sources, such as ZIPs
*  or memory locations. */
File_Io :: struct {
	/** Function used to open a new file
	*/
	OpenProc: File_Open_Proc,

	/** Function used to close an existing file
	*/
	CloseProc: File_Close_Proc,

	/** User-defined, opaque data */
	UserData: User_Data,
}

// ----------------------------------------------------------------------------------
/** @brief C-API: File callbacks
*
*  Actually, it's a data structure to wrap a set of fXXXX (e.g fopen)
*  replacement functions.
*
*  The default implementation of the functions utilizes the fXXX functions from
*  the CRT. However, you can supply a custom implementation to Assimp by
*  delivering a custom aiFileIO. Use this to enable reading from other sources,
*  such as ZIP archives or memory locations. */
File :: struct {
	/** Callback to read from a file */
	ReadProc: File_Read_Proc,

	/** Callback to write to a file */
	WriteProc: File_Write_Proc,

	/** Callback to retrieve the current position of
	*  the file cursor (ftell())
	*/
	TellProc: File_Tell_Proc,

	/** Callback to retrieve the size of the file,
	*  in bytes
	*/
	FileSizeProc: File_Tell_Proc,

	/** Callback to set the current position
	* of the file cursor (fseek())
	*/
	SeekProc: File_Seek,

	/** Callback to flush the file contents
	*/
	FlushProc: File_Flush_Proc,

	/** User-defined, opaque data
	*/
	UserData: User_Data,
}

