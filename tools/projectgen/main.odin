package ProjectGen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import refdisk "../../ref-disk"
import V "../../src"

Options :: struct {
	target:         string,
	name:           string,
	scenesPath:     string,
	componentsPath: string,
	assetsPath:     string,
	shadersPath:    string,
	root:           string,
	startupScene:   string,
	defaultModel:   string,
	defaultAlbedo:  string,
	defaultNormal:  string,
	makeDirs:       bool,
	force:          bool,
}

PROJECT_EXTENSION :: ".project"

usage :: proc() {
	fmt.println("projectgen <directory or project file> [options]")
	fmt.println("  -name:<name>            project name, defaults to the directory name")
	fmt.println("  -root:<dir>             project root relative to the file, defaults to .")
	fmt.println("  -scenes:<dir>           defaults to ./scenes/")
	fmt.println("  -components:<dir>       defaults to ./components/")
	fmt.println("  -assets:<dir>           defaults to ./assets/")
	fmt.println("  -shaders:<dir>          defaults to ./shaders/")
	fmt.println("  -startup:<scene>        scene the engine opens on launch")
	fmt.println("  -default-model:<path>   model a new scene is seeded with")
	fmt.println("  -default-albedo:<path>  albedo a new scene is seeded with")
	fmt.println("  -default-normal:<path>  normal map a new scene is seeded with")
	fmt.println("  -no-dirs                do not create the declared directories")
	fmt.println("  -force                  overwrite an existing project file")
	fmt.println("  -help")
}

parseOptions :: proc() -> (opts: Options, ok: bool) {
	opts = Options {
		scenesPath     = "./scenes/",
		componentsPath = "./components/",
		assetsPath     = "./assets/",
		shadersPath    = "./shaders/",
		root           = ".",
		makeDirs       = true,
	}

	value :: proc(arg, prefix: string) -> (string, bool) {
		if !strings.has_prefix(arg, prefix) {
			return "", false
		}
		return arg[len(prefix):], true
	}

	positional := false
	for arg in os.args[1:] {
		if arg == "-help" || arg == "--help" {
			usage()
			return opts, false
		}
		if arg == "-no-dirs" {
			opts.makeDirs = false
			continue
		}
		if arg == "-force" {
			opts.force = true
			continue
		}
		if v, found := value(arg, "-name:"); found {opts.name = v; continue}
		if v, found := value(arg, "-root:"); found {opts.root = v; continue}
		if v, found := value(arg, "-scenes:"); found {opts.scenesPath = v; continue}
		if v, found := value(arg, "-components:"); found {opts.componentsPath = v; continue}
		if v, found := value(arg, "-assets:"); found {opts.assetsPath = v; continue}
		if v, found := value(arg, "-shaders:"); found {opts.shadersPath = v; continue}
		if v, found := value(arg, "-startup:"); found {opts.startupScene = v; continue}
		if v, found := value(arg, "-default-model:"); found {opts.defaultModel = v; continue}
		if v, found := value(arg, "-default-albedo:"); found {opts.defaultAlbedo = v; continue}
		if v, found := value(arg, "-default-normal:"); found {opts.defaultNormal = v; continue}

		if strings.has_prefix(arg, "-") {
			fmt.eprintfln("Unknown option %q.", arg)
			return opts, false
		}
		if positional {
			fmt.eprintfln("Unexpected argument %q.", arg)
			return opts, false
		}
		opts.target = arg
		positional = true
	}

	if opts.target == "" {
		usage()
		return opts, false
	}
	return opts, true
}

// The target may be the project file itself or the directory to put one in, because both are
// natural things to type.
resolveTarget :: proc(opts: ^Options) -> (projectFile: string, projectDir: string) {
	if filepath.ext(opts.target) == PROJECT_EXTENSION {
		projectFile = opts.target
		projectDir = filepath.dir(projectFile)
	} else {
		projectDir = strings.trim_right(opts.target, "/\\")
		name := opts.name
		if name == "" {
			name = filepath.base(projectDir)
		}
		projectFile = fmt.tprintf("%s/%s%s", projectDir, name, PROJECT_EXTENSION)
	}

	if opts.name == "" {
		opts.name = filepath.base(filepath.stem(projectFile))
	}
	return projectFile, projectDir
}

main :: proc() {
	opts, ok := parseOptions()
	if !ok {
		os.exit(1)
	}

	projectFile, projectDir := resolveTarget(&opts)

	if os.exists(projectFile) && !opts.force {
		fmt.eprintfln("%q already exists. Pass -force to overwrite it.", projectFile)
		os.exit(1)
	}

	if !os.is_dir(projectDir) {
		if err := os.make_directory_all(projectDir); err != nil {
			fmt.eprintfln("Failed to create %q: %v", projectDir, err)
			os.exit(1)
		}
	}

	if opts.makeDirs {
		for sub in ([?]string{opts.scenesPath, opts.componentsPath, opts.assetsPath, opts.shadersPath}) {
			path := fmt.tprintf("%s/%s", projectDir, sub)
			if os.is_dir(path) {
				continue
			}
			if err := os.make_directory_all(path); err != nil {
				fmt.eprintfln("Failed to create %q: %v", path, err)
				os.exit(1)
			}
			fmt.printfln("  created %s", path)
		}
	}

	project := V.ProjectData {
		version        = V.PROJECT_FORMAT_VERSION,
		name           = opts.name,
		root           = opts.root,
		scenesPath     = opts.scenesPath,
		componentsPath = opts.componentsPath,
		assetsPath     = opts.assetsPath,
		shadersPath    = opts.shadersPath,
		startupScene   = opts.startupScene,
		defaultModel   = opts.defaultModel,
		defaultAlbedo  = opts.defaultAlbedo,
		defaultNormal  = opts.defaultNormal,
	}

	file, err := os.open(projectFile, {.Write, .Create, .Trunc})
	if err != nil {
		fmt.eprintfln("Failed to write %q: %v", projectFile, err)
		os.exit(1)
	}
	refdisk.save(file, project)
	os.close(file)

	fmt.printfln("  wrote %s (format version %v)", projectFile, V.PROJECT_FORMAT_VERSION)
	if opts.startupScene == "" {
		fmt.println()
		fmt.println("No startup scene set. The engine needs one, either from -startup: or as its")
		fmt.println("second argument:  valhalla <project file> <scene>")
	}
}
