#version 460

layout(location = 0) in float inColour;

layout(location = 0) out float outColour;

void main() {
    outColour = inColour;
}