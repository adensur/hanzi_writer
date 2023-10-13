//
//  Geometry.swift
//  TongueScribbler
//
//  Created by Maksim Gaiduk on 20/09/2023.
//

import Foundation

func findArcCenter(start: CGPoint, end: CGPoint, radius: Double) -> (CGPoint, CGPoint)? {
    // Step 1: Calculate Midpoint
    let midX = (start.x + end.x) / 2.0
    let midY = (start.y + end.y) / 2.0
    
    // Step 2: Find Perpendicular Bisector
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    
    // Handle the case where deltaX is 0 to prevent division by zero
    guard deltaX != 0 else { return nil }
    
    let slope = deltaY / deltaX
    let perpSlope = -1 / slope
    
    // Step 3: Solve for Center Points
    // Here, we calculate the distance to move along the bisector line to find the center points.
    let d = sqrt(pow(radius, 2) - (pow(deltaX / 2, 2) + pow(deltaY / 2, 2)))
    let angle = atan(perpSlope)
    let center1 = CGPoint(x: midX + d * cos(angle), y: midY + d * sin(angle))
    let center2 = CGPoint(x: midX - d * cos(angle), y: midY - d * sin(angle))

    return (center1, center2)
}

enum EQuarter {
    case first, second, third, fourth
}

func getQuarter(_ p1: CGPoint, _ p2: CGPoint) -> EQuarter {
    let dx = p2.x - p1.x
    let dy = p2.y - p1.y
    if dx >= 0 && dy >= 0 {
        return .first
    }
    if dx < 0 && dy >= 0 {
        return .second
    }
    if dx < 0 && dy < 0 {
        return .third
    }
    if dx >= 0 && dy < 0 {
        return .fourth
    }
    return .first
}

func length(curve: [CGPoint]) -> CGFloat {
    var lastPoint = curve[0]
    let pointsSansFirst = Array(curve.dropFirst())
    return pointsSansFirst.reduce(0.0) { (acc, point) -> CGFloat in
        let dist = distance(lastPoint, point)
        lastPoint = point
        return acc + dist
    }
}
