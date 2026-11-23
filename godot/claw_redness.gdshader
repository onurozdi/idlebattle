shader_type canvas_item;

uniform vec2 atlas_origin;
uniform vec2 sprite_scale;
uniform vec2 contact_points[4];
uniform int contact_count = 0;

void fragment() {
	vec2 local_pixel = floor((UV / TEXTURE_PIXEL_SIZE - atlas_origin) * sprite_scale) + vec2(0.5);
	float red_area = 0.0;
	float edge = sin(local_pixel.x * 1.7 + local_pixel.y * 0.71) * 0.07;
	for (int i = 0; i < contact_count; i++) {
		vec2 offset = (local_pixel - contact_points[i]) / vec2(9.0, 6.5);
		red_area = max(red_area, 1.0 - smoothstep(0.51, 1.08, length(offset) + edge));
	}
	vec3 blood_tint = vec3(0.64, 0.085, 0.10) * 0.82 + COLOR.rgb * 0.29;
	COLOR.rgb = mix(COLOR.rgb, blood_tint, red_area * 0.88);
}
