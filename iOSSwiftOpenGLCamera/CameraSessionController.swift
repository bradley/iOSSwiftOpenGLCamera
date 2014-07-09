//
//  CameraSessionController.swift
//  iOSSwiftOpenGLCamera
//
//  Created by Bradley Griffith on 7/1/14.
//  Copyright (c) 2014 Bradley Griffith. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMedia
import CoreImage

@objc protocol CameraSessionControllerDelegate {
	@optional func cameraSessionDidOutputSampleBuffer(sampleBuffer: CMSampleBuffer!)
}

class CameraSessionController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	
	var session: AVCaptureSession!
	var sessionQueue: dispatch_queue_t!
	var videoDeviceInput: AVCaptureDeviceInput!
	var videoDeviceOutput: AVCaptureVideoDataOutput!
	var stillImageOutput: AVCaptureStillImageOutput!
	var runtimeErrorHandlingObserver: AnyObject?
	
	var sessionDelegate: CameraSessionControllerDelegate?
	
	
	/* Class Methods
	------------------------------------------*/
	
	class func deviceWithMediaType(mediaType: NSString, position: AVCaptureDevicePosition) -> AVCaptureDevice {
		var devices: NSArray = AVCaptureDevice.devicesWithMediaType(mediaType)
		var captureDevice: AVCaptureDevice = devices.firstObject as AVCaptureDevice
		
		for object:AnyObject in devices {
			let device = object as AVCaptureDevice
			if (device.position == position) {
				captureDevice = device
				break
			}
		}
		
		return captureDevice
	}
	
	
	/* Lifecycle
	------------------------------------------*/
	
	init() {
		super.init();
		
		session = AVCaptureSession()
		
		authorizeCamera();
		
		sessionQueue = dispatch_queue_create("CameraSessionController Session", DISPATCH_QUEUE_SERIAL)
		
		dispatch_async(sessionQueue, {
			self.session.beginConfiguration()
			self.addVideoInput()
			self.addVideoOutput()
			self.addStillImageOutput()
			self.session.commitConfiguration()
		})
	}
	
	
	/* Instance Methods
	------------------------------------------*/
	
	func authorizeCamera() {
		AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: {
			(granted: Bool) -> Void in
			// If permission hasn't been granted, notify the user.
			if !granted {
				dispatch_async(dispatch_get_main_queue(), {
					UIAlertView(
						title: "Could not use camera!",
						message: "This application does not have permission to use camera. Please update your privacy settings.",
						delegate: self,
						cancelButtonTitle: "OK").show()
					})
			}
		});
	}
	
	func addVideoInput() -> Bool {
		var success: Bool = false
		var error: NSError?
		
		var videoDevice: AVCaptureDevice = CameraSessionController.deviceWithMediaType(AVMediaTypeVideo, position: AVCaptureDevicePosition.Back)
		videoDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(videoDevice, error: &error) as AVCaptureDeviceInput;
		if !error {
			if session.canAddInput(videoDeviceInput) {
				session.addInput(videoDeviceInput)
				success = true
			}
		}
		
		return success
	}
	
	func addVideoOutput() {
		
		videoDeviceOutput = AVCaptureVideoDataOutput()
		
		videoDeviceOutput.videoSettings = NSDictionary(object: Int(kCVPixelFormatType_32BGRA), forKey:kCVPixelBufferPixelFormatTypeKey)
		
		videoDeviceOutput.alwaysDiscardsLateVideoFrames = true
		
		videoDeviceOutput.setSampleBufferDelegate(self, queue: sessionQueue)
		
		if session.canAddOutput(videoDeviceOutput) {
			session.addOutput(videoDeviceOutput)
		}
	}
	
	func addStillImageOutput() {
		stillImageOutput = AVCaptureStillImageOutput()
		stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
		
		if session.canAddOutput(stillImageOutput) {
			session.addOutput(stillImageOutput)
		}
	}
	
	func startCamera() {
		dispatch_async(sessionQueue, {
			var weakSelf: CameraSessionController? = self
			self.runtimeErrorHandlingObserver = NSNotificationCenter.defaultCenter().addObserverForName(AVCaptureSessionRuntimeErrorNotification, object: self.sessionQueue, queue: nil, usingBlock: {
				(note: NSNotification!) -> Void in
				
				let strongSelf: CameraSessionController = weakSelf!
				
				dispatch_async(strongSelf.sessionQueue, {
					strongSelf.session.startRunning()
					})
				})
			self.session.startRunning()
		})
	}
	
	func teardownCamera() {
		dispatch_async(sessionQueue, {
			self.session.stopRunning()
			NSNotificationCenter.defaultCenter().removeObserver(self.runtimeErrorHandlingObserver)
		})
	}
	
	func focusAndExposeAtPoint(point: CGPoint) {
		dispatch_async(sessionQueue, {
			var device: AVCaptureDevice = self.videoDeviceInput.device
			var error: NSErrorPointer!
			
			if device.lockForConfiguration(error) {
				if device.focusPointOfInterestSupported && device.isFocusModeSupported(AVCaptureFocusMode.AutoFocus) {
					device.focusPointOfInterest = point
					device.focusMode = AVCaptureFocusMode.AutoFocus
				}
				
				if device.exposurePointOfInterestSupported && device.isExposureModeSupported(AVCaptureExposureMode.AutoExpose) {
					device.exposurePointOfInterest = point
					device.exposureMode = AVCaptureExposureMode.AutoExpose
				}
				
				device.unlockForConfiguration()
			}
			else {
				// TODO: Log error.
			}
		})
	}
	
	func captureImage(completion:((image: UIImage?, error: NSError?) -> Void)?) {
		if !completion || !stillImageOutput {
			return
		}
		
		dispatch_async(sessionQueue, {
			self.stillImageOutput.captureStillImageAsynchronouslyFromConnection(
				self.stillImageOutput.connectionWithMediaType(AVMediaTypeVideo),completionHandler: {
					(imageDataSampleBuffer: CMSampleBuffer?, error: NSError?) -> Void in
					if !imageDataSampleBuffer || error {
						completion!(image:nil, error:nil)
					}
					else if imageDataSampleBuffer {
						var imageData: NSData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer?)
						var image: UIImage = UIImage(data: imageData)
						completion!(image:image, error:nil)
					}
				}
			)
		})
	}
	
	
	/* AVCaptureVideoDataOutput Delegate
	------------------------------------------*/
	
	func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
		if (connection.supportsVideoOrientation){
			//connection.videoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
			connection.videoOrientation = AVCaptureVideoOrientation.Portrait
		}
		if (connection.supportsVideoMirroring) {
			//connection.videoMirrored = true
			connection.videoMirrored = false
		}
		sessionDelegate?.cameraSessionDidOutputSampleBuffer?(sampleBuffer)
	}
	
}