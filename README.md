# Valhalla Graphics Engine

Valhalla is a 3D graphics rendering demo showcasing modern graphics techniques and real-time rendering capabilities. This project serves as a demonstration of graphics programming concepts and rendering features.

## Why Valhalla?

Valhalla is an active work in progress. The project is designed to demonstrate various graphics programming techniques and serves as a learning platform for 3D rendering concepts. Its implementation showcases real-time rendering features that could be adapted for both games and visualization tools.

## Features

- Rigged 3D model and animation support
- Multiple light sources
- Custom shaders
- Shadow mapping
- Real-time rendering
- Cross-platform (Windows, Linux)
- Hot-reloadable shaders

## Project Structure

- `src/` &mdash; Core graphics engine implementation
- `shaders/` &mdash; Shader files for rendering
- `assets/` &mdash; Assets used by the demo (models, textures)

## Getting Started

### Prerequisites

- [Odin](https://odin-lang.org/docs/install/) programming language
- [VulkanSDK](https://vulkan.lunarg.com/) (recommended for development)

### Setup

#### Linux

- Install [Assimp](https://github.com/assimp/assimp/releases/tag/v6.0.1) as a shared library.
- Install GLFW 3.4+ (older versions may cause crashes).

Clone the repository and build the demo program:

```sh
git clone https://github.com/xandaron/valhalla.git
cd valhalla/demo
odin build src -out:bin/valhalla.exe
./bin/valhalla.exe ./demo
```

> **Note:** On Linux, you will need to install the GLFW 3.4+ library separately. Anything earlier will cause crashes.

## Roadmap

Planned features and improvements:

- Improved omni-directional light shadow mapping
- Directional light support
- Raytracing
- Additional rendering techniques and optimizations

## License

This project is licensed under the MIT License.
