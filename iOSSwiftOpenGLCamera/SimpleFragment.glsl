precision mediump float;

uniform sampler2D Texture;
uniform float time;
uniform float showShader;
varying vec2 CameraTextureCoord;

void main() {
	if (showShader > 0.5) {
		vec2 offset = 0.5 * vec2( cos(0.0), sin(0.0));
		vec4 cr = texture2D(Texture, CameraTextureCoord + offset);
		vec4 cga = texture2D(Texture, CameraTextureCoord);
		vec4 cb = texture2D(Texture, CameraTextureCoord - offset);
		gl_FragColor = vec4(cr.r, cga.g, cb.b, cga.a);
	}
	else {
		gl_FragColor = texture2D(Texture, CameraTextureCoord);
	}
}