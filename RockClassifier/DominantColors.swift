//
//  Extensions.swift
//  RockClassifier
//
//  Created by Sarah on 11/24/20.
//

import UIKit
import GLKit
import GLKit.GLKMath

// MARK: - Main

/// From: DominantColor pod - DominantColors.swift
/// Created by Indragie on 12/20/14.
/// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.

func dominantColorsInImage(
    _ image: CGImage,
    maxSampledPixels: Int = DefaultParameterValues.maxSampledPixels,
    accuracy: GroupingAccuracy = DefaultParameterValues.accuracy,
    seed: UInt64 = DefaultParameterValues.seed,
    memoizeConversions: Bool = DefaultParameterValues.memoizeConversions,
    n_clusters: Int
) -> [ColorCG] {
    
    /// Computes the dominant colors in an image
    /// - Parameters:
    ///   - Image: The image
    ///   - MaxSampledPixels: Maximum number of pixels to sample in the image. If the total number of pixels in the image exceeds this value, it will be downsampled to meet the constraint.
    ///   - Accuracy: Level of accuracy to use when grouping similar colors. Higher accuracy will come with a performance tradeoff.
    ///   - Seed: Seed to use when choosing the initial points for grouping of similar colors. The same seed is guaranteed to return the same colors every time.
    ///   - MemoizeConversions: Whether to memoize conversions from RGB to the LAB color space (used for grouping similar colors). Memoization will only yield better performance for large values of `maxSampledPixels` in images that are primarily comprised of flat colors. If this information about the image is not known beforehand, it is best to not memoize.
    /// - Returns: A list of dominant colors in the image sorted from most dominant to least dominant.
    
    let (width, height) = (image.width, image.height)
    let (scaledWidth, scaledHeight) = scaledDimensionsForPixelLimit(maxSampledPixels, width: width, height: height)
    
    /// Downsample the image if necessary, so that the total number of pixels sampled does not exceed the specified maximum.
    let context = createRGBAContext(scaledWidth, height: scaledHeight)
    context.draw(image, in: CGRect(x: 0, y: 0, width: Int(scaledWidth), height: Int(scaledHeight)))

    /// Get the RGB colors from the bitmap context, ignoring any pixels that have alpha transparency. Also convert the colors to the LAB color space
    var labValues = [GLKVector3]()
    labValues.reserveCapacity(Int(scaledWidth * scaledHeight))
    
    let RGBToLAB: (RGBAPixel) -> GLKVector3 = {
        let f: (RGBAPixel) -> GLKVector3 = { IN_RGBToLAB($0.toRGBVector()) }
        return memoizeConversions ? memoize(f) : f
    }()
    enumerateRGBAContext(context) { (_, _, pixel) in
        if pixel.a == UInt8.max {
            labValues.append(RGBToLAB(pixel))
        }
    }
    /// Cluster the colors using the k-means algorithm
    let k = selectKForElements(k: n_clusters)
    var clusters = kmeans(labValues, k: k, seed: seed, distance: distanceForAccuracy(accuracy))
    /// Sort the clusters by size in descending order so that the most dominant colors come first.
    clusters.sort { $0.size > $1.size }
    var total = 0
    for cluster in clusters {
        total += cluster.size
    }
    
    return clusters.map { ColorCG(color: RGBVectorToCGColor(IN_LABToRGB($0.centroid)), percentage: Float($0.size)/Float(total)) }
}

func distanceForAccuracy(_ accuracy: GroupingAccuracy) -> (GLKVector3, GLKVector3) -> Float {
    switch accuracy {
    case .low:
        return CIE76SquaredColorDifference
    case .medium:
        return CIE94SquaredColorDifference()
    case .high:
        return CIE2000SquaredColorDifference()
    }
}

func scaledDimensionsForPixelLimit(_ limit: Int, width: Int, height: Int) -> (Int, Int) {
    /// Computes the proportionally scaled dimensions such that the total number of pixels does not exceed the specified limit.
    
    if (width * height > limit) {
        let ratio = Float(width) / Float(height)
        let maxWidth = sqrtf(ratio * Float(limit))
        return (Int(maxWidth), Int(Float(limit) / maxWidth))
    }
    return (width, height)
}

func selectKForElements(k: Int) -> Int {
    if (k>0) {
        return k
    } else {
        // Seems like a magic number...
        return 16
    }
}

public func ==(lhs: RGBAPixel, rhs: RGBAPixel) -> Bool {
    return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b
}

func createRGBAContext(_ width: Int, height: Int) -> CGContext {
    return CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,          // bits per component
        bytesPerRow: width * 4,  // bytes per row
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
    )!
}

func enumerateRGBAContext(_ context: CGContext, handler: (Int, Int, RGBAPixel) -> Void) {
    /// Enumerates over all of the pixels in an RGBA bitmap context in the order that they are stored in memory, for faster access.
    /// From: https://www.mikeash.com/pyblog/friday-qa-2012-08-31-obtaining-and-interpreting-image-data.html
    
    let (width, height) = (context.width, context.height)
    let data = unsafeBitCast(context.data, to: UnsafeMutablePointer<RGBAPixel>.self)
    for y in 0..<height {
        for x in 0..<width {
            handler(x, y, data[Int(x + y * width)])
        }
    }
}

func RGBVectorToCGColor(_ rgbVector: GLKVector3) -> CGColor {
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [CGFloat(rgbVector.x), CGFloat(rgbVector.y), CGFloat(rgbVector.z), 1.0])!
}





// MARK: - ColorDifference

/// From: DominantColor pod - ColorDifference.swift
/// Created by Indragie on 12/22/14.
/// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.

/// These functions return the squared color difference because for distance calculations it doesn't matter and saves an unnecessary computation.

func CIE76SquaredColorDifference(_ lab1: GLKVector3, lab2: GLKVector3) -> Float {
    /// From http://www.brucelindbloom.com/index.html?Eqn_DeltaE_CIE76.html
    let (L1, a1, b1) = lab1.unpack()
    let (L2, a2, b2) = lab2.unpack()
    
    return pow(L2 - L1, 2) + pow(a2 - a1, 2) + pow(b2 - b1, 2)
}

func C(_ a: Float, b: Float) -> Float {
    return sqrt(pow(a, 2) + pow(b, 2))
}

func CIE94SquaredColorDifference(
    /// From http://www.brucelindbloom.com/index.html?Eqn_DeltaE_CIE94.html
        _ kL: Float = 1,
        kC: Float = 1,
        kH: Float = 1,
        K1: Float = 0.045,
        K2: Float = 0.015
    ) -> (_ lab1:GLKVector3, _ lab2:GLKVector3) -> Float {
    
    return { (lab1:GLKVector3, lab2:GLKVector3) -> Float in
        
        let (L1, a1, b1) = lab1.unpack()
        let (L2, a2, b2) = lab2.unpack()
        let ΔL = L1 - L2
        
        let (C1, C2) = (C(a1, b: b1), C(a2, b: b2))
        let ΔC = C1 - C2
        
        let ΔH = sqrt(pow(a1 - a2, 2) + pow(b1 - b2, 2) - pow(ΔC, 2))
        
        let Sl: Float = 1
        let Sc = 1 + K1 * C1
        let Sh = 1 + K2 * C1
        
        return pow(ΔL / (kL * Sl), 2) + pow(ΔC / (kC * Sc), 2) + pow(ΔH / (kH * Sh), 2)
    }
}

func CIE2000SquaredColorDifference(
    /// From http://www.brucelindbloom.com/index.html?Eqn_DeltaE_CIE2000.html
        _ kL: Float = 1,
        kC: Float = 1,
        kH: Float = 1
    ) -> (_ lab1:GLKVector3, _ lab2:GLKVector3) -> Float {
    
    return { (lab1:GLKVector3, lab2:GLKVector3) -> Float in
        let (L1, a1, b1) = lab1.unpack()
        let (L2, a2, b2) = lab2.unpack()
        
        let ΔLp = L2 - L1
        let Lbp = (L1 + L2) / 2
        
        let (C1, C2) = (C(a1, b: b1), C(a2, b: b2))
        let Cb = (C1 + C2) / 2
        
        let G = (1 - sqrt(pow(Cb, 7) / (pow(Cb, 7) + pow(25, 7)))) / 2
        let ap: (Float) -> Float = { a in
            return a * (1 + G)
        }
        let (a1p, a2p) = (ap(a1), ap(a2))
        
        let (C1p, C2p) = (C(a1p, b: b1), C(a2p, b: b2))
        let ΔCp = C2p - C1p
        let Cbp = (C1p + C2p) / 2
        
        let hp: (Float, Float) -> Float = { ap, b in
            if ap == 0 && b == 0 { return 0 }
            let θ = GLKMathRadiansToDegrees(atan2(b, ap))
            return fmod(θ < 0 ? (θ + 360) : θ, 360)
        }
        let (h1p, h2p) = (hp(a1p, b1), hp(a2p, b2))
        let Δhabs = abs(h1p - h2p)
        let Δhp: Float = {
            if (C1p == 0 || C2p == 0) {
                return 0
            } else if Δhabs <= 180 {
                return h2p - h1p
            } else if h2p <= h1p {
                return h2p - h1p + 360
            } else {
                return h2p - h1p - 360
            }
        }()
        
        let ΔHp = 2 * sqrt(C1p * C2p) * sin(GLKMathDegreesToRadians(Δhp / 2))
        let Hbp: Float = {
            if (C1p == 0 || C2p == 0) {
                return h1p + h2p
            } else if Δhabs > 180 {
                return (h1p + h2p + 360) / 2
            } else {
                return (h1p + h2p) / 2
            }
        }()
        
        var T = 1
            - 0.17 * cos(GLKMathDegreesToRadians(Hbp - 30))
            + 0.24 * cos(GLKMathDegreesToRadians(2 * Hbp))
        
        T = T
            + 0.32 * cos(GLKMathDegreesToRadians(3 * Hbp + 6))
            - 0.20 * cos(GLKMathDegreesToRadians(4 * Hbp - 63))
        
        let Sl = 1 + (0.015 * pow(Lbp - 50, 2)) / sqrt(20 + pow(Lbp - 50, 2))
        let Sc = 1 + 0.045 * Cbp
        let Sh = 1 + 0.015 * Cbp * T
        
        let Δθ = 30 * exp(-pow((Hbp - 275) / 25, 2))
        let Rc = 2 * sqrt(pow(Cbp, 7) / (pow(Cbp, 7) + pow(25, 7)))
        let Rt = -Rc * sin(GLKMathDegreesToRadians(2 * Δθ))
        
        let Lterm = ΔLp / (kL * Sl)
        let Cterm = ΔCp / (kC * Sc)
        let Hterm = ΔHp / (kH * Sh)
        return pow(Lterm, 2) + pow(Cterm, 2) + pow(Hterm, 2) + Rt * Cterm * Hterm
    }
}






// MARK: - ColorSpaceConversion

/// From: DominantColor pod - ColorSpaceConversion.swift
/// Created by Jernej Strasner on 2/5/19.
/// Copyright © 2019 Indragie Karunaratne. All rights reserved.

// MARK: RGB
func RGBToSRGB(_ rgbVector: GLKVector3) -> GLKVector3 {
    return rgbVector
}

func SRGBToRGB(_ srgbVector: GLKVector3) -> GLKVector3 {
    return srgbVector
}

// MARK: SRGB
func SRGBToLinearSRGB(_ srgbVector: GLKVector3) -> GLKVector3 {
    func f(_ c: Float) -> Float {
        if (c <= 0.04045) {
            return c / 12.92
        } else {
            return powf((c + 0.055) / 1.055, 2.4)
        }
    }
    return GLKVector3Make(f(srgbVector.x), f(srgbVector.y), f(srgbVector.z))
}

func LinearSRGBToSRGB(_ lSrgbVector: GLKVector3) -> GLKVector3 {
    func f(_ c: Float) -> Float {
        if (c <= 0.0031308) {
            return c * 12.92
        } else {
            return (1.055 * powf(c, 1.0 / 2.4)) - 0.055
        }
    };
    return GLKVector3Make(f(lSrgbVector.x), f(lSrgbVector.y), f(lSrgbVector.z));
}

// MARK: XYZ (CIE 1931)
/// http://en.wikipedia.org/wiki/CIE_1931_color_space#Construction_of_the_CIE_XYZ_color_space_from_the_Wright.E2.80.93Guild_data

let LinearSRGBToXYZMatrix = GLKMatrix3(m: (
    0.4124, 0.2126, 0.0193,
    0.3576, 0.7152, 0.1192,
    0.1805, 0.0722, 0.9505
))

func LinearSRGBToXYZ(_ linearSrgbVector: GLKVector3) -> GLKVector3 {
    let unscaledXYZVector = GLKMatrix3MultiplyVector3(LinearSRGBToXYZMatrix, linearSrgbVector);
    return GLKVector3MultiplyScalar(unscaledXYZVector, 100.0);
}

let XYZToLinearSRGBMatrix = GLKMatrix3(m: (
    3.2406, -0.9689, 0.0557,
    -1.5372, 1.8758, -0.2040,
    -0.4986, 0.0415, 1.0570
))

func XYZToLinearSRGB(_ xyzVector: GLKVector3) -> GLKVector3 {
    let scaledXYZVector = GLKVector3DivideScalar(xyzVector, 100.0);
    return GLKMatrix3MultiplyVector3(XYZToLinearSRGBMatrix, scaledXYZVector);
}

// MARK: LAB
/// http://en.wikipedia.org/wiki/Lab_color_space#CIELAB-CIEXYZ_conversions

func XYZToLAB(_ xyzVector: GLKVector3, _ tristimulus: GLKVector3) -> GLKVector3 {
    func f(_ t: Float) -> Float {
        if (t > powf(6.0 / 29.0, 3.0)) {
            return powf(t, 1.0 / 3.0)
        } else {
            return ((1.0 / 3.0) * powf(29.0 / 6.0, 2.0) * t) + (4.0 / 29.0)
        }
    };
    let fx = f(xyzVector.x / tristimulus.x)
    let fy = f(xyzVector.y / tristimulus.y)
    let fz = f(xyzVector.z / tristimulus.z)

    let l = (116.0 * fy) - 16.0
    let a = 500 * (fx - fy)
    let b = 200 * (fy - fz)

    return GLKVector3Make(l, a, b)
}

func LABToXYZ(_ labVector: GLKVector3, _ tristimulus: GLKVector3) -> GLKVector3 {
    func f(_ t: Float) -> Float {
        if (t > (6.0 / 29.0)) {
            return powf(t, 3.0)
        } else {
            return 3.0 * powf(6.0 / 29.0, 2.0) * (t - (4.0 / 29.0))
        }
    };
    let c = (1.0 / 116.0) * (labVector.x + 16.0)

    let y = tristimulus.y * f(c)
    let x = tristimulus.x * f(c + ((1.0 / 500.0) * labVector.y))
    let z = tristimulus.z * f(c - ((1.0 / 200.0) * labVector.z))

    return GLKVector3Make(x, y, z)
}

// MARK: Public
/// From http://www.easyrgb.com/index.php?X=MATH&H=15#text15

let D65Tristimulus = GLKVector3Make(5.047, 100.0, 108.883)

func IN_RGBToLAB(_ gVector: GLKVector3) -> GLKVector3 {
    let srgbVector = RGBToSRGB(gVector)
    let lSrgbVector = SRGBToLinearSRGB(srgbVector)
    let xyzVector = LinearSRGBToXYZ(lSrgbVector)
    let labVector = XYZToLAB(xyzVector, D65Tristimulus)
    return labVector
}

func IN_LABToRGB(_ gVector: GLKVector3) -> GLKVector3 {
    let xyzVector = LABToXYZ(gVector, D65Tristimulus)
    let lSrgbVector = XYZToLinearSRGB(xyzVector)
    let srgbVector = LinearSRGBToSRGB(lSrgbVector)
    let rgbVector = SRGBToRGB(srgbVector)
    return rgbVector
}






// MARK: - Memoization

/// From: DominantColor pod - Memoization.swift
/// Created by Emmanuel Odeke on 2014-12-25.
/// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.

func memoize<T: Hashable, U>(_ f: @escaping (T) -> U) -> (T) -> U {
    var cache = [T : U]()
    
    return { key in
        var value = cache[key]
        if value == nil {
            value = f(key)
            cache[key] = value
        }
        return value!
    }
}
