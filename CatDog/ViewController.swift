//
//  ViewController.swift
//  CatDog
//
//  Created by Tianran Ding on 16/07/19.
//  Copyright © 2019 Tianran Ding. All rights reserved.
//

import UIKit
import Vision
import AVFoundation

class ViewController: UIViewController {

    @IBOutlet weak var camPreviewView: UIView!
    @IBOutlet weak var resultsLabel: UILabel!
    
    lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        return session
    }()
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    let sampleBufferQueue = DispatchQueue.global(qos: .userInteractive)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureSession.stopRunning()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            self.setupCaptureSession()
            captureSession.startRunning()
        } else if status == .denied || status == .restricted {
            //Warning user if there's no permission to access camera
        } else {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { (authorized) in
                DispatchQueue.main.async {
                    if authorized {
                        self.setupCaptureSession()
                        self.captureSession.startRunning()
                    }
                }
            })
        }
    }
    
    private func setupCaptureSession() {
        guard captureSession.inputs.isEmpty else { return }
        guard let camera = findCamera() else {
            print("No camera found")
            return
        }
        
        do {
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                try! camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
            }
            else if camera.isFocusModeSupported(.autoFocus) {
                try! camera.lockForConfiguration()
                camera.focusMode = .autoFocus
                camera.unlockForConfiguration()
            }
            
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            captureSession.addInput(cameraInput)
            
            let preview = AVCaptureVideoPreviewLayer(session: captureSession)
            preview.frame = view.bounds
            preview.backgroundColor = UIColor.black.cgColor
            preview.videoGravity = .resizeAspectFill
            camPreviewView.layer.addSublayer(preview)
            self.previewLayer = preview
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
            
            captureSession.addOutput(output)
            
        } catch let e {
            print("Error creating capture session: \(e)")
            return
        }
    }
    
    private func findCamera() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(iOS 10.2, *) {
            deviceTypes = [
                .builtInDualCamera,
                .builtInTelephotoCamera,
                .builtInWideAngleCamera
            ]
        } else {
            deviceTypes = [
                .builtInTelephotoCamera,
                .builtInWideAngleCamera
            ]
        }
        
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                         mediaType: .video,
                                                         position: .back)
        
        return discovery.devices.first
    }
    
    public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation
        
        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .upMirrored
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .down
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        return exifOrientation
    }
}

extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let exifOrientation = exifOrientationFromDeviceOrientation()
        let req = VNDetectAnimalRectanglesRequest(completionHandler:  {(request, error) in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                DispatchQueue.main.async {
                    self.resultsLabel.text = ""
                }
                return
            }
            var cats = 0, dogs = 0
            for obs in observations {
                for label in obs.labels {
                    if label.identifier == "Cat" {
                        cats += 1
                        break
                    } else if label.identifier == "Dog" {
                        dogs += 1
                        break
                    }
                }
            }
            
            DispatchQueue.main.async {
                if dogs == 0 && cats == 0 {
                    self.resultsLabel.text = "no animal at all"
                } else {
                    self.resultsLabel.text = "\(cats) cats & \(dogs) dogs"
                }
            }
        })
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        try? imageRequestHandler.perform([req])
    }
}
