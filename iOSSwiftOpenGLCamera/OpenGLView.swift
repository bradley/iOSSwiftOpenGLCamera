//
//  OpenGLView.swift
//  iOSSwiftOpenGLCamera
//
//  Created by Bradley Griffith on 7/1/14.
//  Copyright (c) 2014 Bradley Griffith. All rights reserved.
//

import Foundation
import UIKit
import QuartzCore
import OpenGLES
import GLKit
import CoreMedia
import AVFoundation


struct Vertex {
	var Position: (CFloat, CFloat, CFloat)
	var Color: (CFloat, CFloat, CFloat, CFloat)
	var TexCoord: (CFloat, CFloat)
}

var Vertices: (Vertex, Vertex, Vertex, Vertex) = (
	Vertex(Position: (1, -1, 0) , Color: (1, 0, 0, 1), TexCoord: (1, 0)),
	Vertex(Position: (1, 1, 0)  , Color: (0, 1, 0, 1), TexCoord: (1, 1)),
	Vertex(Position: (-1, 1, 0) , Color: (0, 0, 1, 1), TexCoord: (0, 1)),
	Vertex(Position: (-1, -1, 0), Color: (0, 0, 0, 1), TexCoord: (0, 0))
)

var Indices: (GLubyte, GLubyte, GLubyte, GLubyte, GLubyte, GLubyte) = (
	0, 1, 2,
	2, 3, 0
)


class OpenGLView: UIView {
	
	var eaglLayer: CAEAGLLayer!
	var context: EAGLContext!
	var colorRenderBuffer: GLuint = GLuint()
	var positionSlot: GLuint = GLuint()
	var colorSlot: GLuint = GLuint()
	var texCoordSlot: GLuint = GLuint()
	var textureUniform: GLuint = GLuint()
	var indexBuffer: GLuint = GLuint()
	var vertexBuffer: GLuint = GLuint()
	
	var unmanagedVideoTexture: Unmanaged<CVOpenGLESTexture>?
	var videoTexture: CVOpenGLESTextureRef?
	var videoTextureID: GLuint = GLuint()
	var suppliedTexture: GLuint?
	
	var unmanagedCoreVideoTextureCache: Unmanaged<CVOpenGLESTextureCache>?
	var coreVideoTextureCache: CVOpenGLESTextureCacheRef?
	
	/* Class Methods
	------------------------------------------*/
	
	override class func layerClass() -> AnyClass {
		// In order for our view to display OpenGL content, we need to set it's
		//   default layer to be a CAEAGLayer
		return CAEAGLLayer.self
	}
	
	
	/* Lifecycle
	------------------------------------------*/
	
	init(coder aDecoder: NSCoder!) {
		super.init(coder: aDecoder)
		
		setupLayer()
		setupContext()
		setupRenderBuffer()
		setupFrameBuffer()
		compileShaders()
		setupVBOs()
		setupDisplayLink()
		suppliedTexture = getTextureFromImageWithName("tile_floor.png")
	}
	
	
	/* Instance Methods
	------------------------------------------*/
	
	func setupLayer() {
		// CALayer's are, by default, non-opaque, which is 'bad for performance with OpenGL',
		//   so let's set our CAEAGLLayer layer to be opaque.
		eaglLayer	= layer as CAEAGLLayer
		eaglLayer.opaque = true
	}
	
	func setupContext() {
		// Just like with CoreGraphics, in order to do much with OpenGL, we need a context.
		//   Here we create a new context with the version of the rendering API we want and
		//   tells OpenGL that when we draw, we want to do so within this context.
		var api: EAGLRenderingAPI = EAGLRenderingAPI.OpenGLES2
		context = EAGLContext(API: api)
		
		if (!self.context) {
			println("Failed to initialize OpenGLES 2.0 context!")
			exit(1)
		}
		
		if (!EAGLContext.setCurrentContext(context)) {
			println("Failed to set current OpenGL context!")
			exit(1)
		}

		var err: CVReturn = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, context, nil, &unmanagedCoreVideoTextureCache)
		coreVideoTextureCache = unmanagedCoreVideoTextureCache!.takeUnretainedValue()
	}

	func setupRenderBuffer() {
		// A render buffer is an OpenGL objec that stores the rendered image to present to the screen.
		//   OpenGL will create a unique identifier for a render buffer and store it in a GLuint.
		//   So we call the glGenRenderbuffers function and pass it a reference to our colorRenderBuffer.
		glGenRenderbuffers(1, &colorRenderBuffer)
		// Then we tell OpenGL that whenever we refer to GL_RENDERBUFFER, it should treat that as our colorRenderBuffer.
		glBindRenderbuffer(GL_RENDERBUFFER.asUnsigned(), colorRenderBuffer)
		// Finally, we tell our context that the render buffer for our layer is our colorRenderBuffer.
		context.renderbufferStorage(Int(GL_RENDERBUFFER), fromDrawable:eaglLayer)
	}
	
	func setupFrameBuffer() {
		// A frame buffer is an OpenGL object for storage of a render buffer... amongst other things (tm).
		//   OpenGL will create a unique identifier for a frame vuffer and store it in a GLuint. So we
		//   make a GLuint and pass it to the glGenFramebuffers function to keep this identifier.
		var frameBuffer: GLuint = GLuint()
		glGenFramebuffers(1, &frameBuffer)
		// Then we tell OpenGL that whenever we refer to GL_FRAMEBUFFER, it should treat that as our frameBuffer.
		glBindFramebuffer(GL_FRAMEBUFFER.asUnsigned(), frameBuffer)
		// Finally we tell the frame buffer that it's GL_COLOR_ATTACHMENT0 is our colorRenderBuffer. Oh.
		glFramebufferRenderbuffer(GL_FRAMEBUFFER.asUnsigned(), GL_COLOR_ATTACHMENT0.asUnsigned(), GL_RENDERBUFFER.asUnsigned(), colorRenderBuffer)
	}
	
	func compileShader(shaderName: NSString, shaderType: GLenum) -> GLuint {
		
		// Get NSString with contents of our shader file.
		var shaderPath: NSString = NSBundle.mainBundle().pathForResource(shaderName, ofType: "glsl")
		var error: NSErrorPointer!
		var shaderString: NSString? = NSString.stringWithContentsOfFile(shaderPath, encoding:NSUTF8StringEncoding, error: error)
		if (!shaderString) {
			println("Failed to set contents shader of shader file!")
		}
		
		// Tell OpenGL to create an OpenGL object to represent the shader, indicating if it's a vertex or a fragment shader.
		var shaderHandle: GLuint = glCreateShader(shaderType)
		
		// Conver shader string to CString and call glShaderSource to give OpenGL the source for the shader.
		var shaderStringUTF8: CString = shaderString!.UTF8String
		var shaderStringLength: GLint = GLint.convertFromIntegerLiteral(Int32(shaderString!.length))
		glShaderSource(shaderHandle, 1, &shaderStringUTF8, &shaderStringLength)
		
		// Tell OpenGL to compile the shader.
		glCompileShader(shaderHandle)
		
		// But compiling can fail! If we have errors in our GLSL code, we can here and output any errors.
		var compileSuccess: GLint = GLint()
		glGetShaderiv(shaderHandle, GL_COMPILE_STATUS.asUnsigned(), &compileSuccess)
		if (compileSuccess == GL_FALSE) {
			println("Failed to compile shader!")
			// TODO: Actually output the error that we can get from the glGetShaderInfoLog function.
			exit(1);
		}
		
		return shaderHandle
	}
	
	func compileShaders() {
		
		// Compile our vertex and fragment shaders.
		var vertexShader: GLuint = compileShader("SimpleVertex", shaderType: GL_VERTEX_SHADER.asUnsigned())
		var fragmentShader: GLuint = compileShader("SimpleFragment", shaderType: GL_FRAGMENT_SHADER.asUnsigned())
		
		// Call glCreateProgram, glAttachShader, and glLinkProgram to link the vertex and fragment shaders into a complete program.
		var programHandle: GLuint = glCreateProgram()
		glAttachShader(programHandle, vertexShader)
		glAttachShader(programHandle, fragmentShader)
		glLinkProgram(programHandle)
		
		// Check for any errors.
		var linkSuccess: GLint = GLint()
		glGetProgramiv(programHandle, GL_LINK_STATUS.asUnsigned(), &linkSuccess)
		if (linkSuccess == GL_FALSE) {
			println("Failed to create shader program!")
			// TODO: Actually output the error that we can get from the glGetProgramInfoLog function.
			exit(1);
		}
		
		// Call glUseProgram to tell OpenGL to actually use this program when given vertex info.
		glUseProgram(programHandle)
		
		// Finally, call glGetAttribLocation to get a pointer to the input values for the vertex shader, so we
		//  can set them in code. Also call glEnableVertexAttribArray to enable use of these arrays (they are disabled by default).
		positionSlot = glGetAttribLocation(programHandle, "Position").asUnsigned()
		colorSlot = glGetAttribLocation(programHandle, "SourceColor").asUnsigned()
		glEnableVertexAttribArray(positionSlot)
		glEnableVertexAttribArray(colorSlot)
		
		texCoordSlot = glGetAttribLocation(programHandle, "TexCoordIn").asUnsigned()
		glEnableVertexAttribArray(texCoordSlot);
		textureUniform = glGetUniformLocation(programHandle, "Texture").asUnsigned()
	}
	
	// Setup Vertex Buffer Objects
	func setupVBOs() {
		glGenBuffers(1, &vertexBuffer)
		glBindBuffer(GL_ARRAY_BUFFER.asUnsigned(), vertexBuffer)
		glBufferData(GL_ARRAY_BUFFER.asUnsigned(), Int(sizeofValue(Vertices)), &Vertices, GL_STATIC_DRAW.asUnsigned())
		
		glGenBuffers(1, &indexBuffer)
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER.asUnsigned(), indexBuffer)
		glBufferData(GL_ELEMENT_ARRAY_BUFFER.asUnsigned(), Int(sizeofValue(Indices)), &Indices, GL_STATIC_DRAW.asUnsigned())
	}
	
	func setupDisplayLink() {
		var displayLink: CADisplayLink = CADisplayLink(target: self, selector: "render:")
		displayLink.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
	}
	
	func render(displayLink: CADisplayLink) {
		
		// Call glViewport to set the portion of the UIView to use for rendering. This sets it to the entire window, but if you wanted a smallar part you could change these values.
		glViewport(0, 0, GLint(frame.size.width), GLint(frame.size.height));
		
		// Call glVertexAttribPointer to feed the correct values to the two input variables for the vertex shader – the Position and SourceColor attributes.
		// These two methods are important. Here are some more detailed notes:
		//   > The first parameter specifies the attribute name to set. We got these earlier when we called glGetAttribLocation.
		//   > The second parameter specifies how many values are present for each vertex. If you look back up at the Vertex struct, you’ll see that for the
		//     position there are three floats (x,y,z) and for the color there are four floats (r,g,b,a).
		//   > The third parameter specifies the type of each value – which is float for both Position and Color.
		//   > The fourth parameter is always set to false.
		//   > The fifth parameter is the size of the stride, which is a fancy way of saying “the size of the data structure containing the per-vertex data”.
		//     So we can simply pass in sizeof(Vertex) here to get the compiler to compute it for us.
		//   > The final parameter is the offset within the structure to find this data. The position data is at the beginning of the structure so we can pass 0 here,
		//     the color data is after the Position data (which was 3 floats, so we pass 3 * sizeof(float)).
		let positionSlotFirstComponent: CConstVoidPointer = COpaquePointer(UnsafePointer<Int>(0))
		glVertexAttribPointer(positionSlot, 3 as GLint, GL_FLOAT.asUnsigned(), GLboolean.convertFromIntegerLiteral(UInt8(GL_FALSE)), Int32(sizeof(Vertex)), positionSlotFirstComponent)
		let colorSlotFirstComponent: CConstVoidPointer = COpaquePointer(UnsafePointer<Int>(sizeof(Float) * 3))
		glVertexAttribPointer(colorSlot, 4 as GLint, GL_FLOAT.asUnsigned(), GLboolean.convertFromIntegerLiteral(UInt8(GL_FALSE)), Int32(sizeof(Vertex)), colorSlotFirstComponent)
		
		let texCoordFirstComponent: CConstVoidPointer = COpaquePointer(UnsafePointer<Int>(sizeof(Float) * 7))
		glVertexAttribPointer(texCoordSlot, 2, GL_FLOAT.asUnsigned(), GLboolean.convertFromIntegerLiteral(UInt8(GL_FALSE)), Int32(sizeof(Vertex)), texCoordFirstComponent);
		glActiveTexture(UInt32(GL_TEXTURE0));
		if suppliedTexture {
			
			glBindTexture(GL_TEXTURE_2D.asUnsigned(), suppliedTexture!);
			glUniform1i(textureUniform.asSigned(), 0);
		}
		
		
		// Calls glDrawElements to make the magic happen! This actually ends up calling your vertex shader for every vertex you pass in, and then the fragment shader on each pixel to display on the screen.
		//	  Note that the second parameter to glDrawElements is the number of vertices to render. We use a C trick
		//   here in order to determine this by dividing the size of Indices in bytes by the size of its first element in bytes.
		let vertextBufferOffset: CConstVoidPointer = COpaquePointer(UnsafePointer<Int>(0))
		glDrawElements(GL_TRIANGLES.asUnsigned(), Int32(GLfloat(sizeofValue(Indices)) / GLfloat(sizeofValue(Indices.0))), GL_UNSIGNED_BYTE.asUnsigned(), vertextBufferOffset)
		
		context.presentRenderbuffer(Int(GL_RENDERBUFFER))
	}
	
	func getTextureFromSampleBuffer(sampleBuffer: CMSampleBuffer!) -> GLuint {
		var texture: GLuint = GLuint()
		
		glGenTextures(1, &texture);
		glBindTexture(GL_TEXTURE_2D.asUnsigned(), texture);
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_MIN_FILTER.asUnsigned(), GL_LINEAR)
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_MAG_FILTER.asUnsigned(), GL_LINEAR)
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_WRAP_S.asUnsigned(), GL_CLAMP_TO_EDGE)
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_WRAP_T.asUnsigned(), GL_CLAMP_TO_EDGE)
		
		
		var unmanagedImageBuffer: Unmanaged<CVImageBuffer> = CMSampleBufferGetImageBuffer(sampleBuffer)
		var imageBuffer = unmanagedImageBuffer.takeUnretainedValue()
		var opaqueImageBuffer = unmanagedImageBuffer.toOpaque()
		
		var pixelBuffer: CVPixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaqueImageBuffer).takeUnretainedValue()
		CVPixelBufferLockBaseAddress(pixelBuffer, 0)
		var width: UInt = CVPixelBufferGetWidth(pixelBuffer)
		var height: UInt = CVPixelBufferGetHeight(pixelBuffer)
		
		
		glTexImage2D(GL_TEXTURE_2D.asUnsigned(), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GL_RGBA.asUnsigned(), UInt32(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddress(pixelBuffer))
		CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
		
		
		return texture
	}
	
	
	func getTextureFromImageWithName(fileName: NSString) -> GLuint {
		
		var spriteImage: CGImageRef? = UIImage(named: fileName).CGImage
		if !spriteImage {
			println("Failed to load image!")
			exit(1)
		}
		
		var width: UInt = CGImageGetWidth(spriteImage)
		var height: UInt = CGImageGetHeight(spriteImage)
		var spriteData = COpaquePointer(UnsafePointer<GLubyte>(calloc(UInt(CGFloat(width) * CGFloat(height) * 4), sizeof(GLubyte).asUnsigned())))
	
		let bitmapInfo = CGBitmapInfo.fromRaw(CGImageAlphaInfo.PremultipliedLast.toRaw())!
		var spriteContext: CGContextRef = CGBitmapContextCreate(spriteData, width, height, 8, width*4, CGImageGetColorSpace(spriteImage), bitmapInfo)
		
		CGContextDrawImage(spriteContext, CGRectMake(0, 0, CGFloat(width) , CGFloat(height)), spriteImage)
		CGContextRelease(spriteContext)
		
		var texName: GLuint = GLuint()
		glGenTextures(1, &texName)
		glBindTexture(GL_TEXTURE_2D.asUnsigned(), texName)
		
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_MIN_FILTER.asUnsigned(), GL_NEAREST)
		glTexImage2D(GL_TEXTURE_2D.asUnsigned(), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GL_RGBA.asUnsigned(), UInt32(GL_UNSIGNED_BYTE), spriteData)
		
		free(spriteData)
		return texName
	}
	
	func cleanupTextures() {
		if (videoTexture) {
			CFRelease(videoTexture)
			videoTexture = nil
			videoTextureID = 0
		}
		CVOpenGLESTextureCacheFlush(coreVideoTextureCache, 0);
	}
	
	
	func testGetTextureFromSampleBuffer(sampleBuffer: CMSampleBuffer!) {
		var unmanagedImageBuffer: Unmanaged<CVImageBuffer> = CMSampleBufferGetImageBuffer(sampleBuffer)
		var imageBuffer = unmanagedImageBuffer.takeUnretainedValue()
		var opaqueImageBuffer = unmanagedImageBuffer.toOpaque()
		
		var cameraFrame: CVPixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaqueImageBuffer).takeUnretainedValue()
		var width: UInt = CVPixelBufferGetWidth(cameraFrame)
		var height: UInt = CVPixelBufferGetHeight(cameraFrame)
		
		
		cleanupTextures()
		
		CVPixelBufferLockBaseAddress(cameraFrame, 0)
	
		var err: CVReturn = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, coreVideoTextureCache, imageBuffer, nil, GL_TEXTURE_2D.asUnsigned(),
				GL_RGBA, GLsizei(width), GLsizei(height), GL_BGRA.asUnsigned(), UInt32(GL_UNSIGNED_BYTE), 0, &unmanagedVideoTexture)
		videoTexture = unmanagedVideoTexture!.takeUnretainedValue()

		videoTextureID = CVOpenGLESTextureGetName(videoTexture);
		glBindTexture(GL_TEXTURE_2D.asUnsigned(), videoTextureID);
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_MIN_FILTER.asUnsigned(), GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_MAG_FILTER.asUnsigned(), GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_WRAP_S.asUnsigned(), GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_WRAP_T.asUnsigned(), GL_CLAMP_TO_EDGE);
		
		// Do processing work on the texture data here
		
		CVPixelBufferUnlockBaseAddress(cameraFrame, 0)
		
		CVOpenGLESTextureCacheFlush(coreVideoTextureCache, 0)
		CFRelease(videoTexture)
		videoTexture = nil
		videoTextureID = 0
	}
	
	func updateUsingSampleBuffer(sampleBuffer: CMSampleBuffer!) {
		//suppliedTexture = getTextureFromImageWithName("tile_floor.png")
		//suppliedTexture = getTextureFromSampleBuffer(sampleBuffer)
		//testGetTextureFromSampleBuffer(sampleBuffer)
		//dispatch_async(dispatch_get_main_queue(), {
		//	self.suppliedTexture = self.getTextureFromImageWithName("tile_floor.png")
		//})
		//print(suppliedTexture)
	}
}