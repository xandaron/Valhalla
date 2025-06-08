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

## Getting Started

### Prerequisites

- [Odin](https://odin-lang.org/docs/install/) programming language
- [VulkanSDK](https://vulkan.lunarg.com/) (recommended for development)

#### Linux

You'll also need to install [Assimp](https://github.com/assimp/assimp/releases/tag/v6.0.1) as a shared lib for linux builds.

### Setup

Run the following script to clone the repository, build the project and run the exe:

```sh
git clone https://github.com/xandaron/valhalla.git
cd valhalla
odin build . -out:bin/build.exe
./bin/build.exe
```

> **Note:** On Linux, you will need to install the GLFW 3.4+ library separately. It's important you install GLFW 3.4 or later as anything earlier will cause crashes.

## Demo

![RGB Bunny Box](demo/RGB_Bunny_Box.gif)

*The RGB Bunny Box showcases a rendered scene of the Stanford bunny inside a box, lit by Red, Green, and Blue point lights rotating around the Y-axis.*

![GUI Demo](demo/GUI_Demo.gif)

*A demo of imgui in action.*

![Rigged Zombie](demo/Zombie_Walking.gif)

*A demo of a rigged 3D model and animation.*

![CMY Bunny](demo/CMY_Bunny.gif)

*The CMY Bunny demonstrates a rendered scene of the Stanford bunny illuminated by rotating Cyan, Magenta, and Yellow point lights around the Z-axis.*

## Contributing

At this time, I am not accepting contributions from others. However, you are free to fork the repository if you would like to make your own modifications or improvements.

## License

This project is licensed under the MIT License.
