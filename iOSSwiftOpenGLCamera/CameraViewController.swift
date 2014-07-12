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
	@IBOutlet var togglerSwitch: UISwitch
	
	
	/* Lifecycle
	------------------------------------------*/
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		cameraSessionController = CameraSessionController()
		cameraSessionController.sessionDelegate = self
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
	
	@IBAction func toggleShader(sender: AnyObject) {
		openGLView.shouldShowShader(togglerSwitch.on)
	}
	
	func cameraSessionDidOutputSampleBuffer(sampleBuffer: CMSampleBuffer!) {
		openGLView.updateUsingSampleBuffer(sampleBuffer)
	}
	
}