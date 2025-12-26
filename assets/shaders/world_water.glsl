#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform int u_tex_height;
uniform int u_tex_width;


uniform float u_camera_rotation;
uniform float u_camera_offset_x;
uniform float u_camera_offset_y;

uniform float u_camera_screen_offset_x;
uniform float u_camera_screen_offset_y;

uniform float u_time;

const int STACK_HEIGHT = 8; // number of vertical samples for 3d effect

// weird hashing magic
float hash1(float n) {return fract(sin(n)*43758.77453); }
vec2 hash2(vec2 p) {p = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)) ); return fract(sin(p)*43758.5453); }

float voronoi(in vec2 x, float w, float offset, float time) {
    vec2 n = floor(x);
    vec2 f = fract(x);

    float m = 8.0;
	for(int j = -2; j <= 2; j++)
		for(int i = -2; i <= 2; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g);

			// animate
			o = offset + 0.3*sin(time + 6.2831*o + x);

			// distance to cell
			float d = length(g - f + o);

			float h = clamp(0.5 + 0.5 * (m - d) / w, 0.0, 1.0 );
			m = mix(m, d, h) - h * (1.0 - h) * w;
    }
	return m;
}

bool is_black(vec4 color) {
    return color.r == 0.0 && color.g == 0.0 && color.b == 0.0;
}

bool is_magenta(vec4 color) {
    return color.r == 1.0 && color.g == 0.0 && color.b == 1.0;
}

float chevron(float x) {
	return abs(fract(x) - 0.5);
}

void main() {
    vec2 uv = fragTexCoord;
    vec4 color = texture(texture0, uv);
	if (is_black(color)) {
		bool found = false;
		if (uv.y * u_tex_height < (u_tex_height)) {
			for (int i = 1; i <= STACK_HEIGHT; i++) {
				vec2 sample_uv = uv + vec2(0.0, float(i) / float(u_tex_height));
				if (sample_uv.y > 1) break;
				vec4 sample_color = texture(texture0, sample_uv);

				if (!is_black(sample_color)) {
					color = sample_color * 0.9;
					found = true;
					break;
				}
			}
		}

		if (!found) {
			vec2 screen_center = vec2(u_camera_screen_offset_x, u_camera_screen_offset_y);
			vec2 world_position = (uv * vec2(u_tex_width, u_tex_height)) - vec2(-u_camera_offset_x, u_camera_offset_y);

			float angle = -u_camera_rotation;
			float cos_a = cos(angle);
			float sin_a = sin(angle);

			world_position = world_position - screen_center;
			vec2 rotated = vec2(
				cos_a * world_position.x - sin_a * world_position.y,
				sin_a * world_position.x + cos_a * world_position.y
			);
			rotated = rotated + screen_center;

			vec2 rotated_camera_offset = vec2(
				cos_a * u_camera_offset_x - sin_a * -u_camera_offset_y,
				sin_a * u_camera_offset_x + cos_a * -u_camera_offset_y
			);

			// camera representation of world position, with respect to rotation
			vec2 rotated_world_position = rotated - rotated_camera_offset - vec2(-u_camera_offset_x, u_camera_offset_y);

			float pixel_size = 0.03;
			uv = rotated_world_position * .035;
			uv = floor(uv  / pixel_size) * pixel_size;

			// colors
			vec4 a = vec4(0.114,0.635,0.847,1.0);
			vec4 b = vec4(1.000,1.000,1.000,1.0);
			vec4 c = a * 0.8; // darkens the a color

			float vNoise = voronoi(uv, 0.001, 0.5, u_time);
			float sNoise = voronoi(uv, 0.4, 0.5, u_time);
			float fVoronoi = smoothstep(0.0, 0.01, vNoise-sNoise-0.055);

			// stepping one step down below, to draw the 'shadow'
			uv.x -= sin_a * .1;
			uv.y += cos_a * .1;
			float vNoise2 = voronoi(uv, 0.001, 0.5, u_time);
			float sNoise2 = voronoi(uv, 0.4, 0.5, u_time);
			float offsetVoronoi = smoothstep(0.0, 0.01, vNoise2-sNoise2-0.055);

			vec4 bgColor2 = mix(a, c, offsetVoronoi);

			color = vec4(mix(bgColor2, b, fVoronoi));
		}
    }

    finalColor = color;
}

