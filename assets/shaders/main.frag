#version 460

// glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS)

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
layout(location = 3) in float inAlbedoIndex;
layout(location = 4) in float inNormalIndex;

layout(location = 0) out vec4 outColour;

layout(push_constant) uniform PushConstants {
    uint vertexOffset;
	float ambientLight;
} pushConstant;

#define EPSILON 0.0015 // Shadows are noisy without this

void main() {
    vec3 cumulativeColour = vec3(0.0);
    vec3 albedo = texture(albedoArray, vec3(inUV, inAlbedoIndex)).xyz;
    albedo = pow(albedo, vec3(1 / 2.2));
    vec3 normal = outerProduct(inNormal, vec3(0.0, 0.0, 1.0)) * (texture(normalArray, vec3(inUV, inNormalIndex)).xyz - 0.5) * 2.0;

    for (uint index = 0; index < uniformBuffer.lightCount; index++) {
        #define light lightBuffer.lights[index]

        vec3 relativePosition = light.position.xyz - inPosition;
        float lightSquaredDistance = dot(relativePosition, relativePosition);

        float lightDistance = sqrt(lightSquaredDistance);
        vec3 negativeLightDirection = normalize(relativePosition);
        float lambertainCoefficient = clamp(dot(normal, negativeLightDirection), 0.0, 1.0);

        float depth = texture(shadowMap, vec4(-relativePosition, float(index))).r;
        float shadow = (lightDistance <= depth + EPSILON) ? 1.0 : 0.0;

        cumulativeColour += albedo * shadow * lambertainCoefficient * light.colourIntensity.xyz / lightSquaredDistance;
    }

    cumulativeColour = max(cumulativeColour, albedo * pushConstant.ambientLight);
    outColour =  vec4(cumulativeColour, 1.0);
}