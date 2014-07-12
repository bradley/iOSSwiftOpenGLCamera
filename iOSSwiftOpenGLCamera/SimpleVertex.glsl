attribute vec4 Position;

attribute vec2 TexCoordIn;
varying vec2 CameraTextureCoord;

void main(void) {
	gl_Position = Position;
	CameraTextureCoord = TexCoordIn;
}
