//
//  Extensions.swift
//  RockClassifier
//
//  Created by Sarah on 11/24/20.
//

import UIKit
import Accelerate
import Combine


public enum GroupingAccuracy {
    /// From: DominantColor pod - DominantColors.swift
    /// Created by Indragie on 12/20/14.
    /// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
    case low        // CIE 76 - Euclidian distance
    case medium     // CIE 94 - Perceptual non-uniformity corrections
    case high       // CIE 2000 - Additional corrections for neutral colors, lightness, chroma, and hue
}

public struct DefaultParameterValues {
    public static var accuracy: GroupingAccuracy = .low
    public static var seed: UInt64 = 1
    public static var memoizeConversions: Bool = false
    public static var scales: [String] = []
    public static var mins: [String] = []
}

func dominantColorsInImage(
    _ image: CGImage,
    accuracy: GroupingAccuracy = DefaultParameterValues.accuracy,
    seed: UInt64 = DefaultParameterValues.seed,
    memoizeConversions: Bool = DefaultParameterValues.memoizeConversions,
    n_clusters: Int
) -> [DominantColor] {
    
    /// Computes the dominant colors in an image
    /// - Parameters:
    ///   - Image: The image
    ///   - MaxSampledPixels: Maximum number of pixels to sample in the image. If the total number of pixels in the image exceeds this value, it will be downsampled to meet the constraint.
    ///   - Accuracy: Level of accuracy to use when grouping similar colors. Higher accuracy will come with a performance tradeoff.
    ///   - Seed: Seed to use when choosing the initial points for grouping of similar colors. The same seed is guaranteed to return the same colors every time.
    ///   - MemoizeConversions: Whether to memoize conversions from RGB to the LAB color space (used for grouping similar colors). Memoization will only yield better performance for large values of `maxSampledPixels` in images that are primarily comprised of flat colors. If this information about the image is not known beforehand, it is best to not memoize.
    /// - Returns: A list of dominant colors in the image sorted from most dominant to least dominant.
    
    let RGBvalues = image.pixelData()
    let LABvalues = RGBvalues!.map { rgb_to_lab(rgb: $0) }
    //let LABvalues = image.labData()!
    //print(LABvalues[0])
    
    /// Cluster the colors using the k-means algorithm
    var clusters = kmeans(LABvalues, k: n_clusters, seed: seed, distance: distanceForAccuracy(accuracy))
    //print(clusters[0])
    
    /// Sort the clusters by size in descending order so that the most dominant colors come first.
    clusters.sort { $0.size < $1.size }
    var total = 0
    for cluster in clusters {
        total += cluster.size
    }
    return clusters.map {DominantColor( Color: $0.centroid, percentage: Double($0.size)/Double(total) )}
}

func memoize<T: Hashable, U>(_ f: @escaping (T) -> U) -> (T) -> U {
    /// From: DominantColor pod - Memoization.swift
    /// Created by Emmanuel Odeke on 2014-12-25.
    /// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
    
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

func distanceForAccuracy(_ accuracy: GroupingAccuracy) -> (Pixel, Pixel) -> Float {
    /// From: DominantColor pod - ColorDifference.swift
    /// Created by Indragie on 12/22/14.
    /// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
    switch accuracy {
    case .low:
        return CIE76SquaredColorDifference
    case .medium:
        return CIE94SquaredColorDifference()
    case .high:
        return CIE2000SquaredColorDifference()
    }
}




// MARK: ColorSpaceConversions

func lab_to_rgb(lab: Pixel) -> Pixel {
    let xyz = lab_to_xyz(lab: lab)
    return xyz_to_rgb(xyz: xyz)
}

func rgb_to_lab(rgb: Pixel) -> Pixel {
    let xyz = rgb_to_xyz(rgb: rgb)
    return xyz_to_lab(xyz: xyz)
}

func rgb_to_cgcolor(_ rgb: Pixel) -> CGColor {
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                   components: [CGFloat(rgb.v1/255), CGFloat(rgb.v2/255), CGFloat(rgb.v3/255), 1.0])!
}

func rgb_to_xyz(rgb: Pixel) -> Pixel {
    /// Based on https://www.easyrgb.com/en/math.php
    ///sR, sG and sB (Standard RGB) input range = 0 ÷ 255
    ///X, Y and Z output refer to a D65/2° standard illuminant.

    var var_R = rgb.v1 / 255,
        var_G = rgb.v2 / 255,
        var_B = rgb.v3 / 255;

    if ( var_R > 0.04045 ) {
        var_R = Double(pow((var_R + 0.055)/1.055, 2.4))
    } else {
        var_R = var_R / 12.92
    }
    if ( var_G > 0.04045 ) {
        var_G = Double(pow((var_G + 0.055)/1.055, 2.4))
    } else {
        var_G = var_G / 12.92
    }
    if ( var_B > 0.04045 ) {
        var_B = Double(pow((var_B + 0.055)/1.055, 2.4))
    }
    else {
        var_B = var_B / 12.92
    }

    var_R = var_R * 100
    var_G = var_G * 100
    var_B = var_B * 100
    
    // [0.412453, 0.357580, 0.180423, 0.212671, 0.715160, 0.072169, 0.019334, 0.119193, 0.950227],
    
    let R = var_R * 0.412453 + var_G * 0.357580 + var_B * 0.180423,
        G = var_R * 0.212671 + var_G * 0.715160 + var_B * 0.072169,
        B = var_R * 0.019334 + var_G * 0.119193 + var_B * 0.950227
    
    return Pixel(v1: R, v2: G, v3: B)
}

func xyz_to_lab(xyz: Pixel) -> Pixel {
    /// Based on https://www.easyrgb.com/en/math.php
    ///Reference-X, Y and Z refer to specific illuminants and observers.
    ///Common reference values are available below in this same page.

    var var_X = xyz.v1 / 95.047,
        var_Y = xyz.v2 / 100.0,
        var_Z = xyz.v3 / 108.883;

    if ( var_X > 0.008856 ) {
        var_X = Double(pow(var_X, 1/3))
    } else {
        var_X = ( 7.787 * var_X ) + ( 16 / 116 )
    }
    if ( var_Y > 0.008856 ) {
        var_Y = Double(pow(var_Y, 1/3))
    } else {
        var_Y = ( 7.787 * var_Y ) + ( 16 / 116 )
    }
    if ( var_Z > 0.008856 ) {
        var_Z = Double(pow(var_Z, 1/3))
    } else {
        var_Z = ( 7.787 * var_Z ) + ( 16 / 116 )
    }
    
    return Pixel(v1: ( 116 * var_Y ) - 16,
                 v2: 500 * ( var_X - var_Y ),
                 v3: 200 * ( var_Y - var_Z ))
}

func lab_to_xyz(lab: Pixel) -> Pixel {
    /// Based on https://www.easyrgb.com/en/math.php
    ///Reference-X, Y and Z refer to specific illuminants and observers.
    ///Common reference values are available below in this same page.

    var var_A = ( lab.v1 + 16 ) / 116,
        var_L = lab.v2 / 500 + var_A,
        var_B = var_A - lab.v3 / 200;

    if ( Double(pow(var_A, 3)) > 0.008856 ) {
        var_A = Double(pow(var_A, 3))
    } else {
        var_A = ( var_A - 16 / 116 ) / 7.787
    }
    if ( Double(pow(var_L, 3)) > 0.008856 ) {
        var_L = Double(pow(var_L, 3))
    } else {
        var_L = ( var_L - 16 / 116 ) / 7.787
    }
    if ( Double(pow(var_B, 3)) > 0.008856 ) {
        var_B = Double(pow(var_B, 3))
    } else {
        var_B = ( var_B - 16 / 116 ) / 7.787
    }
    
    return Pixel(v1: var_L * 95.047,
                 v2: var_A * 100.0,
                 v3: var_B * 108.883)
}

func xyz_to_rgb(xyz: Pixel) -> Pixel {
    /// Based on https://www.easyrgb.com/en/math.php
    /// X, Y and Z input refer to a D65/2° standard illuminant.
    /// sR, sG and sB (standard RGB) output range = 0 ÷ 255

    let var_X = xyz.v1 / 100,
        var_Y = xyz.v2 / 100,
        var_Z = xyz.v3 / 100;

    var var_R = var_X *  3.2406 + var_Y * -1.5372 + var_Z * -0.4986,
        var_G = var_X * -0.9689 + var_Y *  1.8758 + var_Z *  0.0415,
        var_B = var_X *  0.0557 + var_Y * -0.2040 + var_Z *  1.0570;

    if ( var_R > 0.0031308 ) {
        var_R = 1.055 * Double(pow(var_R, 1/2.4)) - 0.055
    } else {
        var_R = 12.92 * var_R
    }
    if ( var_G > 0.0031308 ) {
        var_G = 1.055 * Double(pow(var_G, 1/2.4)) - 0.055
    } else {
        var_G = 12.92 * var_G
    }
    if ( var_B > 0.0031308 ) {
        var_B = 1.055 * Double(pow(var_B, 1/2.4)) - 0.055
    } else {
        var_B = 12.92 * var_B
    }

    return Pixel(v1: var_R * 255,
                 v2: var_G * 255,
                 v3: var_B * 255)
}
