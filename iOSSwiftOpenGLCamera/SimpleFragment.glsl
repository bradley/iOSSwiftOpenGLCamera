//varying lowp vec4 DestinationColor;
precision mediump float;


varying lowp vec2 CameraTextureCoord;
uniform sampler2D Texture;

void main(void) {
	//vec4 camera = texture2D(Texture, CameraTextureCoord);
	//float textel = texture2D(Texture, CameraTextureCoord).r;
	//gl_FragColor = camera;//texture2D(Texture, CameraTextureCoord);
	
	vec2 p = CameraTextureCoord;
	vec4 color = texture2D(Texture, p);
	color.rgb = 1.0 - color.rgb;
	gl_FragColor = color;
}