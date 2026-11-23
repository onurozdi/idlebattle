shader_type canvas_item;

uniform vec2 atlas_origin;
uniform vec2 sprite_scale;
// Sprite-space contact and swipe direction.
uniform vec4 contacts[4];
uniform int contact_count = 0;

void fragment() {
	vec2 local_pixel = floor((UV / TEXTURE_PIXEL_SIZE - atlas_origin) * sprite_scale) + vec2(0.5);
	float scratch = 0.0;
	float highlight = 0.0;
	for (int i = 0; i < contact_count; i++) {
		vec2 direction = contacts[i].zw;
		vec2 offset = local_pixel - contacts[i].xy;
		float along = dot(offset, direction);
		float across = dot(offset, vec2(-direction.y, direction.x));
		for (int claw = -1; claw <= 1; claw++) {
			float line = float(claw);
			float length_mask = 1.0 - smoothstep(4.0, 7.0 - abs(line), abs(along - line * 0.9));
			float edge = across - line * 2.9 - along * along * 0.016;
			scratch = max(scratch, length_mask * (1.0 - smoothstep(0.55, 1.08, abs(edge))));
			highlight = max(highlight, length_mask * (1.0 - smoothstep(0.12, 0.6, abs(edge + 0.27))));
		}
	}
	vec3 cut = mix(vec3(0.61, 0.045, 0.07), vec3(0.94, 0.24, 0.23), highlight);
	COLOR.rgb = mix(COLOR.rgb, cut, scratch);
}
