[[vk::binding(0, 1)]]
Sampler2DArray albedoArray;

[[vk::binding(1, 1)]]
Sampler2DArray normalArray;

[[vk::binding(2, 1)]]
SamplerCubeArrayShadow shadowMap;

[[vk::binding(3, 1)]]
Sampler2D sceneDepth;

[[vk::binding(4, 1)]]
RWTexture2D renderedImage;

[[vk::binding(5, 1)]]
RWTexture2D processedImage;
