shader_type spatial;
render_mode cull_disabled,unshaded,ambient_light_disabled;
uniform sampler2DArray sprites_array : source_color;

// index of sprite within sprites_array
instance uniform int sprite_index;

void vertex() {
	vec3 local_up = MODEL_MATRIX[1].xyz;
	//cross of:
	//	local_transform.basis.y     and    to_world(view_space.forward)
	//normalized
	//(represents right direction)
	vec4 ax = vec4(normalize(cross(local_up, INV_VIEW_MATRIX[2].xyz)), 0.0);
	//local_transform.basis.y
	//(represents up direction)
	vec4 ay = vec4(local_up.xyz, 0.0);
	//cross of:
	//	to_world(view_space.right)    and    local_transform.basis.y
	//(represents forward direction)
	vec4 az = vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, local_up)), 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(ax, ay, az, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec3 uv_array = vec3(UV, float(sprite_index));
	vec4 albedo_tex = texture(sprites_array, uv_array);
	ALBEDO = albedo_tex.rgb;
	ALPHA = albedo_tex.a;
}
