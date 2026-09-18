float3 rec709ToRec2020(float3 colour) {
	return float3(dot(colour, float3(0.6274040, 0.3292820, 0.0433136)),
								dot(colour, float3(0.0690970, 0.9195400, 0.0113612)),
								dot(colour, float3(0.0163916, 0.0880132, 0.8955950)));
}

float3 pqEncode(float3 nits) {
	const float m1 = 0.1593017578125;
	const float m2 = 78.84375;
	const float c1 = 0.8359375;
	const float c2 = 18.8515625;
	const float c3 = 18.6875;

	const float3 y = clamp(nits / 10000.0, 0.0, 1.0);
	const float3 ym1 = pow(y, float3(m1));
	return pow((c1 + c2 * ym1) / (1.0 + c3 * ym1), float3(m2));
}
