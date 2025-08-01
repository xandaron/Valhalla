# Valhalla Graphics Engine

Valhalla is a graphics engine designed for rendering 3D scenes with a focus on non-photorealistic rendering techniques. This project aims to serve as the renderer for a future game engine.

## Features

- Support for many model file formats via assimp
- Support for rigged 3D models and animations
- Support for multiple light sources
- Custom shaders
- Shadow mapping
- Real-time rendering
- Cross-platform support (Windows, Linux)
- Hot-reloadable shaders

## Getting Started

### Prerequisites

- [Odin](https://odin-lang.org/docs/install/) programming language
- [VulkanSDK](https://vulkan.lunarg.com/) (recommended for development)

#### Linux

- Install [Assimp](https://github.com/assimp/assimp/releases/tag/v6.0.1) as a shared library.
- Install GLFW 3.4+ (older versions may cause crashes).

### Setup

Run the following script to clone the repository, build the project, and run the executable:

```sh
git clone https://github.com/xandaron/valhalla.git
cd valhalla
odin build . -out:bin/Valhalla.exe
./bin/Valhalla.exe
```

> **Note:** On Linux, you will need to install the GLFW 3.4+ library separately. Anything earlier will cause crashes.

## Demo

![Rigged Zombie](demo/Zombie.gif)

*A demo of a rigged 3D model and animation.*

![Shader Demo](demo/shader_demo.gif)

*A demo of reloading shaders at runtime.*

![GUI Demo](demo/GUI_Demo.gif)

*A demo of imgui in action.*

## License

This project is licensed under the MIT License.
