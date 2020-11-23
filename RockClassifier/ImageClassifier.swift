//
//  ImageClassifier.swift
//  RockClassifier
//
//  Created by Sarah on 11/23/20.
//

import Foundation
import CoreImage
import UIKit
//import TensorFlowLite
//import Accelerate


// MARK: - Structures and Enums

// Information about a model file or labels file.
typealias FileInfo = (name: String, extension: String)

// Information about the MobileNet model.
enum MobileNet {
  static let modelInfo: FileInfo = (name: "mobilenet_quant_v1_224", extension: "tflite")
  static let labelsInfo: FileInfo = (name: "labels", extension: "txt")
}

// Convenient enum to return result with a callback
enum Result<T> {
  case success(T)
  case error(Error)
}

private enum Constant {
  /// Specify the TF Lite model file
  static let modelFilename = "mnist"
  static let modelFileExtension = "tflite"
}

// An inference from invoking the `Interpreter`.
struct Inference {
  let confidence: Float
  let label: String
}


// MARK: - Image classifier
class ImageClassifier {
    
    // MARK: Constants

    // MARK: Instance Variables
    private var interpreter: Interpreter /// TensorFlow Lite `Interpreter` object for performing inference on a given model.
    private var inputImageWidth: Int
    private var inputImageHeight: Int

    /// Initialize Digit Classifer instance
    fileprivate init(interpreter: Interpreter, inputImageWidth: Int, inputImageHeight: Int) {
        self.interpreter = interpreter
        self.inputImageWidth = inputImageWidth
        self.inputImageHeight = inputImageHeight
    }

    static func newInstance(completion: @escaping ((Result<ImageClassifier>) -> ())) {
        // Run initialization in background thread to avoid UI freeze
        DispatchQueue.global(qos: .background).async {
            // Construct the path to the model file.
            guard let modelPath = Bundle.main.path(
                forResource: Constant.modelFilename,
                ofType: Constant.modelFileExtension
            ) else {
                print("Failed to load the model file with name: \(Constant.modelFilename).")
                DispatchQueue.main.async {
                    completion(.error(InitializationError.invalidModel("\(Constant.modelFilename).\(Constant.modelFileExtension)")))
                }
                return
            }
            // Specify the options for the `Interpreter`.
            var options = InterpreterOptions()
            options.threadCount = 2
            do {
                // Create the `Interpreter`.
                let interpreter = try Interpreter(modelPath: modelPath, options: options)

                // Allocate memory for the model's input `Tensor`s.
                try interpreter.allocateTensors()

                // Read TF Lite model input dimension
                let inputShape = try interpreter.input(at: 0).shape
                let inputImageWidth = inputShape.dimensions[1]
                let inputImageHeight = inputShape.dimensions[2]

                // Create DigitClassifier instance and return
                let classifier = ImageClassifier(
                    interpreter: interpreter,
                    inputImageWidth: inputImageWidth,
                    inputImageHeight: inputImageHeight
                )
                DispatchQueue.main.async {
                    completion(.success(classifier))
                }
            } catch let error {
                print("Failed to create the interpreter with error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.error(InitializationError.internalError(error)))
                }
                return
            }
        }
    }
    
    func classify(image: UIImage, completion: @escaping ((Result<String>) -> ())) {
        DispatchQueue.global(qos: .background).async {
            let outputTensor: Tensor
            do {
                // Preprocessing: Convert the input UIImage to (28 x 28) grayscale image to feed to TF Lite model.
                guard let rgbData = image.scaledData(with: CGSize(width: self.inputImageWidth, height: self.inputImageHeight))
                else {
                DispatchQueue.main.async {
                    completion(.error(ClassificationError.invalidImage))
                }
                print("Failed to convert the image buffer to RGB data.")
                return
                }

                // Copy the RGB data to the input `Tensor`.
                try self.interpreter.copy(rgbData, toInputAt: 0)

                // Run inference by invoking the `Interpreter`.
                try self.interpreter.invoke()

                // Get the output `Tensor` to process the inference results.
                outputTensor = try self.interpreter.output(at: 0)
            } catch let error {
                print("Failed to invoke the interpreter with error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.error(ClassificationError.internalError(error)))
                }
                return
            }

            // Postprocessing: Find the label with highest confidence and return as human readable text.
            let results = outputTensor.data.toArray(type: Float32.self)
            let maxConfidence = results.max() ?? -1
            let maxIndex = results.firstIndex(of: maxConfidence) ?? -1
            let humanReadableResult = "Predicted: \(maxIndex)\nConfidence: \(maxConfidence)"

            // Return the classification result
            DispatchQueue.main.async {
                completion(.success(humanReadableResult))
            }
        }
    }

}



// MARK: - Error enums
/// Define errors that could happen in the initialization of this class
enum InitializationError: Error {
  // Invalid TF Lite model
  case invalidModel(String)
  // TF Lite Internal Error when initializing
  case internalError(Error)
}

/// Define errors that could happen in when doing image clasification
enum ClassificationError: Error {
  // Invalid input image
  case invalidImage
  // TF Lite Internal Error when initializing
  case internalError(Error)
}
