# Local zlib binding

This package exists because Odin's vendored `vendor:zlib` cannot be linked with anything other
than MSVC's `link.exe`.

`vendor:zlib/libz.lib` is built with `/GL` (whole-program optimization), so its object files are
stored as MSVC's "anonymous object" intermediate representation rather than native machine code.
`link.exe` knows how to turn that back into real code on the fly (that's the "restarting link with
/LTCG" step you see during a normal build), but `radlink` and `lld-link` don't implement that step
at all. The practical result is that assimp (which statically depends on zlib for its `.zip`/glTF
compression handling) fails to link when building with `--linker:radlink` or `--linker:lld`,
either with an outright "not a native COFF file" error (lld) or silently missing symbols (radlink).

`libz.lib` in this directory is a from-source rebuild of zlib 1.3.2, compiled with `cl.exe /O2 /MT`
and deliberately without `/GL`, so it's an ordinary static library any linker can consume. `/MT` is
used to match the static, multithreaded release CRT (`LIBCMT`) that `libassimp.lib` itself links
against; a `/MD` build produces CRT-mismatch warnings (`LNK4098`/`LNK4217`) instead.

`assimp/*.odin` links against `"../zlib/libz.lib"` here instead of `"vendor:zlib/libz.lib"`.
