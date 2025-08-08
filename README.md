# Valhalla Graphics Engine

Valhalla is a graphics engine designed for rendering 3D scenes. The engine is now structured as a reusable Odin package that can be imported into other projects. A demo program is included to showcase how to use the package.

## Features

- Support for rigged 3D models and animations
- Support for multiple light sources
- Custom shaders
- Shadow mapping
- Real-time rendering
- Cross-platform support (Windows, Linux)
- Hot-reloadable shaders

## Project Structure

- `valhalla/` &mdash; The core graphics engine package (importable in Odin projects)
- `demo/` &mdash; Example program demonstrating usage of the Valhalla package

## Getting Started

### Prerequisites

- [Odin](https://odin-lang.org/docs/install/) programming language
- [VulkanSDK](https://vulkan.lunarg.com/) (recommended for development)

#### Linux

- Install [Assimp](https://github.com/assimp/assimp/releases/tag/v6.0.1) as a shared library.
- Install GLFW 3.4+ (older versions may cause crashes).

### Setup

Clone the repository and build the demo program:

```sh
git clone https://github.com/xandaron/valhalla.git
cd valhalla/demo
odin build . -out:demo.exe
./demo.exe
```

> **Note:** On Linux, you will need to install the GLFW 3.4+ library separately. Anything earlier will cause crashes.

### Using the Valhalla Package in Your Project

You can import the graphics engine into your own Odin projects:

```odin
import valhalla "path/to/valhalla"
```

Refer to the `demo/` directory for an example of how to initialize and use the engine.

## Demo

![Rigged Zombie](demo/Zombie.gif)

*A demo of a rigged 3D model and animation.*

![Shader Demo](demo/shader_demo.gif)

*A demo of reloading shaders at runtime.*

![GUI Demo](demo/GUI_Demo.gif)

*A demo of imgui in action.*

## License

This project is licensed under the MIT License.
