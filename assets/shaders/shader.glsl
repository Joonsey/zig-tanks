#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform sampler2D normal;

uniform int debug_mode = 0;

struct Light {
    vec2 position;
    float height;
    float radius;
    vec3 color;
};

#define MAX_LIGHTS 45

uniform int light_count;
uniform Light lights[MAX_LIGHTS];
uniform float ambiance = 0.2;


void main() {
    vec2 uv = fragTexCoord;
    vec4 color = texture(texture0, uv);

	vec3 lighting = vec3(0.0);
	vec3 n = texture(normal, uv).xyz * 2.0 - 1.0;

	for (int i = 0; i < light_count; i++) {
		vec2 lp = lights[i].position;

		// this seems like it should work but it randomly does???
		// normal we would invert the y position here also but the x seemed a to be flipped
		// so i changed the direction formula and this is magically just better

		lp.y = 1 - lp.y;
		vec3 to_light =  vec3(uv, 0) - vec3(lp, lights[i].height);
	    vec3 light_dir = normalize(vec3(to_light.x, -to_light.y, -to_light.z));

		float ndotl = max(dot(n, light_dir), 0.0);

		float attenuation = clamp(ndotl, 0.0, 1.0);

		lighting += lights[i].color * attenuation / (length(to_light) / lights[i].radius) * (texture(normal, uv).a);
	}


	finalColor = vec4(color.rgb * clamp(lighting, ambiance, 1.0), color.a);
	if (debug_mode == 1) finalColor = vec4(texture(normal, uv).rgb, 1);
	if (debug_mode == 3) finalColor = vec4(texture(texture0, uv).rgb, 1);
}

