#version 460

layout(binding = 0) readonly uniform UniformBuffer {
	mat4 view;
	mat4 projection;
	mat4 viewProjection;
    uint lightCount;
} uniformBuffer;

struct Light {
    vec4 position;
    vec4 colourIntensity;
    float near;
    float far;
};

layout(binding = 2) readonly buffer LightBuffer {
    Light[] lights;
} lightBuffer;

layout(binding = 4) uniform sampler2DArray albedoArray;
layout(binding = 5) uniform sampler2DArray normalArray;
layout(binding = 6) uniform samplerCubeArray shadowMap;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec3 inNormal;

layout(location = 0) out vec4 outColour;

layout(push_constant) uniform PushConstants {
	float ambientLight;
    uint vertexOffset;
    uint albedoTextureIndex;
    uint normalTextureIndex;
} pushConstant;

#define EPSILON 0.015 // Shadows are noisy without this

void main() {
    vec3 cumulativeColour = vec3(0.0);
    const vec3 albedo = pow(texture(albedoArray, vec3(inUV, pushConstant.albedoTextureIndex)).xyz, vec3(1.0 / 2.2));
    const vec3 normal = outerProduct(inNormal, vec3(0.0, 0.0, 1.0)) * (texture(normalArray, vec3(inUV, pushConstant.normalTextureIndex)).xyz - 0.5) * 2.0;

    for (uint index = 0; index < uniformBuffer.lightCount; index++) {
        #define light lightBuffer.lights[index]

        const vec3 relativePosition = light.position.xyz - inPosition;
        const float lightSquaredDistance = dot(relativePosition, relativePosition);
        const float lightDistance = sqrt(lightSquaredDistance);
        const vec3 negativeLightDirection = relativePosition / lightDistance;

        #define diskRadius 0.02 // The engine has a scale problem. I need to fix the scaling of objects and the world and then increase this value
        #define SAMPLES 20
        vec3 sampleOffsetDirections[SAMPLES] = vec3[](
            vec3(1, 0, 0), vec3(-1, 0, 0),
            vec3(0, 1, 0), vec3(0, -1, 0),
            vec3(0, 0, 1), vec3(0, 0, -1),
            vec3(1, 1, 0), vec3(-1, -1, 0),
            vec3(1, -1, 0), vec3(-1, 1, 0),
            vec3(1, 0, 1), vec3(-1, 0, -1),
            vec3(1, 0, -1), vec3(-1, 0, 1),
            vec3(0, 1, 1), vec3(0, -1, -1),
            vec3(0, 1, -1), vec3(0, -1, 1),
            vec3(1, 1, 1), vec3(-1, -1, -1)
        );

        #define BIAS 0.015

        float shadow = 0.0;

        for (int i = 0; i < SAMPLES; ++i) {
            vec3 offsetDir = diskRadius * sampleOffsetDirections[i] - relativePosition;
            float sampleDepth = texture(shadowMap, vec4(offsetDir, float(index))).r;

            if (lightSquaredDistance < sampleDepth + BIAS) shadow += 1.0;
        }

        shadow /= float(SAMPLES);

        const float lambertainCoefficient = clamp(dot(normal, negativeLightDirection), 0.0, 1.0);
        // Should be devided by lightSquaredDistance but the light drops off too quickly and looks too dark
        cumulativeColour += albedo * shadow * lambertainCoefficient * light.colourIntensity.xyz / lightDistance;
    }

    cumulativeColour = max(cumulativeColour, pushConstant.ambientLight * albedo);
    outColour =  vec4(cumulativeColour, 1.0);
}