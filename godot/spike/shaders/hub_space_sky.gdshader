shader_type sky;

/** Deep-space backdrop for the hub hangar exterior. */
uniform vec3 space_color : source_color = vec3(0.008, 0.012, 0.04);
uniform vec3 nebula_a : source_color = vec3(0.12, 0.05, 0.22);
uniform vec3 nebula_b : source_color = vec3(0.04, 0.1, 0.28);
uniform float star_density = 140.0;
uniform float star_brightness = 1.6;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = space_color;

	/* Soft nebulae */
	float n1 = hash13(floor(dir * 6.0 + vec3(2.1, 0.0, 0.7)));
	float n2 = hash13(floor(dir * 11.0 + vec3(0.3, 4.2, 1.1)));
	col += nebula_a * smoothstep(0.62, 1.0, n1) * 0.45;
	col += nebula_b * smoothstep(0.7, 1.0, n2) * 0.35;

	/* Milky-way-ish band */
	float band = exp(-pow(dir.y * 2.2, 2.0)) * (0.55 + 0.45 * hash13(dir * 4.0));
	col += vec3(0.18, 0.14, 0.32) * band * 0.12;

	/* Stars */
	vec3 cell = floor(dir * star_density);
	float h = hash13(cell);
	if (h > 0.965) {
		vec3 f = fract(dir * star_density) - 0.5;
		float d = length(f.xy);
		float twinkle = 0.55 + 0.45 * sin(TIME * (1.5 + h * 7.0) + h * 30.0);
		float s = smoothstep(0.09, 0.0, d) * star_brightness * twinkle;
		s *= (h - 0.965) / 0.035;
		col += vec3(s, s * 0.95, s * 1.05);
	}

	/* Brighter sparse stars */
	vec3 cell2 = floor(dir * (star_density * 0.45));
	float h2 = hash13(cell2 + 9.1);
	if (h2 > 0.988) {
		vec3 f2 = fract(dir * (star_density * 0.45)) - 0.5;
		float d2 = length(f2.xy);
		float s2 = smoothstep(0.12, 0.0, d2) * 2.2;
		col += vec3(s2);
	}

	COLOR = col;
}
