//
//  KNNClassifier.swift
//  RockClassifier
//
//  Created by Sarah on 1/26/21.
//

import Foundation
import CoreImage
import UIKit
import TensorFlowLite

// Information about the TF model.
enum ColorsModel {
    static let modelInfo: FileInfo = (name: "colors_model", extension: "tflite")
    static let labelsInfo: FileInfo = (name: "colors_labels", extension: "txt")
    static let scalesInfo: FileInfo = (name: "scales", extension: "txt")
    static let minsInfo: FileInfo = (name: "mins", extension: "txt")
}


// MARK: - Image classifier
class KNNClassifier {
    
    // MARK: Constants

    // MARK: Instance Variables
    private var interpreter: Interpreter /// TensorFlow Lite `Interpreter` object for performing inference on a given model.
    private var inputShape: TensorShape
    private var labels: [String] = []
    
    /// Loads the labels from the labels file and stores them in the `labels` property.
    private func loadLabels(fileInfo: FileInfo) {
        let filename = fileInfo.name
        let fileExtension = fileInfo.extension
        
        guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension)
        else {
            fatalError("Labels file not found in bundle. Please add a labels file with name \(filename).\(fileExtension) and try again.")
        }
        guard
            let scaleURL = Bundle.main.url(forResource: ColorsModel.scalesInfo.name, withExtension: fileExtension)
        else {
            fatalError("Scales file not found in bundle. Please add a labels file with name \(filename).\(fileExtension) and try again.")
        }
        
        guard let minURL = Bundle.main.url(forResource: ColorsModel.minsInfo.name, withExtension: fileExtension)
        else {
            fatalError("Mins file not found in bundle. Please add a labels file with name \(filename).\(fileExtension) and try again.")
        }
        
        do {
            var contents = try String(contentsOf: fileURL, encoding: .utf8)
            labels = contents.components(separatedBy: .newlines)
            contents = try String(contentsOf: scaleURL, encoding: .utf8)
            DefaultParameterValues.scales = contents.components(separatedBy: .newlines)
            contents = try String(contentsOf: minURL, encoding: .utf8)
            DefaultParameterValues.mins = contents.components(separatedBy: .newlines)
        } catch {
            fatalError("File named \(filename).\(fileExtension) cannot be read. Please add a valid file and try again.")
        }
    }
    
    /// Initialize KNN Classifer instance
    fileprivate init(interpreter: Interpreter, inputShape: TensorShape) {
        self.interpreter = interpreter
        self.inputShape = inputShape
        self.loadLabels(fileInfo: ColorsModel.labelsInfo)
    }

    static func newInstance(completion: @escaping ((Result<KNNClassifier>) -> ())) {
        // Run initialization in background thread to avoid UI freeze
        DispatchQueue.global(qos: .background).async {
            // Construct the path to the model file.
            guard let modelPath = Bundle.main.path(
                forResource: ColorsModel.modelInfo.name,
                ofType: ColorsModel.modelInfo.extension
            ) else {
                print("Failed to load the model file with name: \(ColorsModel.modelInfo.name).")
                DispatchQueue.main.async {
                    completion(.error(InitializationError.invalidModel("\(ColorsModel.modelInfo.name).\(ColorsModel.modelInfo.extension)")))
                }
                return
            }
            // Specify the options for the `Interpreter`.
            let options = InterpreterOptions()
            // options.threadCount = 2
            do {
                // Create the `Interpreter`.
                let interpreter = try Interpreter(modelPath: modelPath, options: options)
                // Allocate memory for the model's input `Tensor`s.
                try interpreter.allocateTensors()
                
                // Read TF Lite model dimensions
                let inputShape = try interpreter.input(at: 0).shape
                
                // Create KNNClassifier instance and return
                let classifier = KNNClassifier(
                    interpreter: interpreter,
                    inputShape: inputShape
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
                // Preprocessing: Convert the input UIImage to the model input dimensions to feed the TF Lite model.
                guard let labData = image.extractedColorsData()
                else {
                    DispatchQueue.main.async {
                        completion(.error(ClassificationError.invalidImage))
                    }
                    print("Failed to convert the image buffer to LAB data.")
                    return
                }

                // Copy the LAB data to the input `Tensor`.
                try self.interpreter.copy(labData, toInputAt: 0)
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
            
            let result = outputTensor.data.toArray(type: Int.self)[0]
            print("str_inferences = \(result)")
            let str_result = "    " + self.labels[result]

            // Return the classification result
            DispatchQueue.main.async {
                completion(.success(str_result))
            }
        }
    }

}
