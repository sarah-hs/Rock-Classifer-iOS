//
//  ViewController.swift
//  RockClassifier
//
//  Created by Sarah on 11/23/20.
//

import Foundation
import UIKit
import AVFoundation

class ViewController: UIViewController {
    // MARK: Storyboards Connections
    @IBOutlet weak var button_camera: UIButton!
    //@IBOutlet weak var button_library: UIButton!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var button_classify: UIButton!
    @IBOutlet weak var label_results: UILabel!
    @IBOutlet weak var imageView: UIImageView!
    
    // MARK: Constants
    // MARK: Instance Variables
    private var classifier: KNNClassifier?
    private var imagePicker = UIImagePickerController()
    private var targetImage: UIImage?
    private var extractedImage: UIImage?
    private var averageImage: UIImage?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        targetImage = imageView.image
        self.extractedImage = targetImage?.dominantColorsImage(size: imageView.frame.size)
        self.averageImage = targetImage?.averageColorImage(size: imageView.frame.size)
        
        // Setup image picker.
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.allowsEditing = false

        // Enable camera option only if current device has camera.
        let isCameraAvailable = UIImagePickerController.isCameraDeviceAvailable(.front) || UIImagePickerController.isCameraDeviceAvailable(.rear)
        if isCameraAvailable {
            button_camera.isEnabled = true
        }
        
        KNNClassifier.newInstance { result in
            switch result {
            case let .success(classifier):
                self.classifier = classifier
            case .error(_):
                self.label_results.text = "Failed to initialize."
            }
        }
    }
    
    // Open camera to allow user taking photo.
    @IBAction func onTapOpenCamera(_ sender: Any) {
        guard UIImagePickerController.isCameraDeviceAvailable(.front) || UIImagePickerController.isCameraDeviceAvailable(.rear)
        else {
            return
        }
        imagePicker.sourceType = .camera
        present(imagePicker, animated: true)
    }

    // Open photo library for user to choose an image from.
    @IBAction func onTapPhotoLibrary(_ sender: Any) {
        imagePicker.sourceType = .photoLibrary
        present(imagePicker, animated: true)
    }
    
    /// Handle tapping on different display mode: Original Image, Color extracted Image, and average image color
    @IBAction func onSegmentChanged(_ sender: Any) {
        switch segmentedControl.selectedSegmentIndex {
            case 0:
                // Mode 0: Show input image
                imageView.image = self.targetImage
            case 1:
                // Mode 1: Show visualization of main colors result.
                imageView.image = self.extractedImage
            case 2:
                // Mode 2: Show visualization of average color result.
                imageView.image = self.averageImage
            default:
                break
        }
    }

    @IBAction func classify(_ sender: Any) {
        label_results.text = "Classifying..."
        guard let classifier = self.classifier else { return }
        guard targetImage != nil else {
              label_results.text = "Invalid image."
              return
        }

        // Run Image classifier.
        classifier.classify(image: targetImage!) { result in
            // Show the classification result on screen.
            switch result {
                case let .success(classificationResult):
                    self.label_results.text = classificationResult
                case .error(_):
                    self.label_results.text = "Failed to classify image."
            }
        }
    }
}




// MARK: - UIImagePickerControllerDelegate
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let pickedImage = info[.originalImage] as? UIImage {
            print("\nLoading image...")
            self.targetImage = pickedImage
            imageView.image = targetImage
            segmentedControl.selectedSegmentIndex = 0;
            self.label_results.text = "Tap classify to get results"
        }
        dismiss(animated: true)
        self.extractedImage = self.targetImage?.dominantColorsImage(size: imageView.frame.size)
        self.averageImage = self.targetImage?.averageColorImage(size: imageView.frame.size)
    }
}


//    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
//        print("\nLoading image...")
//        if let pickedImage = info[.editedImage] as? UIImage {
//            self.targetImage = pickedImage
//        } else if let pickedImage2 = info[.originalImage] as? UIImage {
//            self.targetImage = pickedImage2
//        }
//        imageView.image = targetImage
//        segmentedControl.selectedSegmentIndex = 0;
//        self.label_results.text = "Tap classify to get results"
//
//        picker.dismiss(animated: true,completion: nil)
//
//        self.averageImage = self.targetImage?.averageColorImage(size: imageView.frame.size)
//        self.extractedImage = self.targetImage?.dominantColorsImage(size: imageView.frame.size)
//    }
