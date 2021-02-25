//
//  KMeans.swift
//  DominantColor
//
//  Created by Indragie on 12/20/14.
//  Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
//

/// From: DominantColor pod - KMeans.swift
/// Created by Indragie on 12/20/14.
/// Copyright (c) 2014 Indragie Karunaratne. All rights reserved.

import Darwin
import GameKit

// Represents a type that can be clustered using the k-means clustering
// algorithm.
protocol ClusteredType {
    // Used to compute average values to determine the cluster centroids.
    static func +(lhs: Self, rhs: Self) -> Self
    static func /(lhs: Self, rhs: Int) -> Self
    
    // Identity value such that x + identity = x. Typically the 0 vector.
    static var identity: Self { get }
}

struct Cluster<T : ClusteredType> {
    let centroid: T
    let size: Int
}

// k-means clustering algorithm from
// http://users.eecs.northwestern.edu/~wkliao/Kmeans/

func kmeans<T : ClusteredType>(
        _ points: [T],
        k: Int,
        seed: UInt64,
        distance: ((T, T) -> Float),
        threshold: Float = 0.0001
    ) -> [Cluster<T>] {
            
    let n = points.count
    assert(k <= n, "k cannot be larger than the total number of points")

    var centroids = points.randomValues(k, seed: seed)
    var memberships = [Int](repeating: -1, count: n)
    var clusterSizes = [Int](repeating: 0, count: k)
    
    var error: Float = 0
    var previousError: Float = 0
    
    repeat {
        error = 0
        var newCentroids = [T](repeating: T.identity, count: k)
        var newClusterSizes = [Int](repeating: 0, count: k)
        
        for i in 0..<n {
            let point = points[i]
            let clusterIndex = findNearestCluster(point, centroids: centroids, k: k, distance: distance)
            if memberships[i] != clusterIndex {
                error += 1
                memberships[i] = clusterIndex
            }
            newClusterSizes[clusterIndex] += 1
            newCentroids[clusterIndex] = newCentroids[clusterIndex] + point
        }
        for i in 0..<k {
            let size = newClusterSizes[i]
            if size > 0 {
                centroids[i] = newCentroids[i] / size
            }
        }
        
        clusterSizes = newClusterSizes
        previousError = error
    } while abs(error - previousError) > threshold
    
    return zip(centroids, clusterSizes).map { Cluster(centroid: $0, size: $1) }
}

private func findNearestCluster<T : ClusteredType>(_ point: T, centroids: [T], k: Int, distance: (T, T) -> Float) -> Int {
    var minDistance = Float.infinity
    var clusterIndex = 0
    for i in 0..<k {
        let distance = distance(point, centroids[i])
        if distance < minDistance {
            minDistance = distance
            clusterIndex = i
        }
    }
    return clusterIndex
}

private extension Array {
    func randomValues(_ num: Int, seed: UInt64) -> [Element] {
        if self.isEmpty {
            return self
        }
        let rs = GKMersenneTwisterRandomSource()
        rs.seed = seed

        let rd = GKRandomDistribution(randomSource: rs, lowestValue: 0, highestValue: self.count - 1)

        var indices = [Int]()
        indices.reserveCapacity(num)

        for _ in 0..<num {
            var random = 0
            repeat {
                random = rd.nextInt()
            } while indices.contains(random)
            indices.append(random)
        }

        return indices.map { self[$0] }
    }
}


// MARK: ColorDifference (DISTANCE)
/// These functions return the squared color difference because for distance calculations it doesn't matter and saves an unnecessary computation.

func C(_ a: Float, b: Float) -> Float {
    return sqrt(pow(a, 2) + pow(b, 2))
}

func CIE76SquaredColorDifference(_ lab1: Pixel, lab2: Pixel) -> Float {
    /// From http://www.brucelindbloom.com/index.html?Eqn_DeltaE_CIE76.html
    let L1 = Float(lab1.v1),
        a1 = Float(lab1.v2),
        b1 = Float(lab1.v3);
    let L2 = Float(lab2.v1),
        a2 = Float(lab2.v2),
        b2 = Float(lab2.v3);
    
    return pow(L2 - L1, 2) + pow(a2 - a1, 2) + pow(b2 - b1, 2)
}

func CIE94SquaredColorDifference(
        _ kL: Float = 1, kC: Float = 1, kH: Float = 1,
        K1: Float = 0.045, K2: Float = 0.015
    ) -> (_ lab1:Pixel, _ lab2:Pixel) -> Float {
    /// From http://www.brucelindbloom.com/index.html?Eqn_DeltaE_CIE94.html
    return { (lab1:Pixel, lab2:Pixel) -> Float in
        let L1 = Float(lab1.v1),
            a1 = Float(lab1.v2),
            b1 = Float(lab1.v3);
        let L2 = Float(lab1.v1),
            a2 = Float(lab1.v2),
            b2 = Float(lab1.v3);
        
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

func CIE2000SquaredColorDifference(_ kL: Float = 1, kC: Float = 1, kH: Float = 1) -> (_ lab1:Pixel, _ lab2:Pixel) -> Float {
    /// From http://www.brucelindbloom.com/index.html?Eqn_DeltaE_CIE2000.html
    return { (lab1:Pixel, lab2:Pixel) -> Float in
        let L1 = Float(lab1.v1),
            a1 = Float(lab1.v2),
            b1 = Float(lab1.v3);
        let L2 = Float(lab1.v1),
            a2 = Float(lab1.v2),
            b2 = Float(lab1.v3);
        
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
