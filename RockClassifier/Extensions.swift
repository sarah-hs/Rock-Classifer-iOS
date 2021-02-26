//
//  Extensions.swift
//  RockClassifier
//
//  Created by Sarah on 11/23/20.
//

import CoreGraphics
import Foundation
import UIKit
import GLKit
import TensorFlowLite


// Menu:
/// - Structures
/// - Enums
/// - Extensions



// MARK: - Structures

typealias FileInfo = (
    /// Information about a model file or labels file.
    name: String,
    extension: String
)

struct Inference {
    /// An inference from invoking the `Interpreter`.
    let confidence: Float
    let label: String
}

public struct DominantColor {
    /// Structure to send each color and percentage
    let Color: Pixel
    let percentage: Double
}

struct Pixel : ClusteredType{
    var v1: Double,
        v2: Double,
        v3: Double;
    static func + (lhs: Pixel, rhs: Pixel) -> Self {
        return Pixel(v1: lhs.v1 + rhs.v1, v2: lhs.v2 + rhs.v2, v3: lhs.v3 + rhs.v3)
    }
    
    static func / (lhs: Pixel, rhs: Int) -> Self {
        return Pixel(v1: lhs.v1 / Double(rhs), v2: lhs.v2 / Double(rhs), v3: lhs.v3 / Double(rhs))
    }
    
    static var identity: Pixel {
        return Pixel(v1: 0.0, v2: 0.0, v3: 0.0)
    }
}





// MARK: - Enums

enum Result<T> {
    /// Convenient enum to return result with a callback
    case success(T)
    case error(Error)
}

enum InitializationError: Error {
    /// Define errors that could happen in the initialization of this class
    case invalidModel(String) /// Invalid TF Lite model
    case internalError(Error) /// TF Lite Internal Error when initializing
}

enum ClassificationError: Error {
    /// Define errors that could happen in when doing image clasification
    case invalidImage /// Invalid input image
    case internalError(Error) /// TF Lite Internal Error when initializing
}

private enum Constant {
    static let maxRGBValue: Float32 = 255.0
    static let jpegCompressionQuality: CGFloat = 0.8
    static let alphaComponent = (baseOffset: 4, moduloRemainder: 3)
    static let imageMean: Float32 = 127.5
    static let imageStd: Float32 = 127.5
}





// MARK: - Extensions

// MARK: Float
extension Float {
    func truncate(places : Int)-> String {
        let divisor = pow(10.0, Float(places))
        let r = (self*100*divisor).rounded(.towardZero) / divisor
        return "\(r)"
    }
}

// MARK: Data
extension Data {
    
    /// Creates a new buffer by copying the buffer pointer of the given array.
    /// - Warning: The given array's element type `T` must be trivial in that it can be copied bit
    ///     for bit with no indirection or reference-counting operations; otherwise, reinterpreting
    ///     data from the resulting buffer has undefined behavior.
    /// - Parameter array: An array with elements of type `T`.

    init<T>(copyingBufferOf array: [T]) {
        self = array.withUnsafeBufferPointer(Data.init)
    }
    
    func toArray<T>(type: T.Type) -> [T] where T: ExpressibleByIntegerLiteral {
        var array = Array<T>(repeating: 0, count: self.count/MemoryLayout<T>.stride)
        _ = array.withUnsafeMutableBytes { copyBytes(to: $0) }
        return array
    }
}

// MARK: CGImage
extension CGImage {
    func pixelData() -> [Pixel]? { // Double, UInt8
        var colors = [Pixel]()
        let dataSize = self.width * self.height * 4
        var pixelData = [UInt8](repeating: 0, count: Int(dataSize))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixelData,
                                width: Int(self.width),
                                height: Int(self.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 4 * Int(self.width),
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.draw(self, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))
        
        print("Width:", self.width, "Height:", self.height)
        print("RGB data size =", pixelData.count)
        print("RGB data [0...15] =", pixelData[0...15])
        
        var out = self.width
        var ins = self.height
        if self.height < out {
            out = self.height
            ins = self.width
        }
        for x in 0..<out {
            for y in 0..<ins {
                let from = 4 * (out * x + y)
                let color = Pixel(v1: Double(pixelData[from]),
                                  v2: Double(pixelData[from + 1]),
                                  v3: Double(pixelData[from + 2]))
                colors.append(color)
            }
        }
        
        return colors
    }
    
    func labData() -> [Pixel]? { // Double, UInt8
        var colors = [Pixel]()
        let dataSize = self.width * self.height * 4
        var pixelData = [UInt8](repeating: 0, count: Int(dataSize))
        let colorSpace = CGColorSpace(name:CGColorSpace.genericLab)!
        let context = CGContext(data: &pixelData,
                                width: Int(self.width),
                                height: Int(self.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 4 * Int(self.width),
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.draw(self, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))
        
        print("Width:", self.width, "Height:", self.height)
        print("RGB data size =", pixelData.count)
        print("RGB data [0...15] =", pixelData[0...15])
        
        for i in 0..<Int(pixelData.count/4){
            let from = i*4
            let color = Pixel(v1: Double(pixelData[from]),
                              v2: Double(pixelData[from + 1]),
                              v3: Double(pixelData[from + 2]))
            colors.append(color)
        }
        
        return colors
    }
}

// MARK: UIImage
extension UIImage {
    
    private struct dominant {
        static var Colors : [DominantColor] = []
    }
    
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector])
        else { return nil }
        
        guard let outputImage = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }
    
    func averageColorImage(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        self.averageColor!.setFill()
        UIRectFill(rect)
        let image: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    func dominantColorsImage(size: CGSize) -> UIImage? {
        dominant.Colors = dominantColorsInImage(self.cgImage!, n_clusters: 4)
        let colors = dominant.Colors.map {(
            UIColor(cgColor: rgb_to_cgcolor(lab_to_rgb(lab: $0.Color))), $0.percentage
        )}
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        var index = CGFloat(0)
        for color in colors {
            let rect = CGRect(x: index, y: 0, width: size.width * CGFloat(color.1), height: size.height)
            color.0.setFill()
            UIRectFill(rect)
            index += size.width*CGFloat(color.1)
        }
        let image: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    public func extractedColorsData() -> Data? {
        //dominant.Colors = dominantColorsInImage(self.cgImage!, n_clusters: 4)
        var features = [Double]()
        for dominant_color in dominant.Colors {
            features.append(dominant_color.Color.v1)
            features.append(dominant_color.Color.v2)
            features.append(dominant_color.Color.v3)
            features.append(dominant_color.percentage)
        }
        print("Dominant colors =", features)
        let zippedResults = zip(features, zip(DefaultParameterValues.scales, DefaultParameterValues.mins))
        let n_features = zippedResults.map { norm in norm.0 * Double(norm.1.0)! + Double(norm.1.1)! }
        
        print("Normalized dominant colors =", n_features.map{Float($0)})
        return Data(copyingBufferOf: n_features.map{Float($0)} )
    }

    public func scaledData(inputShape: TensorShape, isModelQuantized: Bool) -> Data? {
        
        /// Returns the data representation of the image after scaling to the given `size` and converting to grayscale.
        /// - Parameters
        ///   - size: Size to scale the image to (i.e. image size used while training the model).
        /// - Returns: The scaled image as data or `nil` if the image could not be scaled.
        
        guard let cgImage = self.cgImage, cgImage.width > 0, cgImage.height > 0 else { return nil }

//        let bitmapInfo = CGBitmapInfo(
//            rawValue: CGImageAlphaInfo.none.rawValue
//        )
        
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        let batchSize = inputShape.dimensions[0]
        let width = inputShape.dimensions[1]
        let height = inputShape.dimensions[2]
        let channels = inputShape.dimensions[3]
        
        //let colorSpace = channels == 3 ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray()
        //let bitmapInfo = channels == 3 ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.none.rawValue
        let byteCount = batchSize * width * height * channels
        //let colorSpace = cgImage.colorSpace
        
        let scaledBytesPerRow = (cgImage.bytesPerRow / cgImage.width) * width
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: scaledBytesPerRow, //width * 1,
            space: CGColorSpaceCreateDeviceRGB(),//colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let imageData = context.makeImage()?.dataProvider?.data as Data? else { return nil }
        var scaledBytes = [UInt8](repeating: 0, count: byteCount)
        
        var index = 0
        for component in imageData.enumerated() {
            let offset = component.offset
            let isAlphaComponent = (offset % Constant.alphaComponent.baseOffset) == Constant.alphaComponent.moduloRemainder
            guard !isAlphaComponent else { continue }
            scaledBytes[index] = component.element
            index += 1
        }
        
        if isModelQuantized { return Data(scaledBytes) }
        
        //        let scaledFloats = scaledBytes.map { (Float32($0) - Constant.imageMean) / Constant.imageStd }
        let scaledFloats = scaledBytes.map { Float32($0) / Constant.maxRGBValue }
        return Data(copyingBufferOf: scaledFloats)
    }
    
}
