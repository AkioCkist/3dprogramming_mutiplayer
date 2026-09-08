shader_type canvas_item;
uniform sampler2DArray sprite_array: source_color;
instance uniform int sprite_index = 0;

void fragment() {
	vec3 texture_uv = vec3(UV, float(sprite_index));
	COLOR = texture(sprite_array, texture_uv);
}
