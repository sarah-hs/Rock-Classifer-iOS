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


// MARK: - Constants
private enum Constant {
    static let maxRGBValue: Float32 = 255.0
    static let jpegCompressionQuality: CGFloat = 0.8
    static let alphaComponent = (baseOffset: 4, moduloRemainder: 3)
    static let imageMean: Float32 = 127.5
    static let imageStd: Float32 = 127.5
}

public struct DefaultParameterValues {
    public static var maxSampledPixels: Int = 1000
    public static var accuracy: GroupingAccuracy = .medium
    public static var seed: UInt64 = 3571
    public static var memoizeConversions: Bool = false
}


// MARK: - Float
extension Float {
    func truncate(places : Int)-> String {
        let divisor = pow(10.0, Float(places))
        let r = (self*100*divisor).rounded(.towardZero) / divisor
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
    
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }
    
    var dominantColors: Array<(UIColor,Float)>? {
        return getDominantColors(n_clusters: 4)
    }
    
    func getDominantColors(
        _ maxSampledPixels: Int = DefaultParameterValues.maxSampledPixels,
        accuracy: GroupingAccuracy = DefaultParameterValues.accuracy,
        seed: UInt64 = DefaultParameterValues.seed,
        memoizeConversions: Bool = DefaultParameterValues.memoizeConversions,
        n_clusters:Int
    ) -> Array<(UIColor,Float)> {
        
        /// Computes the dominant colors in the receiver
        ///     Created by Indragie on 12/25/14.
        ///     Extracted from: PlatformExtensions.swift - DominantColor pod
        ///     Copyright (c) 2014 Indragie Karunaratne. All rights reserved.

        /// - Parameters
        ///   - MaxSampledPixels:   Maximum number of pixels to sample in the image. If the total number of pixels in the image exceeds this value, it will be downsampled to meet the constraint.
        ///   - Accuracy: Level of accuracy to use when grouping similar colors. Higher accuracy will come with a performance tradeoff.
        ///   - Seed:   Seed to use when choosing the initial points for grouping of similar colors. The same seed is guaranteed to return the same colors every time.
        ///   - MemoizeConversions: Whether to memoize conversions from RGB to the LAB color space (used for grouping similar colors). Memoization will only yield better performance for large values of `maxSampledPixels` in images that are primarily comprised of flat colors. If this information about the image is not known beforehand, it is best to not memoize.
        /// - Returns: A list of dominant colors in the image sorted from most dominant to least dominant.
        
        if let CGImage = self.cgImage {
            let colors = dominantColorsInImage(
                CGImage,
                maxSampledPixels: maxSampledPixels,
                accuracy: accuracy,
                seed: seed,
                memoizeConversions: memoizeConversions,
                n_clusters: n_clusters
            )
            return colors.map { (UIColor(cgColor: $0.color), $0.percentage) }
        } else {
            return []
        }
    }
    
    func getMainColors(size: CGSize) -> UIImage? {
        guard let colors = self.dominantColors
        else { return nil }
        
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
    
    func getAverageColor(size: CGSize) -> UIImage? {
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        self.averageColor!.setFill()
        UIRectFill(rect)
        let image: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
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




// MARK: - Dominant Color extensions

public struct ColorCG {
    /// Structure to send each color and percentage
    let color: CGColor
    let percentage: Float
}

public enum GroupingAccuracy {
    /// From: DominantColor pod - DominantColors.swift
    /// Created by Indragie on 12/20/14.
    /// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
    case low        // CIE 76 - Euclidian distance
    case medium     // CIE 94 - Perceptual non-uniformity corrections
    case high       // CIE 2000 - Additional corrections for neutral colors, lightness, chroma, and hue
}

// Clustering
extension GLKVector3 : ClusteredType {
    /// From: DominantColor pod - DominantColors.swift
    /// Created by Indragie on 12/20/14.
    /// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
}

// Bitmaps
public struct RGBAPixel {
    /// From: DominantColor pod - DominantColors.swift
    /// Created by Indragie on 12/20/14.
    /// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}
extension RGBAPixel: Hashable {
    /// From: DominantColor pod - DominantColors.swift
    /// Created by Indragie on 12/20/14.
    /// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(r)
        hasher.combine(g)
        hasher.combine(b)
    }
}
extension RGBAPixel {
    /// From: DominantColor pod - DominantColors.swift
    /// Created by Indragie on 12/20/14.
    /// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
    func toRGBVector() -> GLKVector3 {
        return GLKVector3Make(
            Float(r) / Float(UInt8.max),
            Float(g) / Float(UInt8.max),
            Float(b) / Float(UInt8.max)
        )
    }
}

// MARK: GLKVector3
extension GLKVector3 {
    ///  Created by Indragie on 12/24/14.
    ///  From: DominantColor pod - INVector3SwiftExtensions.swift
    ///  Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
    func unpack() -> (Float, Float, Float) {
        return (x, y, z)
    }
    static var identity: GLKVector3 {
        return GLKVector3Make(0, 0, 0)
    }
    static func +(lhs: GLKVector3, rhs: GLKVector3) -> GLKVector3 {
        return GLKVector3Make(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }
    static func /(lhs: GLKVector3, rhs: Float) -> GLKVector3 {
        return GLKVector3Make(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs)
    }
    static func /(lhs: GLKVector3, rhs: Int) -> GLKVector3 {
        return lhs / Float(rhs)
    }
}
