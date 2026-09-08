shader_type spatial;
render_mode ambient_light_disabled, blend_add, depth_draw_opaque, cull_disabled;

uniform sampler2D albedo_emission;
instance uniform float alpha_mod: hint_range(0.0, 1.0, 0.1) = 1.f;

void fragment() {
	// Called for every pixel the material is visible on.
	vec4 color = texture(albedo_emission, UV);
	ALPHA = color.a * alpha_mod;
	ALBEDO = color.rgb;
	EMISSION = color.rgb * 2.0;
}
