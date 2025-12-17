#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform float rotation;


void main() {
    // decode
	vec4 pixel = texture(texture0, fragTexCoord);
    vec3 n = pixel.xyz * 2.0 - 1.0;

    // rotate XY by rotation (Z unchanged)
    float cs = cos(rotation);
    float sn = sin(rotation);
    vec3 n_rot = vec3(
        n.x * cs - n.y * sn,
        n.x * sn + n.y * cs,
        n.z
    );

    // IMPORTANT: re-normalize after rotation (fixes filtering/interp artifacts)
    n_rot = normalize(n_rot);

    // encode back to 0..1
    n_rot = n_rot * 0.5 + 0.5;

    // clamp just to be safe
    finalColor = vec4(clamp(n_rot, 0.0, 1.0), pixel.a);
}
