//
//  StrokeMatch.swift
//  TongueScribbler
//
//  Created by Maksim Gaiduk on 18/09/2023.
//

import Foundation

func average<T: FloatingPoint>(_ values: [T]) -> T {
    // Implement the logic for calculating the average
    return values.reduce(0, +) / T(values.count) // Placeholder implementation
}

func dedup(_ stroke: [CGPoint]) -> [CGPoint] {
    if stroke.count <= 1 {
        return stroke
    }
    var res = Array<CGPoint>()
    for idx in 1..<stroke.count {
        if stroke[idx] != stroke[idx - 1] {
            res.append(stroke[idx])
        }
    }
    return res
}

func distance(_ point1: CGPoint, _ point2: CGPoint) -> Double {
    let xDist = point2.x - point1.x
    let yDist = point2.y - point1.y
    return sqrt((xDist * xDist) + (yDist * yDist))
}

func averageDistance(from: [CGPoint], to: [CGPoint]) -> Double {
    return to.reduce(0.0) {total, point in
        let distances = from.map { distance($0, point)}
        let newDistance = distances.min()!
        return total + newDistance
    } / Double(to.count)
}

func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

func getVectors(_ points: [CGPoint]) -> [CGPoint] {
    var result = Array<CGPoint>()
    for idx in 1..<points.count {
        result.append(points[idx] - points[idx - 1])
    }
    return result
}

func cosineSimilarity(_ vector1: CGPoint, _ vector2: CGPoint) -> Double {
    let dotProduct = (vector1.x * vector2.x) + (vector1.y * vector2.y)
        let magnitude1 = sqrt((vector1.x * vector1.x) + (vector1.y * vector1.y))
        let magnitude2 = sqrt((vector2.x * vector2.x) + (vector2.y * vector2.y))
        
        guard magnitude1 != 0 && magnitude2 != 0 else {
            return 0.0 // or handle this case differently as you see fit
        }
        
        return dotProduct / (magnitude1 * magnitude2)
}

func avgCosineSimilarity(_ userStroke: [CGPoint], _ characterStroke: [CGPoint]) -> Double {
    let userVectors = getVectors(userStroke)
    let characterVectors = getVectors(characterStroke)
    let similarities = characterVectors.map {characterVector in
        let subSimilarities = userVectors.map {userVector in
            return cosineSimilarity(userVector, characterVector)
        }
        return subSimilarities.max()!
    }
    let avgSimilarity = average(similarities)
    return avgSimilarity
}

func outlineCurve(curve: [CGPoint], numPoints: Int = 30) -> [CGPoint] {
    let curveLen = length(curve: curve)
    let segmentLen = curveLen / CGFloat(numPoints - 1)
    var outlinePoints = [curve[0]]
    let endPoint = curve.last!
    var remainingCurvePoints = Array(curve.dropFirst())

    for _ in 0..<(numPoints - 2) {
        var lastPoint = outlinePoints.last!
        var remainingDist = segmentLen
        var outlinePointFound = false
        while !outlinePointFound {
            let nextPointDist = distance(lastPoint, remainingCurvePoints[0])
            if nextPointDist < remainingDist {
                remainingDist -= nextPointDist
                lastPoint = remainingCurvePoints.removeFirst()
            } else {
                let nextPoint = extendPointOnLine(p1: lastPoint, p2: remainingCurvePoints[0], dist: remainingDist - nextPointDist)
                outlinePoints.append(nextPoint)
                outlinePointFound = true
            }
        }
    }

    outlinePoints.append(endPoint)
    
    return outlinePoints
}

func magnitude(vect: CGPoint) -> CGFloat {
    return sqrt(vect.x * vect.x + vect.y * vect.y)
}

func extendPointOnLine(p1: CGPoint, p2: CGPoint, dist: CGFloat) -> CGPoint {
    let vect = p2 - p1
    let norm = dist / magnitude(vect: vect)
    return CGPoint(x: p2.x + norm * vect.x, y: p2.y + norm * vect.y)
}

func subdivideCurve(curve: [CGPoint], maxLen: CGFloat = 0.05) -> [CGPoint] {
    var newCurve = Array(curve.prefix(1))
    
    for point in curve.dropFirst() {
        guard let prevPoint = newCurve.last else { continue }
        let segLen = distance(point, prevPoint)
        
        if segLen > maxLen {
            let numNewPoints = Int(ceil(segLen / maxLen))
            let newSegLen = segLen / CGFloat(numNewPoints)
            
            for i in 0..<numNewPoints {
                newCurve.append(extendPointOnLine(p1: point, p2: prevPoint, dist: -1 * newSegLen * CGFloat(i + 1)))
            }
        } else {
            newCurve.append(point)
        }
    }
    
    return newCurve
}


func normalizeCurve(curve: [CGPoint]) -> [CGPoint] {
    let outlinedCurve = outlineCurve(curve: curve, numPoints: 30)
    let meanX = average(outlinedCurve.map { $0.x })
    let meanY = average(outlinedCurve.map { $0.y })
    let mean = CGPoint(x: meanX, y: meanY)
    let translatedCurve = outlinedCurve.map { $0 - mean }
    let scale = sqrt(
        average([
            pow(translatedCurve[0].x, 2) + pow(translatedCurve[0].y, 2),
            pow(translatedCurve.last!.x, 2) + pow(translatedCurve.last!.y, 2)
        ])
    )
    let scaledCurve = translatedCurve.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }
    return subdivideCurve(curve: scaledCurve)
}

func frechetDist(curve1: [CGPoint], curve2: [CGPoint]) -> CGFloat {
    let longCurve = curve1.count >= curve2.count ? curve1 : curve2
    let shortCurve = curve1.count >= curve2.count ? curve2 : curve1

    func calcVal(i: Int, j: Int, prevResultsCol: [CGFloat], curResultsCol: [CGFloat]) -> CGFloat {
        if i == 0 && j == 0 {
            return distance(longCurve[0], shortCurve[0])
        }

        if i > 0 && j == 0 {
            return max(prevResultsCol[0], distance(longCurve[i], shortCurve[0]))
        }

        let lastResult = curResultsCol.last!

        if i == 0 && j > 0 {
            return max(lastResult, distance(longCurve[0], shortCurve[j]))
        }

        return max(
            min(prevResultsCol[j], prevResultsCol[j - 1], lastResult),
            distance(longCurve[i], shortCurve[j])
        )
    }

    var prevResultsCol: [CGFloat] = []
    for i in 0..<longCurve.count {
        var curResultsCol: [CGFloat] = []
        for j in 0..<shortCurve.count {
            curResultsCol.append(calcVal(i: i, j: j, prevResultsCol: prevResultsCol, curResultsCol: curResultsCol))
        }
        prevResultsCol = curResultsCol
    }

    return prevResultsCol[shortCurve.count - 1]
}

func rotate(curve: [CGPoint], theta: CGFloat) -> [CGPoint] {
    return curve.map { point in
        let x = cos(theta) * point.x - sin(theta) * point.y
        let y = sin(theta) * point.x + cos(theta) * point.y
        return CGPoint(x: x, y: y)
    }
}


let SHAPE_FIT_ROTATIONS: [CGFloat] = [
    .pi / 16,
    .pi / 32,
    0,
    (-1 * .pi) / 32,
    (-1 * .pi) / 16,
]

let FRECHET_THRESHOLD: CGFloat = 0.4// define an appropriate value for this constant

func shapeFitDist(curve1: [CGPoint], curve2: [CGPoint]) -> Double {
    let normCurve1 = normalizeCurve(curve: curve1)
    let normCurve2 = normalizeCurve(curve: curve2)
    
    var minDist: CGFloat = .infinity
    for theta in SHAPE_FIT_ROTATIONS {
        let dist = frechetDist(curve1: normCurve1, curve2: rotate(curve: normCurve2, theta: theta))
        if dist < minDist {
            minDist = dist
        }
    }
    return minDist
}

let minLenThreshold = 0.55

func lengthMatch(userStroke: [CGPoint], characterStroke: [CGPoint]) -> Double {
    return (length(curve: userStroke) + 0.024) / (length(curve: characterStroke) + 0.024)
}

func strokesMatch(userStroke: [CGPoint], characterStroke: [CGPoint]) -> Bool {
    print("Trying to match strokes. User stroke: \(userStroke), character stroke: \(characterStroke)")
    let userStroke = dedup(userStroke)
    if userStroke.count <= 1 {
        return false
    }
    // check length match
    let lengthMatch = lengthMatch(userStroke: userStroke, characterStroke: characterStroke)
    print("Length match: ", lengthMatch)
    if lengthMatch < minLenThreshold {
        print("Rejected by length match")
        return false
    }
    // check the shape of the curve
    let shapeFitDist = shapeFitDist(curve1: userStroke, curve2: characterStroke)
    print("Shape fit dist: ", shapeFitDist)
    if shapeFitDist >= FRECHET_THRESHOLD {
        print("Rejected by shape fit")
        return false
    }
    let avgDistance = averageDistance(from: userStroke, to: characterStroke)
    print("Avg distance: \(avgDistance)")
    if avgDistance >= 0.1 {
        print("Rejected by avg distance")
        return false
    }
    // checking distance between start and end
    let startDistance = distance(userStroke.first!, characterStroke.first!)
    print("Start distance: ", startDistance)
    if startDistance > 0.15 {
        print("Rejected by start distance")
        return false
    }
    let endDistance = distance(userStroke.first!, characterStroke.first!)
    print("End distance: ", endDistance)
    if endDistance > 0.15 {
        print("Rejected by end distance")
        return false
    }
    // checking stroke direction
    let similarity = avgCosineSimilarity(userStroke, characterStroke)
    print("Avg cosine similarity: ", similarity)
    if similarity <= 0 {
        print("Rejected by stroke direction")
        return false
    }
    return true
}
