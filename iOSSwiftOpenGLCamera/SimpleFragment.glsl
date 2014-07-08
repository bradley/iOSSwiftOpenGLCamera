varying lowp vec4 DestinationColor;

varying lowp vec2 TexCoordOut;
uniform sampler2D Texture;

void main(void) {
	
	if (1==1) {
		gl_FragColor = DestinationColor * texture2D(Texture, TexCoordOut);
	}
	else {
		gl_FragColor = DestinationColor;
	}
	
}