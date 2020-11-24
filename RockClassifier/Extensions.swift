//
//  Extensions.swift
//  RockClassifier
//
//  Created by Sarah on 11/23/20.
//

import CoreGraphics
import Foundation
import UIKit
import TensorFlowLite



// MARK: - Constants
private enum Constant {
    static let maxRGBValue: Float32 = 255.0
    static let jpegCompressionQuality: CGFloat = 0.8
    static let alphaComponent = (baseOffset: 4, moduloRemainder: 3)
    static let imageMean: Float32 = 127.5
    static let imageStd: Float32 = 127.5
}



// MARK: - Float
extension Float
{
    func truncate(places : Int)-> String {
        let divisor = pow(10.0, Float(places))
        let r = (self*divisor).rounded(.towardZero) / divisor
        return "\(r)"
    }
}



// MARK: - Data
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



// MARK: - UIImage
extension UIImage {

    /// Returns the data representation of the image after scaling to the given `size` and converting to grayscale.
    /// - Parameters
    ///   - size: Size to scale the image to (i.e. image size used while training the model).
    /// - Returns: The scaled image as data or `nil` if the image could not be scaled.
    
    public func scaledData(inputShape: TensorShape, isModelQuantized: Bool) -> Data? {
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
