//
//  CameraViewController.swift
//  iOSSwiftOpenGLCamera
//
//  Created by Bradley Griffith on 7/3/14.
//  Copyright (c) 2014 Bradley Griffith. All rights reserved.
//

import UIKit
import CoreMedia
import AVFoundation

class CameraViewController: UIViewController, CameraSessionControllerDelegate {
	
	var cameraSessionController: CameraSessionController!
	var previewLayer: AVCaptureVideoPreviewLayer!
	
	
	/* Lifecycle
	------------------------------------------*/
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		cameraSessionController = CameraSessionController()
		cameraSessionController.sessionDelegate = self
		setupPreviewLayer()
	}
	
	override func viewWillAppear(animated: Bool) {3
		super.viewWillAppear(animated)
		
		cameraSessionController.startCamera()
	}
	
	override func viewWillDisappear(animated: Bool) {
		super.viewWillDisappear(animated)
		
		cameraSessionController.teardownCamera()
	}
	
	
	/* Instance Methods
	------------------------------------------*/
	
	func setupPreviewLayer() {
		var minSize: Float = min(view.bounds.size.width, view.bounds.size.height)
		var bounds: CGRect = CGRectMake(0.0, 0.0, minSize, minSize)
		previewLayer = AVCaptureVideoPreviewLayer(session: cameraSessionController.session)
		previewLayer.bounds = bounds
		previewLayer.position = CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds))
		previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
		
		view.layer.addSublayer(previewLayer)
	}
	
	func cameraSessionDidOutputSampleBuffer(sampleBuffer: CMSampleBuffer!) {
		// Any frame processing could be done here.
	}
	
}