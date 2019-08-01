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
    @IBOutlet weak var boundingsView: UIView!
    @IBOutlet weak var resultsLabel: UILabel!
    
    lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        return session
    }()
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    var bufferSize = CGSize(width: 0.0, height: 0.0)
    var frameSize = CGSize(width: 0.0, height: 0.0)
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
        frameSize = boundingsView.frame.size
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
            
            let captureConnection = output.connection(with: .video)
            captureConnection?.isEnabled = true
            do {
                try camera.lockForConfiguration()
                let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
                bufferSize.width = CGFloat(dimensions.width)
                bufferSize.height = CGFloat(dimensions.height)
                camera.unlockForConfiguration()
            } catch {
                print(error)
            }
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
        //Make a request to handle detection results
        let req = VNRecognizeAnimalsRequest(completionHandler:  {(request, error) in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                return
            }
            
            var cats = [CGRect](), dogs = [CGRect]()
            var catCount = 0, dogCount = 0
            for observation in observations {
                let newOrigin = CGRect(x: observation.boundingBox.origin.y,
                                       y: observation.boundingBox.origin.x,
                                       width: observation.boundingBox.size.height,
                                       height: observation.boundingBox.size.width)
                let newFrame = VNImageRectForNormalizedRect(newOrigin, Int(self.frameSize.width), Int(self.frameSize.height))
                for classification in observation.labels {
                    //Either cat or dog
                    if classification.identifier == "Cat" {
                        catCount += 1
                        cats.append(newFrame)
                        break
                    } else if classification.identifier == "Dog" {
                        dogCount += 1
                        dogs.append(newFrame)
                        break
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.boundingsView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                if dogCount == 0 && catCount == 0 {
                    self.resultsLabel.text = "no animal at all"
                } else {
                    self.resultsLabel.text = "\(catCount) cats & \(dogCount) dogs"
                }
                for shape in cats {
                    let shapeLayer = self.createCatRoundedRectLayerWithBounds(shape)
                    self.boundingsView.layer.addSublayer(shapeLayer)
                }
                for shape in dogs {
                    let shapeLayer = self.createDogRoundedRectLayerWithBounds(shape)
                    self.boundingsView.layer.addSublayer(shapeLayer)
                }
            }
        })
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        try? imageRequestHandler.perform([req])
    }
    
    func createCatRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.cornerRadius = 10
        mask.opacity = 0.75
        mask.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 0.2, 0.2, 0.4])
        mask.borderWidth = 3.0
        return mask
    }
    
    func createDogRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.cornerRadius = 10
        mask.opacity = 0.75
        mask.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.2, 1.0, 1.0, 0.4])
        mask.borderWidth = 3.0
        return mask
    }
}
