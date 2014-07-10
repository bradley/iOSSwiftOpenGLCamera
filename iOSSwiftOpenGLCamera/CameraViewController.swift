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
	@IBOutlet var openGLView: OpenGLView!

	
	/* Lifecycle
	------------------------------------------*/
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		cameraSessionController = CameraSessionController()
		cameraSessionController.sessionDelegate = self
		setupPreviewLayer()
	}
	
	override func viewWillAppear(animated: Bool) {
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
	}
	
	func cameraSessionDidOutputSampleBuffer(sampleBuffer: CMSampleBuffer!) {
		openGLView.updateUsingSampleBuffer(sampleBuffer)
	}
	
}