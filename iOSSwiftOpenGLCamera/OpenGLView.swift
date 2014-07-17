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
	var TexCoord: (CFloat, CFloat)
}

var Vertices: (Vertex, Vertex, Vertex, Vertex) = (
	Vertex(Position: (1, -1, 0) , TexCoord: (1, 1)),
	Vertex(Position: (1, 1, 0)  , TexCoord: (1, 0)),
	Vertex(Position: (-1, 1, 0) , TexCoord: (0, 0)),
	Vertex(Position: (-1, -1, 0), TexCoord: (0, 1))
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
	var texCoordSlot: GLuint = GLuint()
	var textureUniform: GLuint = GLuint()
	var timeUniform: GLuint = GLuint()
	var showShaderBoolUniform: GLuint = GLuint()
	var indexBuffer: GLuint = GLuint()
	var vertexBuffer: GLuint = GLuint()
	var unmanagedVideoTexture: Unmanaged<CVOpenGLESTexture>?
	var videoTexture: CVOpenGLESTextureRef?
	var videoTextureID: GLuint?
	var unmanagedCoreVideoTextureCache: Unmanaged<CVOpenGLESTextureCache>?
	var coreVideoTextureCache: CVOpenGLESTextureCacheRef?
	
	var textureWidth: UInt?
	var textureHeight: UInt?
	
	var time: GLfloat = 0.0
	var showShader: GLfloat = 1.0
	
	var frameTimestamp: Double = 0.0
	
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
		
		self.contentScaleFactor =  UIScreen.mainScreen().scale
	}

	
	/* Setup Methods
	------------------------------------------*/
	
	func setupLayer() {
		// CALayer's are, by default, non-opaque, which is 'bad for performance with OpenGL',
		//   so let's set our CAEAGLLayer layer to be opaque.
		eaglLayer = layer as CAEAGLLayer
		eaglLayer.opaque = true

	}
	
	func setupContext() {
		// Just like with CoreGraphics, in order to do much with OpenGL, we need a context.
		//   Here we create a new context with the version of the rendering API we want and
		//   tells OpenGL that when we draw, we want to do so within this context.
		let api: EAGLRenderingAPI = EAGLRenderingAPI.OpenGLES2
		context = EAGLContext(API: api)
		
		if (!self.context) {
			println("Failed to initialize OpenGLES 2.0 context!")
			exit(1)
		}
		
		if (!EAGLContext.setCurrentContext(context)) {
			println("Failed to set current OpenGL context!")
			exit(1)
		}

		let err: CVReturn = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, context, nil, &unmanagedCoreVideoTextureCache)
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
		let shaderPath: NSString = NSBundle.mainBundle().pathForResource(shaderName, ofType: "glsl")

		var shaderString: NSString? = NSString.stringWithContentsOfFile(shaderPath, encoding:NSUTF8StringEncoding, error: nil)
		if (!shaderString) {
			println("Failed to set contents shader of shader file!")
		}
		
		// Tell OpenGL to create an OpenGL object to represent the shader, indicating if it's a vertex or a fragment shader.
		let shaderHandle: GLuint = glCreateShader(shaderType)
		
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
			var value: GLint = 0
			glGetShaderiv(shaderHandle, GLenum(GL_INFO_LOG_LENGTH), &value)
			var infoLog: [GLchar] = [GLchar](count: Int(value), repeatedValue: 0)
			var infoLogLength: GLsizei = 0
			glGetShaderInfoLog(shaderHandle, value, &infoLogLength, &infoLog)
			var messageString = NSString(bytes: infoLog, length: Int(infoLogLength), encoding: NSASCIIStringEncoding)
			
			println("Failed to compile shader!")
			println(messageString)
			
			exit(1);
		}
		
		return shaderHandle
	}
	
	func compileShaders() {
		
		// Compile our vertex and fragment shaders.
		let vertexShader: GLuint = compileShader("SimpleVertex", shaderType: GL_VERTEX_SHADER.asUnsigned())
		let fragmentShader: GLuint = compileShader("SimpleFragment", shaderType: GL_FRAGMENT_SHADER.asUnsigned())
		
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
		glEnableVertexAttribArray(positionSlot)
		
		texCoordSlot = glGetAttribLocation(programHandle, "TexCoordIn").asUnsigned()
		glEnableVertexAttribArray(texCoordSlot);
		
		textureUniform = glGetUniformLocation(programHandle, "Texture").asUnsigned()
		
		timeUniform = glGetUniformLocation(programHandle, "time").asUnsigned()
		
		showShaderBoolUniform = glGetUniformLocation(programHandle, "showShader").asUnsigned()
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
		let displayLink: CADisplayLink = CADisplayLink(target: self, selector: "render:")
		displayLink.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
	}
	
	
	/* Helper Methods
	------------------------------------------*/
	
	func getTextureFromImageWithName(fileName: NSString) -> GLuint {
		
		var spriteImage: CGImageRef? = UIImage(named: fileName).CGImage
		
		if !spriteImage {
			println("Failed to load image!")
			exit(1)
		}
		
		let width: UInt = CGImageGetWidth(spriteImage)
		let height: UInt = CGImageGetHeight(spriteImage)
		let spriteData = UnsafePointer<GLubyte>(calloc(UInt(CGFloat(width) * CGFloat(height) * 4), sizeof(GLubyte).asUnsigned()))
	
		let bitmapInfo = CGBitmapInfo.fromRaw(CGImageAlphaInfo.PremultipliedLast.toRaw())!
		let spriteContext: CGContextRef = CGBitmapContextCreate(spriteData, width, height, 8, width*4, CGImageGetColorSpace(spriteImage), bitmapInfo)
		
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
	
	func cleanupVideoTextures() {
		if (videoTexture) {
			CFRelease(videoTexture)
			videoTexture = nil
		}
		CVOpenGLESTextureCacheFlush(coreVideoTextureCache, 0)
	}
	
	func getTextureFromSampleBuffer(sampleBuffer: CMSampleBuffer!) -> GLuint {
		cleanupVideoTextures()
		
		var unmanagedImageBuffer: Unmanaged<CVImageBuffer> = CMSampleBufferGetImageBuffer(sampleBuffer)
		var imageBuffer = unmanagedImageBuffer.takeUnretainedValue()
		var opaqueImageBuffer = unmanagedImageBuffer.toOpaque()
		
		var cameraFrame: CVPixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaqueImageBuffer).takeUnretainedValue()
		textureWidth = CVPixelBufferGetWidth(cameraFrame)
		textureHeight = CVPixelBufferGetHeight(cameraFrame)

		CVPixelBufferLockBaseAddress(cameraFrame, 0)

		var err: CVReturn = CVOpenGLESTextureCacheCreateTextureFromImage(
										kCFAllocatorDefault,
										coreVideoTextureCache,
										imageBuffer,
										nil,
										GL_TEXTURE_2D.asUnsigned(),
										GL_RGBA,
										GLsizei(textureWidth!),
										GLsizei(textureHeight!),
										GL_BGRA.asUnsigned(),
										UInt32(GL_UNSIGNED_BYTE),
										0,
										&unmanagedVideoTexture
									)
		
		videoTexture = unmanagedVideoTexture!.takeUnretainedValue()
		
		var textureID: GLuint = GLuint()
		textureID = CVOpenGLESTextureGetName(videoTexture);
		glBindTexture(GL_TEXTURE_2D.asUnsigned(), textureID);
		
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_MIN_FILTER.asUnsigned(), GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_MAG_FILTER.asUnsigned(), GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_WRAP_S.asUnsigned(), GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D.asUnsigned(), GL_TEXTURE_WRAP_T.asUnsigned(), GL_CLAMP_TO_EDGE);
		
		
		CVPixelBufferUnlockBaseAddress(cameraFrame, 0)
		
		
		return textureID
	}
	
	func updateUsingSampleBuffer(sampleBuffer: CMSampleBuffer!) {
		dispatch_async(dispatch_get_main_queue(), {
			self.videoTextureID = self.getTextureFromSampleBuffer(sampleBuffer)
		});
	}
	
	func shouldShowShader(show: Bool) {
		showShader = show ? 1.0 : 0.0
	}
	
	func render(displayLink: CADisplayLink) {
		
		if textureWidth && textureHeight {
			var ratio = CGFloat(frame.size.height) / CGFloat(textureHeight!)
			glViewport(0, 0, GLint(CGFloat(textureWidth!) * ratio), GLint(CGFloat(textureHeight!) * ratio))
		}
		else {
			glViewport(0, 0, GLint(frame.size.width), GLint(frame.size.height))
		}
		
		let positionSlotFirstComponent = ConstUnsafePointer<Int>(0)
		glVertexAttribPointer(positionSlot, 3 as GLint, GL_FLOAT.asUnsigned(), GLboolean.convertFromIntegerLiteral(UInt8(GL_FALSE)), Int32(sizeof(Vertex)), positionSlotFirstComponent)
		
		let texCoordFirstComponent = ConstUnsafePointer<Int>(sizeof(Float) * 3)
		glVertexAttribPointer(texCoordSlot, 2, GL_FLOAT.asUnsigned(), GLboolean.convertFromIntegerLiteral(UInt8(GL_FALSE)), Int32(sizeof(Vertex)), texCoordFirstComponent)
		glActiveTexture(UInt32(GL_TEXTURE0))
		if videoTextureID {
			glBindTexture(GL_TEXTURE_2D.asUnsigned(), videoTextureID!)
			glUniform1i(textureUniform.asSigned(), 0)
		}
		
		// Incriment and pass time to shader. This is experimental, be sure to fully test any use of this variable.
		time += Float(displayLink.duration)
		glUniform1f(timeUniform.asSigned(), time)
		
		glUniform1f(showShaderBoolUniform.asSigned(), showShader)

		let vertextBufferOffset = ConstUnsafePointer<Int>(0)
		glDrawElements(GL_TRIANGLES.asUnsigned(), Int32(GLfloat(sizeofValue(Indices)) / GLfloat(sizeofValue(Indices.0))), GL_UNSIGNED_BYTE.asUnsigned(), vertextBufferOffset)
		
		context.presentRenderbuffer(Int(GL_RENDERBUFFER))
	}
}