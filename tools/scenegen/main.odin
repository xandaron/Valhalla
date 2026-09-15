package SceneGen

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:path/filepath"
import "core:strings"

import stbi "vendor:stb/image"

import refdisk "../../ref-disk"
import V "../../src"

// Every asset this produces is generated from the code below, so the output carries no third
// party licence. Regenerating is always safe: nothing here reads the existing project.

// ===[ Options ]==============================================================

Options :: struct {
	projectDir:    string,
	projectFile:   string,
	// Resolved from the project file so the generator writes where the engine reads. Stored in
	// the "./components/" form because descriptors keep paths relative to the project root.
	componentsRel: string,
	scenesRel:     string,
	generatedRel:  string,
	bench:         bool,
	environment:   bool,
	stress:        bool,
	textureSize:   int,
	// Whether the green channel points down. Assimp's tangents are derived from UVs that the
	// engine flips on import, so which convention lands correct is a property of the import
	// settings rather than of the maps; see README.
	flipNormalY:   bool,
	stressLights:  int,
	stressDensity: int,
}

DEFAULT_OPTIONS :: Options {
	projectDir    = "./demo",
	projectFile   = "",
	bench         = true,
	environment   = true,
	stress        = true,
	textureSize   = 512,
	flipNormalY   = false,
	stressLights  = 32,
	stressDensity = 100,
}

usage :: proc() {
	fmt.println("scenegen [project directory] [options]")
	fmt.println("  project directory   defaults to ./demo, same argument the engine takes")
	fmt.println("  -scene:<which>      bench, environment, stress or all (default all)")
	fmt.println("  -size:<pixels>      texture edge length, power of two (default 512)")
	fmt.println("  -flip-normal-y      write normal maps with the green channel inverted")
	fmt.println("  -lights:<count>     stress scene light count (default 32)")
	fmt.println("  -density:<percent>  stress scene instance count scale (default 100)")
	fmt.println("  -help")
}

parseCount :: proc(arg, prefix: string) -> (value: int, ok: bool) {
	digits := arg[len(prefix):]
	if len(digits) == 0 {
		fmt.eprintfln("Bad value %q.", arg)
		return 0, false
	}
	for r in digits {
		if r < '0' || r > '9' {
			fmt.eprintfln("Bad value %q.", arg)
			return 0, false
		}
		value = value * 10 + int(r - '0')
	}
	return value, true
}

parseOptions :: proc() -> (opts: Options, ok: bool) {
	opts = DEFAULT_OPTIONS
	positional := false

	for arg in os.args[1:] {
		switch {
		case arg == "-help" || arg == "--help":
			usage()
			return opts, false
		case arg == "-flip-normal-y":
			opts.flipNormalY = true
		case strings.has_prefix(arg, "-scene:"):
			which := arg[len("-scene:"):]
			opts.bench = which == "bench" || which == "all"
			opts.environment = which == "environment" || which == "all"
			opts.stress = which == "stress" || which == "all"
			if !(opts.bench || opts.environment || opts.stress) {
				fmt.eprintfln("Unknown scene %q, expected bench, environment, stress or all.", arg)
				return opts, false
			}
		case strings.has_prefix(arg, "-size:"):
			size := parseCount(arg, "-size:") or_return
			if size < 8 {
				fmt.eprintfln("Size %v is too small.", size)
				return opts, false
			}
			opts.textureSize = size
		case strings.has_prefix(arg, "-lights:"):
			opts.stressLights = parseCount(arg, "-lights:") or_return
			if opts.stressLights < 1 {
				fmt.eprintln("The stress scene needs at least one light.")
				return opts, false
			}
		case strings.has_prefix(arg, "-density:"):
			opts.stressDensity = parseCount(arg, "-density:") or_return
			if opts.stressDensity < 1 {
				fmt.eprintln("Density must be at least 1 percent.")
				return opts, false
			}
		case strings.has_prefix(arg, "-"):
			fmt.eprintfln("Unknown option %q.", arg)
			return opts, false
		case !positional:
			opts.projectDir = arg
			positional = true
		case:
			fmt.eprintfln("Unexpected argument %q.", arg)
			return opts, false
		}
	}
	return opts, true
}


// ===[ Deterministic Noise ]==================================================

// Hashed rather than seeded from the clock so that regenerating produces byte-identical assets.

hash3 :: proc(x, y, seed: u32) -> u32 {
	h := seed + x * 374761393 + y * 668265263
	h = (h ~ (h >> 13)) * 1274126177
	return h ~ (h >> 16)
}

hashFloat :: proc(x, y, seed: u32) -> f32 {
	return f32(hash3(x, y, seed) & 0xFFFFFF) / f32(0xFFFFFF)
}

smoothstep :: proc(t: f32) -> f32 {
	return t * t * (3.0 - 2.0 * t)
}

// Tileable value noise. Lattice coordinates wrap at `period` so the result tiles seamlessly,
// which matters because every surface here repeats its UVs.
valueNoise :: proc(x, y: f32, period: u32, seed: u32) -> f32 {
	xi := u32(math.floor(x))
	yi := u32(math.floor(y))
	xf := x - math.floor(x)
	yf := y - math.floor(y)

	wrap :: proc(v, period: u32) -> u32 {
		return v % period
	}

	x0 := wrap(xi, period)
	y0 := wrap(yi, period)
	x1 := wrap(xi + 1, period)
	y1 := wrap(yi + 1, period)

	v00 := hashFloat(x0, y0, seed)
	v10 := hashFloat(x1, y0, seed)
	v01 := hashFloat(x0, y1, seed)
	v11 := hashFloat(x1, y1, seed)

	sx := smoothstep(xf)
	sy := smoothstep(yf)
	return linalg.lerp(linalg.lerp(v00, v10, sx), linalg.lerp(v01, v11, sx), sy)
}

fbm :: proc(x, y: f32, basePeriod: u32, octaves: int, seed: u32) -> f32 {
	total, amplitude, normalisation := f32(0), f32(1), f32(0)
	period := basePeriod
	frequency := f32(1)
	for i in 0 ..< octaves {
		total += valueNoise(x * frequency, y * frequency, period, seed + u32(i) * 7919) * amplitude
		normalisation += amplitude
		amplitude *= 0.5
		frequency *= 2
		period *= 2
	}
	return total / normalisation
}


// ===[ Images ]===============================================================

Image :: struct {
	width, height: int,
	pixels:        []u8,
}

imageMake :: proc(width, height: int) -> Image {
	return Image{width = width, height = height, pixels = make([]u8, width * height * 4)}
}

imageDelete :: proc(image: ^Image) {
	delete(image.pixels)
	image.pixels = nil
}

imageSet :: proc(image: ^Image, x, y: int, colour: [3]f32) {
	channel :: proc(v: f32) -> u8 {
		return u8(clamp(v * 255.0 + 0.5, 0, 255))
	}
	index := (y * image.width + x) * 4
	image.pixels[index + 0] = channel(colour.r)
	image.pixels[index + 1] = channel(colour.g)
	image.pixels[index + 2] = channel(colour.b)
	image.pixels[index + 3] = 255
}

writePNG :: proc(path: string, image: ^Image) -> bool {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	written := stbi.write_png(
		cpath,
		i32(image.width),
		i32(image.height),
		4,
		raw_data(image.pixels),
		i32(image.width * 4),
	)
	if written == 0 {
		fmt.eprintfln("Failed to write %q.", path)
		return false
	}
	return true
}

// Central differences on a wrapped height field. The surface normal of a height map h is
// normalize(-dh/du, -dh/dv, 1); `strength` is just how tall the relief is taken to be relative
// to a texel.
heightToNormal :: proc(height: []f32, width, height_: int, strength: f32, flipY: bool) -> Image {
	sample :: proc(height: []f32, width, height_, x, y: int) -> f32 {
		xx := ((x % width) + width) % width
		yy := ((y % height_) + height_) % height_
		return height[yy * width + xx]
	}

	image := imageMake(width, height_)
	for y in 0 ..< height_ {
		for x in 0 ..< width {
			dx :=
				sample(height, width, height_, x + 1, y) - sample(height, width, height_, x - 1, y)
			dy :=
				sample(height, width, height_, x, y + 1) - sample(height, width, height_, x, y - 1)

			normal := linalg.normalize(V.Vec3{-dx * strength, -dy * strength, 1})
			if flipY {
				normal.y = -normal.y
			}
			imageSet(&image, x, y, {normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5})
		}
	}
	return image
}

flatNormalImage :: proc(size: int) -> Image {
	image := imageMake(size, size)
	for y in 0 ..< size {
		for x in 0 ..< size {
			imageSet(&image, x, y, {0.5, 0.5, 1.0})
		}
	}
	return image
}


// ===[ Patterns ]=============================================================

Pattern :: struct {
	albedo: Image,
	height: []f32,
}

patternDelete :: proc(pattern: ^Pattern) {
	imageDelete(&pattern.albedo)
	delete(pattern.height)
	pattern.height = nil
}

// Running bond brick. The height field bevels towards the mortar so the normal map has a clear
// direction change at every edge rather than a single-texel cliff.
brickPattern :: proc(size: int, seed: u32) -> Pattern {
	COLUMNS :: 4
	ROWS :: 8
	MORTAR :: f32(0.055)
	BEVEL :: f32(0.09)

	pattern := Pattern {
		albedo = imageMake(size, size),
		height = make([]f32, size * size),
	}

	for y in 0 ..< size {
		for x in 0 ..< size {
			u := f32(x) / f32(size)
			v := f32(y) / f32(size)

			row := int(v * ROWS)
			localV := v * ROWS - f32(row)

			// Every other course shifts by half a brick.
			offset := f32(row % 2) * 0.5
			shifted := u * COLUMNS + offset
			column := int(shifted)
			localU := shifted - f32(column)

			edgeU := min(localU, 1.0 - localU)
			edgeV := min(localV, 1.0 - localV)
			edge := min(edgeU / f32(COLUMNS), edgeV / f32(ROWS)) * f32(max(COLUMNS, ROWS))

			grain := fbm(u * 24, v * 24, 24, 4, seed)
			h: f32
			if edge < MORTAR {
				h = 0.08 * grain
			} else {
				bevel := clamp((edge - MORTAR) / BEVEL, 0, 1)
				h = 0.35 + 0.65 * smoothstep(bevel) + 0.06 * grain
			}
			pattern.height[y * size + x] = h

			colour: [3]f32
			if edge < MORTAR {
				grey := 0.48 + 0.10 * grain
				colour = {grey, grey * 0.99, grey * 0.95}
			} else {
				// One hash per brick keeps the courses from looking rubber-stamped.
				tint := hashFloat(u32(column), u32(row), seed)
				base := [3]f32{0.42, 0.16, 0.12}
				base += [3]f32{0.16, 0.08, 0.05} * (tint - 0.5) * 2
				base *= 0.82 + 0.30 * grain
				colour = base
			}
			imageSet(&pattern.albedo, x, y, colour)
		}
	}
	return pattern
}

// Square tiles with recessed grout.
tilePattern :: proc(size: int, seed: u32) -> Pattern {
	TILES :: 6
	GROUT :: f32(0.04)
	BEVEL :: f32(0.06)

	pattern := Pattern {
		albedo = imageMake(size, size),
		height = make([]f32, size * size),
	}

	for y in 0 ..< size {
		for x in 0 ..< size {
			u := f32(x) / f32(size)
			v := f32(y) / f32(size)

			su := u * TILES
			sv := v * TILES
			cx := int(su)
			cy := int(sv)
			localU := su - f32(cx)
			localV := sv - f32(cy)

			edge := min(min(localU, 1.0 - localU), min(localV, 1.0 - localV))
			grain := fbm(u * 32, v * 32, 32, 4, seed + 17)

			h: f32
			if edge < GROUT {
				h = 0.05 + 0.05 * grain
			} else {
				bevel := clamp((edge - GROUT) / BEVEL, 0, 1)
				h = 0.30 + 0.70 * smoothstep(bevel)
			}
			pattern.height[y * size + x] = h

			colour: [3]f32
			if edge < GROUT {
				grey := 0.30 + 0.08 * grain
				colour = {grey, grey, grey * 0.97}
			} else {
				tint := hashFloat(u32(cx), u32(cy), seed + 991)
				base := [3]f32{0.58, 0.60, 0.63}
				base += [3]f32{0.10, 0.09, 0.07} * (tint - 0.5) * 2
				base *= 0.90 + 0.18 * grain
				colour = base
			}
			imageSet(&pattern.albedo, x, y, colour)
		}
	}
	return pattern
}

// A grid of hemispheres. This is the unambiguous normal map: the relief is geometric, so if
// tangent space is wrong the lighting on the domes is visibly lit from the wrong side.
bumpPattern :: proc(size: int) -> Pattern {
	DOMES :: 8
	RADIUS :: f32(0.36)

	pattern := Pattern {
		albedo = imageMake(size, size),
		height = make([]f32, size * size),
	}

	for y in 0 ..< size {
		for x in 0 ..< size {
			u := f32(x) / f32(size) * DOMES
			v := f32(y) / f32(size) * DOMES
			localU := u - math.floor(u) - 0.5
			localV := v - math.floor(v) - 0.5

			distance := math.sqrt(localU * localU + localV * localV)
			h: f32 = 0
			if distance < RADIUS {
				t := distance / RADIUS
				h = math.sqrt(max(0, 1.0 - t * t))
			}
			pattern.height[y * size + x] = h

			shade := 0.62 + 0.16 * h
			imageSet(&pattern.albedo, x, y, {shade, shade * 0.97, shade * 0.92})
		}
	}
	return pattern
}

// Flat two-tone reference surface. Deliberately has no relief: it is the control that the
// normal-mapped surfaces are compared against.
checkerImage :: proc(size: int) -> Image {
	SQUARES :: 8
	image := imageMake(size, size)
	for y in 0 ..< size {
		for x in 0 ..< size {
			cx := x * SQUARES / size
			cy := y * SQUARES / size
			shade: f32 = (cx + cy) % 2 == 0 ? 0.72 : 0.24
			imageSet(&image, x, y, {shade, shade, shade})
		}
	}
	return image
}

plasterPattern :: proc(size: int, seed: u32) -> Pattern {
	pattern := Pattern {
		albedo = imageMake(size, size),
		height = make([]f32, size * size),
	}
	for y in 0 ..< size {
		for x in 0 ..< size {
			u := f32(x) / f32(size)
			v := f32(y) / f32(size)
			coarse := fbm(u * 8, v * 8, 8, 5, seed)
			fine := fbm(u * 48, v * 48, 48, 3, seed + 31)

			pattern.height[y * size + x] = 0.55 * coarse + 0.45 * fine
			shade := 0.60 + 0.12 * (coarse - 0.5) + 0.05 * (fine - 0.5)
			imageSet(&pattern.albedo, x, y, {shade, shade * 0.98, shade * 0.93})
		}
	}
	return pattern
}

// Binary zone plate. Ring frequency rises linearly with radius and reaches the Nyquist limit at
// the edge, so minification without mip levels shows up as false rings rather than as grey.
zonePlateImage :: proc(size: int) -> Image {
	image := imageMake(size, size)
	half := f32(size) * 0.5
	for y in 0 ..< size {
		for x in 0 ..< size {
			dx := f32(x) - half
			dy := f32(y) - half
			phase := math.PI * (dx * dx + dy * dy) / f32(size)
			shade: f32 = math.cos(phase) > 0 ? 0.8 : 0.1
			imageSet(&image, x, y, {shade, shade, shade})
		}
	}
	return image
}

hueColour :: proc(hue: f32) -> [3]f32 {
	h := hue * 6
	return {clamp(abs(h - 3) - 1, 0, 1), clamp(2 - abs(h - 2), 0, 1), clamp(2 - abs(h - 4), 0, 1)}
}

// Flat cells keep the PNG tiny on disk while the decoded image still costs its full size in
// device memory, which is the cost being exercised.
variantImage :: proc(size, variant, variants: int) -> Image {
	CELLS :: 8
	image := imageMake(size, size)
	tint := hueColour(f32(variant) / f32(variants))
	for y in 0 ..< size {
		for x in 0 ..< size {
			shade := 0.35 + 0.5 * hashFloat(u32(x * CELLS / size), u32(y * CELLS / size), u32(variant) + 4099)
			imageSet(&image, x, y, tint * shade)
		}
	}
	return image
}


// ===[ Geometry ]=============================================================

Mesh :: struct {
	positions: [dynamic]V.Vec3,
	normals:   [dynamic]V.Vec3,
	uvs:       [dynamic]V.Vec2,
	indices:   [dynamic]u32,
}

meshDelete :: proc(mesh: ^Mesh) {
	delete(mesh.positions)
	delete(mesh.normals)
	delete(mesh.uvs)
	delete(mesh.indices)
}

addVertex :: proc(mesh: ^Mesh, position, normal: V.Vec3, uv: V.Vec2) -> u32 {
	append(&mesh.positions, position)
	append(&mesh.normals, normal)
	append(&mesh.uvs, uv)
	return u32(len(mesh.positions) - 1)
}

addQuad :: proc(mesh: ^Mesh, a, b, c, d: u32) {
	append(&mesh.indices, a, b, c)
	append(&mesh.indices, a, c, d)
}

makePlane :: proc(segments: int, size, uvTiles: f32) -> Mesh {
	mesh: Mesh
	stride := u32(segments + 1)
	for z in 0 ..= segments {
		for x in 0 ..= segments {
			fx := f32(x) / f32(segments)
			fz := f32(z) / f32(segments)
			addVertex(
				&mesh,
				{(fx - 0.5) * size, 0, (fz - 0.5) * size},
				{0, 1, 0},
				{fx * uvTiles, fz * uvTiles},
			)
		}
	}
	for z in 0 ..< u32(segments) {
		for x in 0 ..< u32(segments) {
			i00 := z * stride + x
			addQuad(&mesh, i00, i00 + stride, i00 + stride + 1, i00 + 1)
		}
	}
	return mesh
}

makeCube :: proc(size, uvTiles: f32) -> Mesh {
	mesh: Mesh
	half := size * 0.5

	// du cross dv must equal the outward normal, otherwise the face is wound inside out.
	face :: proc(mesh: ^Mesh, origin, du, dv, normal: V.Vec3, uvTiles: f32) {
		a := addVertex(mesh, origin, normal, {0, 0})
		b := addVertex(mesh, origin + du, normal, {uvTiles, 0})
		c := addVertex(mesh, origin + du + dv, normal, {uvTiles, uvTiles})
		d := addVertex(mesh, origin + dv, normal, {0, uvTiles})
		addQuad(mesh, a, b, c, d)
	}

	s := size
	face(&mesh, {half, -half, -half}, {0, s, 0}, {0, 0, s}, {1, 0, 0}, uvTiles)
	face(&mesh, {-half, -half, -half}, {0, 0, s}, {0, s, 0}, {-1, 0, 0}, uvTiles)
	face(&mesh, {-half, half, -half}, {0, 0, s}, {s, 0, 0}, {0, 1, 0}, uvTiles)
	face(&mesh, {-half, -half, -half}, {s, 0, 0}, {0, 0, s}, {0, -1, 0}, uvTiles)
	face(&mesh, {-half, -half, half}, {s, 0, 0}, {0, s, 0}, {0, 0, 1}, uvTiles)
	face(&mesh, {-half, -half, -half}, {0, s, 0}, {s, 0, 0}, {0, 0, -1}, uvTiles)
	return mesh
}

makeSphere :: proc(rings, segments: int, radius, uvTiles: f32) -> Mesh {
	mesh: Mesh
	stride := u32(segments + 1)
	for ring in 0 ..= rings {
		v := f32(ring) / f32(rings)
		phi := v * math.PI
		for segment in 0 ..= segments {
			u := f32(segment) / f32(segments)
			theta := u * 2 * math.PI
			normal := V.Vec3 {
				math.sin(phi) * math.cos(theta),
				math.cos(phi),
				math.sin(phi) * math.sin(theta),
			}
			addVertex(&mesh, normal * radius, normal, {u * uvTiles, v * uvTiles})
		}
	}
	for ring in 0 ..< u32(rings) {
		for segment in 0 ..< u32(segments) {
			i00 := ring * stride + segment
			addQuad(&mesh, i00, i00 + 1, i00 + stride + 1, i00 + stride)
		}
	}
	return mesh
}

makeTorus :: proc(majorSegments, minorSegments: int, majorRadius, minorRadius, uvTiles: f32) -> Mesh {
	mesh: Mesh
	stride := u32(minorSegments + 1)
	for major in 0 ..= majorSegments {
		u := f32(major) / f32(majorSegments)
		theta := u * 2 * math.PI
		for minor in 0 ..= minorSegments {
			v := f32(minor) / f32(minorSegments)
			phi := v * 2 * math.PI
			normal := V.Vec3 {
				math.cos(theta) * math.cos(phi),
				math.sin(phi),
				math.sin(theta) * math.cos(phi),
			}
			position := V.Vec3 {
				math.cos(theta) * majorRadius + normal.x * minorRadius,
				normal.y * minorRadius,
				math.sin(theta) * majorRadius + normal.z * minorRadius,
			}
			addVertex(&mesh, position, normal, {u * uvTiles * 4, v * uvTiles})
		}
	}
	for major in 0 ..< u32(majorSegments) {
		for minor in 0 ..< u32(minorSegments) {
			i00 := major * stride + minor
			addQuad(&mesh, i00, i00 + 1, i00 + stride + 1, i00 + stride)
		}
	}
	return mesh
}

// One object per file. The loader sizes an object's texture list from the model's mesh count,
// so a file that imported as several meshes would index past it.
writeOBJ :: proc(path, name: string, mesh: ^Mesh) -> bool {
	builder := strings.builder_make(context.temp_allocator)

	fmt.sbprintln(&builder, "# Generated by Valhalla scenegen.")
	fmt.sbprintfln(&builder, "o %s", name)
	for position in mesh.positions {
		fmt.sbprintfln(&builder, "v %.6f %.6f %.6f", position.x, position.y, position.z)
	}
	for uv in mesh.uvs {
		fmt.sbprintfln(&builder, "vt %.6f %.6f", uv.x, uv.y)
	}
	for normal in mesh.normals {
		fmt.sbprintfln(&builder, "vn %.6f %.6f %.6f", normal.x, normal.y, normal.z)
	}
	for i := 0; i < len(mesh.indices); i += 3 {
		a := mesh.indices[i] + 1
		b := mesh.indices[i + 1] + 1
		c := mesh.indices[i + 2] + 1
		fmt.sbprintfln(&builder, "f %d/%d/%d %d/%d/%d %d/%d/%d", a, a, a, b, b, b, c, c, c)
	}

	if err := os.write_entire_file(path, strings.to_string(builder)); err != nil {
		fmt.eprintfln("Failed to write %q: %v", path, err)
		return false
	}
	return true
}


// ===[ Descriptors ]==========================================================

// These go through refdisk against the engine's own structs rather than writing the byte layout
// by hand, so a change to SceneData or ModelComponent cannot leave the generator behind.

saveComponent :: proc(path: string, data: any) -> bool {
	file, err := os.open(path, {.Write, .Create, .Trunc})
	if err != nil {
		fmt.eprintfln("Failed to open %q: %v", path, err)
		return false
	}
	defer os.close(file)
	refdisk.save(file, data)
	return true
}

Asset :: struct {
	name:           string,
	descriptorPath: string,
	assetPath:      string,
}

writeTextureDescriptor :: proc(asset: Asset) -> bool {
	return saveComponent(
		asset.descriptorPath,
		V.TextureComponent{name = asset.name, assetPath = asset.assetPath},
	)
}

writeModelDescriptor :: proc(asset: Asset) -> bool {
	return saveComponent(
		asset.descriptorPath,
		V.ModelComponent {
			name = asset.name,
			assetPath = asset.assetPath,
			position = {0, 0, 0},
			rotation = V.IQUAT,
			scale = {1, 1, 1},
		},
	)
}


// ===[ Scene Assembly ]=======================================================

Builder :: struct {
	models:   [dynamic]string,
	textures: [dynamic]string,
	objects:  [dynamic]V.ObjectComponent,
	lights:   [dynamic]V.PointLight,
	cameras:  [dynamic]V.Camera,
}

addObject :: proc(
	builder: ^Builder,
	name: string,
	modelIdx: u32,
	position: V.Vec3,
	scale: V.Vec3,
	albedo, normal: u32,
	rotation := V.IQUAT,
	meshCount := 1,
	animation := V.AnimationComponent{idx = -1},
	attachment := V.Attachment{targetIdx = -1, bindpointIdx = 0},
) -> u32 {
	textureIdxs := make([][V.TextureIndex]u32, meshCount, context.temp_allocator)
	for &meshTextures in textureIdxs {
		meshTextures[.Albedo] = albedo
		meshTextures[.NormalMap] = normal
	}

	append(
		&builder.objects,
		V.ObjectComponent {
			name = name,
			position = position,
			rotation = rotation,
			scale = scale,
			modelIdx = modelIdx,
			textureIdxs = textureIdxs,
			animation = animation,
			attachment = attachment,
		},
	)
	return u32(len(builder.objects) - 1)
}

addLight :: proc(builder: ^Builder, name: string, position, colour: V.Vec3, lumens: f32) {
	append(
		&builder.lights,
		V.PointLight{name = name, position = position, colour = colour, lumens = lumens},
	)
}

addCamera :: proc(builder: ^Builder, name: string, eye, center: V.Vec3, far: f32 = 200) {
	append(
		&builder.cameras,
		V.Camera {
			name = name,
			mode = .PERSPECTIVE,
			eye = eye,
			center = center,
			up = {0, 1, 0},
			fov = 55,
			near = 0.1,
			far = far,
		},
	)
}


// ===[ Generation ]===========================================================

// Indices into the descriptor lists below. Both scenes share one set, so these stay in step
// with the order the lists are built in.
Model :: enum u32 {
	Plane = 0,
	Cube,
	Sphere,
	Torus,
}

Tex :: enum u32 {
	Checker = 0,
	FlatNormal,
	BrickAlbedo,
	BrickNormal,
	TileAlbedo,
	TileNormal,
	BumpNormal,
	PlasterAlbedo,
	PlasterNormal,
}

MODEL_ASSETS := [Model]struct {
	name: string,
	file: string,
} {
	.Plane  = {"Generated Plane", "gen_plane"},
	.Cube   = {"Generated Cube", "gen_cube"},
	.Sphere = {"Generated Sphere", "gen_sphere"},
	.Torus  = {"Generated Torus", "gen_torus"},
}

TEXTURE_ASSETS := [Tex]struct {
	name: string,
	file: string,
} {
	.Checker       = {"Generated Checker", "gen_checker"},
	.FlatNormal    = {"Generated Flat Normal", "gen_flat_normal"},
	.BrickAlbedo   = {"Generated Brick", "gen_brick_albedo"},
	.BrickNormal   = {"Generated Brick Normal", "gen_brick_normal"},
	.TileAlbedo    = {"Generated Tile", "gen_tile_albedo"},
	.TileNormal    = {"Generated Tile Normal", "gen_tile_normal"},
	.BumpNormal    = {"Generated Bump Normal", "gen_bump_normal"},
	.PlasterAlbedo = {"Generated Plaster", "gen_plaster_albedo"},
	.PlasterNormal = {"Generated Plaster Normal", "gen_plaster_normal"},
}

StressModel :: enum u32 {
	DenseSphere = 0,
	TiledPlane,
}

STRESS_MODEL_ASSETS := [StressModel]struct {
	name: string,
	file: string,
} {
	.DenseSphere = {"Generated Dense Sphere", "gen_dense_sphere"},
	.TiledPlane  = {"Generated Tiled Plane", "gen_tiled_plane"},
}

STRESS_VARIANTS :: 48
STRESS_VARIANT_SIZE :: 1024
STRESS_ZONE_PLATE_SIZE :: 4096

KnightPart :: enum u32 {
	Body = 0,
	Helmet,
	Sword,
}

// Referenced rather than generated: the stress scene needs a skinned, animated mesh, and nothing
// here can make one. These are the descriptors knight.scene already uses.
KNIGHT_PARTS := [KnightPart]string {
	.Body   = "Knight.model",
	.Helmet = "Knight_Helmet.model",
	.Sword  = "Knight_Sword.model",
}

KNIGHT_TEXTURES := [2]string{"knight.texture", "blank_normal.texture"}

// Must equal the mesh count assimp produces for Knight_Simplified.glb: the loader indexes an
// object's texture list by mesh, so a shorter list reads past its end.
KNIGHT_MESH_COUNT :: 6
KNIGHT_HEAD_BINDPOINT :: 0
KNIGHT_RIGHT_HAND_BINDPOINT :: 2

stressModel :: proc(model: StressModel) -> u32 {
	return u32(len(Model)) + u32(model)
}

knightModel :: proc(part: KnightPart) -> u32 {
	return u32(len(Model) + len(StressModel)) + u32(part)
}

ZONE_PLATE_TEX :: u32(len(Tex))
KNIGHT_ALBEDO_TEX :: u32(len(Tex)) + 1 + STRESS_VARIANTS
KNIGHT_NORMAL_TEX :: KNIGHT_ALBEDO_TEX + 1

variantTex :: proc(variant: int) -> u32 {
	return u32(len(Tex)) + 1 + u32(variant % STRESS_VARIANTS)
}

GENERATED_SUBDIR :: "generated/"

// The positional argument may be the project file or the directory holding it, because both are
// natural to type and the engine itself now takes the file.
resolveProject :: proc(opts: ^Options) -> bool {
	opts.projectFile = opts.projectDir
	if os.is_dir(opts.projectDir) {
		found := ""
		iterator, err := os.read_directory_by_path(opts.projectDir, -1, context.temp_allocator)
		if err != nil {
			fmt.eprintfln("Failed to read %q: %v", opts.projectDir, err)
			return false
		}
		for info in iterator {
			if strings.has_suffix(info.name, ".project") {
				if found != "" {
					fmt.eprintfln(
						"%q holds more than one .project file; name the one you want.",
						opts.projectDir,
					)
					return false
				}
				found = info.name
			}
		}
		if found == "" {
			fmt.eprintfln("No .project file in %q. Create one with projectgen first.", opts.projectDir)
			return false
		}
		opts.projectFile = fmt.tprintf("%s/%s", opts.projectDir, found)
	} else if !os.exists(opts.projectFile) {
		fmt.eprintfln("%q does not exist.", opts.projectFile)
		return false
	} else {
		opts.projectDir = filepath.dir(opts.projectFile)
	}

	project, loadErr := V.loadProject(opts.projectFile)
	if loadErr != .None {
		fmt.eprintfln("Failed to load %q: %v", opts.projectFile, loadErr)
		return false
	}

	// loadProject already rejects a project that leaves any of these unset, so they are taken as
	// given rather than defaulted a second time here.
	opts.componentsRel = project.componentsPath
	opts.scenesRel = project.scenesPath
	opts.generatedRel = fmt.tprintf("%s%s", project.assetsPath, GENERATED_SUBDIR)

	fmt.printfln("Project \"%v\" (%v)", project.name, opts.projectFile)
	return true
}

generateMeshes :: proc(opts: Options) -> bool {
	dir := fmt.tprintf("%s/%s", opts.projectDir, opts.generatedRel)

	meshes := [Model]Mesh {
		.Plane  = makePlane(4, 20, 4),
		.Cube   = makeCube(1, 1),
		.Sphere = makeSphere(32, 64, 0.5, 1),
		.Torus  = makeTorus(64, 32, 0.75, 0.28, 1),
	}

	for model in Model {
		mesh := meshes[model]
		defer meshDelete(&mesh)
		path := fmt.tprintf("%s%s.obj", dir, MODEL_ASSETS[model].file)
		if !writeOBJ(path, MODEL_ASSETS[model].name, &mesh) {
			return false
		}
		fmt.printfln("  %s  (%v vertices, %v triangles)", path, len(mesh.positions), len(mesh.indices) / 3)
	}
	return true
}

generateTextures :: proc(opts: Options) -> bool {
	dir := fmt.tprintf("%s/%s", opts.projectDir, opts.generatedRel)
	size := opts.textureSize

	write :: proc(dir: string, tex: Tex, image: ^Image) -> bool {
		path := fmt.tprintf("%s%s.png", dir, TEXTURE_ASSETS[tex].file)
		if !writePNG(path, image) {
			return false
		}
		fmt.printfln("  %s", path)
		return true
	}

	checker := checkerImage(size)
	defer imageDelete(&checker)
	flat := flatNormalImage(4)
	defer imageDelete(&flat)

	brick := brickPattern(size, 1337)
	defer patternDelete(&brick)
	brickNormal := heightToNormal(brick.height, size, size, f32(size) / 64.0, opts.flipNormalY)
	defer imageDelete(&brickNormal)

	tile := tilePattern(size, 2024)
	defer patternDelete(&tile)
	tileNormal := heightToNormal(tile.height, size, size, f32(size) / 64.0, opts.flipNormalY)
	defer imageDelete(&tileNormal)

	bump := bumpPattern(size)
	defer patternDelete(&bump)
	bumpNormal := heightToNormal(bump.height, size, size, f32(size) / 48.0, opts.flipNormalY)
	defer imageDelete(&bumpNormal)

	plaster := plasterPattern(size, 77)
	defer patternDelete(&plaster)
	plasterNormal := heightToNormal(plaster.height, size, size, f32(size) / 96.0, opts.flipNormalY)
	defer imageDelete(&plasterNormal)

	if !write(dir, .Checker, &checker) do return false
	if !write(dir, .FlatNormal, &flat) do return false
	if !write(dir, .BrickAlbedo, &brick.albedo) do return false
	if !write(dir, .BrickNormal, &brickNormal) do return false
	if !write(dir, .TileAlbedo, &tile.albedo) do return false
	if !write(dir, .TileNormal, &tileNormal) do return false
	if !write(dir, .BumpNormal, &bumpNormal) do return false
	if !write(dir, .PlasterAlbedo, &plaster.albedo) do return false
	if !write(dir, .PlasterNormal, &plasterNormal) do return false
	return true
}

generateDescriptors :: proc(opts: Options) -> bool {
	for model in Model {
		entry := MODEL_ASSETS[model]
		if !writeModelDescriptor(
			Asset {
				name = entry.name,
				descriptorPath = fmt.tprintf(
					"%s/%s%s.model",
					opts.projectDir,
					opts.componentsRel,
					entry.file,
				),
				assetPath = fmt.tprintf("%s%s.obj", opts.generatedRel, entry.file),
			},
		) {
			return false
		}
	}

	for tex in Tex {
		entry := TEXTURE_ASSETS[tex]
		if !writeTextureDescriptor(
			Asset {
				name = entry.name,
				descriptorPath = fmt.tprintf(
					"%s/%s%s.texture",
					opts.projectDir,
					opts.componentsRel,
					entry.file,
				),
				assetPath = fmt.tprintf("%s%s.png", opts.generatedRel, entry.file),
			},
		) {
			return false
		}
	}
	return true
}

commonLists :: proc(opts: Options, builder: ^Builder) {
	for model in Model {
		append(&builder.models, fmt.tprintf("%s%s.model", opts.componentsRel, MODEL_ASSETS[model].file))
	}
	for tex in Tex {
		append(&builder.textures, fmt.tprintf("%s%s.texture", opts.componentsRel, TEXTURE_ASSETS[tex].file))
	}
}

saveSceneFile :: proc(opts: Options, fileName, name: string, ambient: f32, builder: ^Builder) -> bool {
	path := fmt.tprintf("%s/%s%s.scene", opts.projectDir, opts.scenesRel, fileName)
	data := V.SceneData {
		name         = name,
		ambientLight = ambient,
		clearColour  = {0.02, 0.025, 0.035, 1},
		models       = builder.models,
		textures     = builder.textures,
		objects      = builder.objects,
		lights       = builder.lights,
		cameras      = builder.cameras,
	}
	if !saveComponent(path, data) {
		return false
	}
	fmt.printfln(
		"  %s  (%v objects, %v lights)",
		path,
		len(builder.objects),
		len(builder.lights),
	)
	return true
}

// Diagnostic scene. Ambient is deliberately low: a high ambient floor flattens relief and is the
// quickest way to convince yourself normal mapping is broken when it is not.
buildBenchScene :: proc(opts: Options) -> bool {
	builder: Builder
	commonLists(opts, &builder)

	addObject(&builder, "Ground", u32(Model.Plane), {0, 0, 0}, {1, 1, 1}, u32(Tex.Checker), u32(Tex.FlatNormal))

	// A/B pair: identical albedo and geometry, differing only in the normal map. Any difference
	// between these two is normal mapping and nothing else.
	addObject(&builder, "Sphere Flat (reference)", u32(Model.Sphere), {-4.5, 1, 0}, {2, 2, 2}, u32(Tex.Checker), u32(Tex.FlatNormal))
	addObject(&builder, "Sphere Bumped", u32(Model.Sphere), {-1.5, 1, 0}, {2, 2, 2}, u32(Tex.Checker), u32(Tex.BumpNormal))

	addObject(&builder, "Cube Brick", u32(Model.Cube), {1.5, 1, 0}, {2, 2, 2}, u32(Tex.BrickAlbedo), u32(Tex.BrickNormal))

	// Non-uniform scale exercises the inverse transpose in the vertex shader; if that is wrong
	// the lighting on this cube disagrees with the one beside it.
	addObject(&builder, "Cube Squashed", u32(Model.Cube), {4.75, 0.75, 0}, {3, 1.5, 2}, u32(Tex.BrickAlbedo), u32(Tex.BrickNormal))

	// Doubly curved with a wrapping UV seam, which is where tangent handedness goes wrong.
	addObject(&builder, "Torus", u32(Model.Torus), {0, 1.1, 3.5}, {2, 2, 2}, u32(Tex.TileAlbedo), u32(Tex.TileNormal))

	addObject(&builder, "Back Wall", u32(Model.Cube), {0, 3, 6.5}, {16, 6, 0.4}, u32(Tex.BrickAlbedo), u32(Tex.BrickNormal))

	// Two opposed coloured lights make the relief direction readable: a bump lit from the left
	// and from the right should shade on opposite sides.
	addLight(&builder, "Key (warm)", {-5, 4, -4}, {1.0, 0.78, 0.55}, 2200)
	addLight(&builder, "Fill (cool)", {5, 3.5, -4}, {0.55, 0.72, 1.0}, 1700)
	addLight(&builder, "Rim", {0, 5, 4}, {1, 1, 1}, 1100)

	addCamera(&builder, "Bench", {0, 3.5, -9}, {0, 1.2, 0})

	return saveSceneFile(opts, "bench", "Bench", 0.05, &builder)
}

// Presentable scene: a walled courtyard. Judges whether the renderer looks right overall rather
// than whether a single feature works.
buildEnvironmentScene :: proc(opts: Options) -> bool {
	builder: Builder
	commonLists(opts, &builder)

	addObject(&builder, "Floor", u32(Model.Plane), {0, 0, 0}, {1, 1, 1}, u32(Tex.TileAlbedo), u32(Tex.TileNormal))

	WALL_HEIGHT :: f32(5)
	WALL_SPAN :: f32(20)
	WALL_THICK :: f32(0.5)
	half := WALL_SPAN * 0.5

	addObject(&builder, "Wall North", u32(Model.Cube), {0, WALL_HEIGHT / 2, half}, {WALL_SPAN, WALL_HEIGHT, WALL_THICK}, u32(Tex.BrickAlbedo), u32(Tex.BrickNormal))
	addObject(&builder, "Wall South", u32(Model.Cube), {0, WALL_HEIGHT / 2, -half}, {WALL_SPAN, WALL_HEIGHT, WALL_THICK}, u32(Tex.BrickAlbedo), u32(Tex.BrickNormal))
	addObject(&builder, "Wall East", u32(Model.Cube), {half, WALL_HEIGHT / 2, 0}, {WALL_THICK, WALL_HEIGHT, WALL_SPAN}, u32(Tex.BrickAlbedo), u32(Tex.BrickNormal))
	addObject(&builder, "Wall West", u32(Model.Cube), {-half, WALL_HEIGHT / 2, 0}, {WALL_THICK, WALL_HEIGHT, WALL_SPAN}, u32(Tex.BrickAlbedo), u32(Tex.BrickNormal))

	pillars := [4]V.Vec3{{-6, 0, -6}, {6, 0, -6}, {-6, 0, 6}, {6, 0, 6}}
	pillarLights := [4]struct {
		name:   string,
		colour: V.Vec3,
	} {
		{"Pillar Light Crimson", {1.00, 0.22, 0.18}},
		{"Pillar Light Emerald", {0.25, 1.00, 0.40}},
		{"Pillar Light Azure", {0.28, 0.45, 1.00}},
		{"Pillar Light Amber", {1.00, 0.75, 0.22}},
	}

	// Each pillar light sits outboard of its pillar, between it and the corner, so the pillar is
	// lit from behind and throws a shadow inward across the floor rather than being washed flat.
	PILLAR_LIGHT_SPREAD :: f32(1.3)
	PILLAR_LIGHT_HEIGHT :: f32(1.8)

	for position, i in pillars {
		addObject(
			&builder,
			fmt.tprintf("Pillar %v", i + 1),
			u32(Model.Cube),
			{position.x, 2, position.z},
			{1.1, 4, 1.1},
			u32(Tex.PlasterAlbedo),
			u32(Tex.PlasterNormal),
		)
		addObject(
			&builder,
			fmt.tprintf("Pillar Cap %v", i + 1),
			u32(Model.Cube),
			{position.x, 4.15, position.z},
			{1.5, 0.3, 1.5},
			u32(Tex.TileAlbedo),
			u32(Tex.TileNormal),
		)
		addLight(
			&builder,
			pillarLights[i].name,
			{
				position.x * PILLAR_LIGHT_SPREAD,
				PILLAR_LIGHT_HEIGHT,
				position.z * PILLAR_LIGHT_SPREAD,
			},
			pillarLights[i].colour,
			2600,
		)
	}

	addObject(&builder, "Plinth", u32(Model.Cube), {0, 0.4, 0}, {3, 0.8, 3}, u32(Tex.TileAlbedo), u32(Tex.TileNormal))
	addObject(&builder, "Monument", u32(Model.Torus), {0, 1.5, 0}, {2.4, 2.4, 2.4}, u32(Tex.PlasterAlbedo), u32(Tex.PlasterNormal))
	addObject(&builder, "Orb East", u32(Model.Sphere), {3.5, 0.8, -2}, {1.6, 1.6, 1.6}, u32(Tex.Checker), u32(Tex.BumpNormal))
	addObject(&builder, "Orb West", u32(Model.Sphere), {-3.5, 0.8, 2}, {1.6, 1.6, 1.6}, u32(Tex.Checker), u32(Tex.BumpNormal))

	// Deliberately dim and neutral: it reads the monument's shape without competing with the
	// pillar lights, which are what actually colour the courtyard.
	addLight(&builder, "Monument Key", {0, 3.6, 0}, {1.0, 1.0, 1.0}, 900)

	addCamera(&builder, "Courtyard", {-8, 6, -8}, {0, 1, 0})

	return saveSceneFile(opts, "environment", "Courtyard", 0.12, &builder)
}

generateStressAssets :: proc(opts: Options) -> bool {
	dir := fmt.tprintf("%s/%s", opts.projectDir, opts.generatedRel)

	meshes := [StressModel]Mesh {
		.DenseSphere = makeSphere(256, 512, 0.5, 8),
		.TiledPlane  = makePlane(1, 20, 40),
	}
	for model in StressModel {
		mesh := meshes[model]
		defer meshDelete(&mesh)
		entry := STRESS_MODEL_ASSETS[model]
		path := fmt.tprintf("%s%s.obj", dir, entry.file)
		if !writeOBJ(path, entry.name, &mesh) {
			return false
		}
		fmt.printfln("  %s  (%v vertices, %v triangles)", path, len(mesh.positions), len(mesh.indices) / 3)
		if !writeModelDescriptor(
			Asset {
				name = entry.name,
				descriptorPath = fmt.tprintf("%s/%s%s.model", opts.projectDir, opts.componentsRel, entry.file),
				assetPath = fmt.tprintf("%s%s.obj", opts.generatedRel, entry.file),
			},
		) {
			return false
		}
	}

	write :: proc(opts: Options, name, file: string, image: ^Image) -> bool {
		path := fmt.tprintf("%s/%s%s.png", opts.projectDir, opts.generatedRel, file)
		if !writePNG(path, image) {
			return false
		}
		fmt.printfln("  %s", path)
		return writeTextureDescriptor(
			Asset {
				name = name,
				descriptorPath = fmt.tprintf("%s/%s%s.texture", opts.projectDir, opts.componentsRel, file),
				assetPath = fmt.tprintf("%s%s.png", opts.generatedRel, file),
			},
		)
	}

	zonePlate := zonePlateImage(STRESS_ZONE_PLATE_SIZE)
	defer imageDelete(&zonePlate)
	if !write(opts, "Generated Zone Plate", "gen_zone_plate", &zonePlate) {
		return false
	}

	for variant in 0 ..< STRESS_VARIANTS {
		image := variantImage(STRESS_VARIANT_SIZE, variant, STRESS_VARIANTS)
		defer imageDelete(&image)
		if !write(opts, fmt.tprintf("Generated Variant %v", variant), fmt.tprintf("gen_variant_%02d", variant), &image) {
			return false
		}
	}
	return true
}

// Performance scene. Each group targets one cost the renderer currently pays in full, and
// -lights and -density scale them independently so frame time can be attributed by
// regenerating rather than by guesswork.
buildStressScene :: proc(opts: Options) -> bool {
	builder: Builder
	commonLists(opts, &builder)
	for model in StressModel {
		append(&builder.models, fmt.tprintf("%s%s.model", opts.componentsRel, STRESS_MODEL_ASSETS[model].file))
	}
	for file in KNIGHT_PARTS {
		append(&builder.models, fmt.tprintf("%s%s", opts.componentsRel, file))
	}
	append(&builder.textures, fmt.tprintf("%sgen_zone_plate.texture", opts.componentsRel))
	for variant in 0 ..< STRESS_VARIANTS {
		append(&builder.textures, fmt.tprintf("%sgen_variant_%02d.texture", opts.componentsRel, variant))
	}
	for file in KNIGHT_TEXTURES {
		append(&builder.textures, fmt.tprintf("%s%s", opts.componentsRel, file))
	}

	density := f32(opts.stressDensity) / 100
	scaled :: proc(base: int, density: f32) -> int {
		return max(1, int(f32(base) * density + 0.5))
	}
	side :: proc(base: int, density: f32) -> int {
		return max(1, int(f32(base) * math.sqrt(density) + 0.5))
	}
	centred :: proc(index, count: int, spacing: f32) -> f32 {
		return (f32(index) - f32(count - 1) * 0.5) * spacing
	}

	// The zone plate repeats forty times across the floor, so almost all of it is minified.
	addObject(&builder, "Floor", stressModel(.TiledPlane), {0, 0, 0}, {8, 1, 8}, ZONE_PLATE_TEX, u32(Tex.FlatNormal))

	// Coplanar with the floor: only depth precision decides which surface wins each pixel.
	addObject(&builder, "Z-Fight Patch", u32(Model.Plane), {20, 0, -55}, {0.5, 1, 0.5}, u32(Tex.BrickAlbedo), u32(Tex.BrickNormal))

	// Many instances of a 24 vertex mesh. Transform.slang dispatches over vertices and loops
	// over instances inside each invocation, so only 24 invocations run, each walking every
	// instance. Every crate reads one of 48 distinct 1024x1024 textures.
	crates := side(100, density)
	for i in 0 ..< crates * crates {
		x, z := i % crates, i / crates
		addObject(
			&builder,
			fmt.tprintf("Crate %v", i),
			u32(Model.Cube),
			{centred(x, crates, 0.5), 0.15, centred(z, crates, 0.5)},
			{0.3, 0.3, 0.3},
			variantTex(x * 7 + z * 13),
			u32(Tex.FlatNormal),
		)
	}

	// Mid-poly instances. Per-vertex transform storage and shadow triangles both scale with
	// vertices times instances, and nothing is culled.
	orbs := side(20, density)
	for i in 0 ..< orbs * orbs {
		x, z := i % orbs, i / orbs
		addObject(
			&builder,
			fmt.tprintf("Orb %v", i),
			u32(Model.Sphere),
			{-52 + centred(x, orbs, 2.2), 1, 20 + centred(z, orbs, 2.2)},
			{1.6, 1.6, 1.6},
			u32(Tex.Checker),
			u32(Tex.BumpNormal),
		)
	}

	// Skinned and animated, each carrying two bone attachments. Animation is evaluated per
	// object on the CPU every frame.
	knights := side(8, density)
	for i in 0 ..< knights * knights {
		x, z := i % knights, i / knights
		body := addObject(
			&builder,
			fmt.tprintf("Knight %v", i),
			knightModel(.Body),
			{48 + centred(x, knights, 3), 0, 15 + centred(z, knights, 3)},
			{1, 1, 1},
			KNIGHT_ALBEDO_TEX,
			KNIGHT_NORMAL_TEX,
			meshCount = KNIGHT_MESH_COUNT,
			animation = V.AnimationComponent {
				idx = 0,
				timer = f64(hashFloat(u32(i), 0, 5)) * 2,
				playing = true,
				end = {behavior = .Loop, nextIdx = -1},
			},
		)
		addObject(
			&builder,
			fmt.tprintf("Knight %v Helmet", i),
			knightModel(.Helmet),
			{0, 0, 0},
			{1, 1, 1},
			KNIGHT_ALBEDO_TEX,
			KNIGHT_NORMAL_TEX,
			attachment = {targetIdx = i32(body), bindpointIdx = KNIGHT_HEAD_BINDPOINT},
		)
		addObject(
			&builder,
			fmt.tprintf("Knight %v Sword", i),
			knightModel(.Sword),
			{0, 0, 0},
			{1, 1, 1},
			KNIGHT_ALBEDO_TEX,
			KNIGHT_NORMAL_TEX,
			attachment = {targetIdx = i32(body), bindpointIdx = KNIGHT_RIGHT_HAND_BINDPOINT},
		)
	}

	// A tall helix of tori behind the crates, throwing long shadows across the other groups.
	tori := scaled(100, density)
	for i in 0 ..< tori {
		angle := f32(i) * 0.45
		addObject(
			&builder,
			fmt.tprintf("Torus %v", i),
			u32(Model.Torus),
			{math.cos(angle) * 4, 1 + f32(i) * 0.35, 50 + math.sin(angle) * 4},
			{1.5, 1.5, 1.5},
			u32(Tex.TileAlbedo),
			u32(Tex.TileNormal),
			rotation = linalg.quaternion_angle_axis_f32(angle, V.Vec3{math.cos(angle), 0, math.sin(angle)}),
		)
	}

	// Panes facing the camera, listed far to near. Instances draw in list order, so each pane
	// is fully shaded before the next one covers it and early depth testing rejects nothing.
	panes := scaled(40, density)
	facing := linalg.quaternion_angle_axis_f32(-math.PI / 2, V.Vec3{1, 0, 0})
	for i in 0 ..< panes {
		addObject(
			&builder,
			fmt.tprintf("Pane %v", i),
			u32(Model.Plane),
			{-18, 4.2, -40 - f32(i) * 0.5},
			{0.4, 1, 0.4},
			u32(Tex.PlasterAlbedo),
			u32(Tex.PlasterNormal),
			rotation = facing,
		)
	}

	// Posts much thinner than a shadow map texel, so their shadows break up rather than
	// reading as lines.
	posts := scaled(200, density)
	for i in 0 ..< posts {
		addObject(
			&builder,
			fmt.tprintf("Post %v", i),
			u32(Model.Cube),
			{-40 + 80 * f32(i) / f32(max(posts - 1, 1)), 2.5, -30},
			{0.03, 5, 0.03},
			u32(Tex.Checker),
			u32(Tex.FlatNormal),
		)
	}

	// Hundreds of thousands of triangles at the far corner of the floor, with no level of
	// detail, drawn into every shadow view as well.
	addObject(&builder, "Dense Sphere", stressModel(.DenseSphere), {62, 4, 70}, {8, 8, 8}, u32(Tex.Checker), u32(Tex.BumpNormal))

	// High and far off, so each 512 texel cube face is stretched across the whole floor and
	// shadow edges stair-step visibly.
	addLight(&builder, "Sun", {-30, 60, -40}, {1.0, 0.95, 0.85}, 120000)

	// Every light renders all geometry into six views and takes twenty shadow samples per
	// shaded pixel whether or not it reaches anything. These contribute nothing at all.
	buried := (opts.stressLights - 1) / 4
	for i in 0 ..< buried {
		addLight(
			&builder,
			fmt.tprintf("Buried %v", i),
			{-60 + 120 * hashFloat(u32(i), 1, 11), -4, -60 + 120 * hashFloat(u32(i), 2, 11)},
			{1, 1, 1},
			5000,
		)
	}

	lamps := opts.stressLights - 1 - buried
	columns := max(1, int(math.ceil(math.sqrt(f32(lamps)))))
	for i in 0 ..< lamps {
		cx, cz := i % columns, i / columns
		addLight(
			&builder,
			fmt.tprintf("Lamp %v", i),
			{
				-70 + 140 * (f32(cx) + 0.5) / f32(columns),
				5 + 4 * hashFloat(u32(i), 3, 11),
				-70 + 140 * (f32(cz) + 0.5) / f32(columns),
			},
			0.35 + 0.65 * hueColour(f32(i) / f32(max(lamps, 1))),
			2500,
		)
	}

	addCamera(&builder, "Overview", {0, 16, -80}, {0, 2, 0}, far = 1000)

	return saveSceneFile(opts, "stress", "Stress", 0.05, &builder)
}


// ===[ Entry Point ]==========================================================

main :: proc() {
	opts, ok := parseOptions()
	if !ok {
		os.exit(1)
	}

	if !resolveProject(&opts) {
		os.exit(1)
	}

	for sub in ([?]string{opts.generatedRel, opts.componentsRel, opts.scenesRel}) {
		path := fmt.tprintf("%s/%s", opts.projectDir, sub)
		if !os.is_dir(path) {
			if err := os.make_directory_all(path); err != nil {
				fmt.eprintfln("Failed to create %q: %v", path, err)
				os.exit(1)
			}
		}
	}

	fmt.printfln("Meshes:")
	if !generateMeshes(opts) do os.exit(1)

	fmt.printfln("Textures (%vx%v):", opts.textureSize, opts.textureSize)
	if !generateTextures(opts) do os.exit(1)

	fmt.printfln("Descriptors:")
	if !generateDescriptors(opts) do os.exit(1)

	if opts.stress {
		fmt.printfln("Stress assets:")
		if !generateStressAssets(opts) do os.exit(1)
	}

	fmt.printfln("Scenes:")
	if opts.bench && !buildBenchScene(opts) do os.exit(1)
	if opts.environment && !buildEnvironmentScene(opts) do os.exit(1)
	if opts.stress && !buildStressScene(opts) do os.exit(1)

	free_all(context.temp_allocator)
	fmt.println("Done.")
}
