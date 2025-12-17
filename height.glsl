#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;

uniform float height;

void main() {
    vec2 uv = fragTexCoord;
    vec4 color = texture(texture0, uv);
	if (color.a < 0.01) discard;

    finalColor = vec4(vec3(height / 255), color.a);
}

