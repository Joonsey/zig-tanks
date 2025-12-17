#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform sampler2D normal;
uniform sampler2D height;

uniform vec2 mouse;
uniform float light_height = 0.4;

uniform int debug_mode = 0;

void main() {
    vec2 uv = fragTexCoord;
    vec4 color = texture(texture0, uv);

	vec2 m = mouse;
	m.y = 1 - m.y;

    vec3 to_light = vec3(m, light_height) - vec3(uv, texture(height, uv).r);
    vec3 light_dir = normalize(to_light);

    vec3 n = texture(normal, uv).xyz * 2.0 - 1.0;

    float l = max(dot(n, light_dir), 0.0);

    finalColor = vec4(color.rgb * clamp(l / (length(to_light) / 0.2), 0.1, 1.0), color.a);

	if (debug_mode == 1) finalColor = vec4(texture(normal, uv).rgb, 1);
	if (debug_mode == 2) finalColor = vec4(texture(height, uv).rgb, 1);
	if (debug_mode == 3) finalColor = vec4(texture(texture0, uv).rgb, 1);
}

