//
//  ImageClassifier.swift
//  RockClassifier
//
//  Created by Sarah on 11/23/20.
//

import Foundation
import CoreImage
import UIKit
import TensorFlowLite


// MARK: - Structures and Enums

// Information about a model file or labels file.
typealias FileInfo = (name: String, extension: String)

// Information about the MobileNet model.
enum Model {
//    static let modelInfo: FileInfo = (name: "mobilenet_quant_v1_224", extension: "tflite")
//    static let labelsInfo: FileInfo = (name: "labels", extension: "txt")
    static let modelInfo: FileInfo = (name: "rock_model", extension: "tflite")
    static let labelsInfo: FileInfo = (name: "rock_labels", extension: "txt")
}

// Convenient enum to return result with a callback
enum Result<T> {
    case success(T)
    case error(Error)
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
    private var inputShape: TensorShape
    private var outputShape: TensorShape
    private var resultsToDisplay = -1 // Default -1: Classifier will display the results of all classes from the selected model
    private var labels: [String] = []
    
    /// Loads the labels from the labels file and stores them in the `labels` property.
    private func loadLabels(fileInfo: FileInfo) {
        let filename = fileInfo.name
        let fileExtension = fileInfo.extension
        guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension)
        else {
            fatalError("Labels file not found in bundle. Please add a labels file with name \(filename).\(fileExtension) and try again.")
        }
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            labels = contents.components(separatedBy: .newlines)
        } catch {
            fatalError("Labels file named \(filename).\(fileExtension) cannot be read. Please add a valid labels file and try again.")
        }
    }
    
    /// Initialize Digit Classifer instance
    fileprivate init(interpreter: Interpreter, inputShape: TensorShape, outputShape: TensorShape) {
        self.interpreter = interpreter
        self.inputShape = inputShape
        self.outputShape = outputShape
        self.loadLabels(fileInfo: Model.labelsInfo)
    }

    static func newInstance(completion: @escaping ((Result<ImageClassifier>) -> ())) {
        // Run initialization in background thread to avoid UI freeze
        DispatchQueue.global(qos: .background).async {
            // Construct the path to the model file.
            guard let modelPath = Bundle.main.path(
                forResource: Model.modelInfo.name,
                ofType: Model.modelInfo.extension
            ) else {
                print("Failed to load the model file with name: \(Model.modelInfo.name).")
                DispatchQueue.main.async {
                    completion(.error(InitializationError.invalidModel("\(Model.modelInfo.name).\(Model.modelInfo.extension)")))
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
                
                // Read TF Lite model dimensions
                let inputShape = try interpreter.input(at: 0).shape
                let outputShape = try interpreter.output(at: 0).shape
                
                // Create ImageClassifier instance and return
                let classifier = ImageClassifier(
                    interpreter: interpreter,
                    inputShape: inputShape,
                    outputShape: outputShape
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
                let inputTensor = try self.interpreter.input(at: 0)
                
                // Preprocessing: Convert the input UIImage to the model input image dimensions to feed the TF Lite model.
                guard let rgbData = image.scaledData(
                    inputShape: self.inputShape,
                    isModelQuantized: inputTensor.dataType == .uInt8
                ) else {
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
            
            let results: [Float]
            switch outputTensor.dataType {
                case .uInt8:
                    guard let quantization = outputTensor.quantizationParameters
                    else {
                        print("No results returned because the quantization values for the output tensor are nil.")
                        return
                    }
                    
                    let quantizedResults = [UInt8](outputTensor.data)
                    results = quantizedResults.map {
                        quantization.scale * Float(Int($0) - quantization.zeroPoint)
                    }
                case .float32:
                    results = outputTensor.data.toArray(type: Float32.self)
                    print("output type jeje: \(outputTensor.dataType)")
                default:
                    print("Output tensor data type \(outputTensor.dataType) is unsupported for this example app.")
                    return
            }
            
            if (self.resultsToDisplay == -1){
                self.resultsToDisplay = self.outputShape.dimensions[1]
                print("results to display: \(self.resultsToDisplay)")
            }
            
            // Create a zipped array of tuples [(labelIndex: Int, confidence: Float)].
            let zippedResults = zip(self.labels.indices, results)
            // Sort the zipped results by confidence value in descending order.
            let sortedResults = zippedResults.sorted { $0.1 > $1.1 }.prefix(self.resultsToDisplay)
            // Return the `Inference` results.
            let inferences =  sortedResults.map { result in Inference(confidence: result.1, label: self.labels[result.0]) }
            
            print("inferences = \(inferences)")
            
            var str_inferences = ""
            var first = true
            for inference in inferences {
                if (first){
                    str_inferences += "\(inference.label): \(inference.confidence.truncate(places: 3))%"
                    first = false
                } else {
                    str_inferences += "\n\(inference.label): \(inference.confidence.truncate(places: 3))%"
                }
            }
            
            print("str_inferences = \(str_inferences)")

            // Return the classification result
            DispatchQueue.main.async {
                completion(.success(str_inferences))
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
