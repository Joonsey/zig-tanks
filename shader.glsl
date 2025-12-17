#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform sampler2D normal;

uniform vec2 mouse;
uniform float light_height = 0.7;

void main() {
    vec2 uv = fragTexCoord;

    vec4 color = texture(texture0, uv);

	vec2 m = mouse;
	m.y = 1 - m.y;
	m.x = 1 - m.x;
	vec2 light_dir = normalize(m - uv);

	vec3 n = texture(normal, uv).xyz * 2.0 - 1.0;

	float light = max(dot(n, vec3(light_dir, light_height)), 0.0);
	finalColor = vec4(color.rgb * clamp(light, 0.2, 1), 1);
	// finalColor = texture(normal, uv);
}
