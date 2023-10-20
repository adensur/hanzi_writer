//
//  CharacterView.swift
//  TongueScribbler
//
//  Created by Maksim Gaiduk on 17/09/2023.
//

import SwiftUI

fileprivate func scalePoint(_ point: CGPoint, scale: Double) -> CGPoint {
    return CGPoint(x: point.x * scale, y: point.y * scale)
}

fileprivate func scalePoints(_ points: [CGPoint], width: Double, height: Double) -> [CGPoint] {
    let size = min(width, height)
    return points.map {point in
        if width < height {
            let delta = height - width
            let y = point.y - delta / 2.0
            return CGPoint(x: point.x / size, y: y / size)
        } else {
            let delta = width - height
            let x = point.x - delta / 2.0
            return CGPoint(x: x / size, y: point.y / size)
        }
    }
}

func normalizeAngle(_ angle: Angle) -> Angle {
    var angle = angle
    if angle.radians > .pi / 2.0 {
        angle.radians -= .pi
    }
    if angle.radians < -.pi / 2.0 {
        angle.radians += .pi
    }
    return angle
}

fileprivate func processPathComponents(components: [StrokePathComponent], scaleFactor: Double, path: inout Path) {
//    print("processPathComponents\n\n")
    for component in components {
//        print("Component: ", component)
        switch component {
        case .move(let to):
            path.move(to: scalePoint(to, scale: scaleFactor))
        case .addQuadCurve(let to, let control):
            path.addQuadCurve(to: scalePoint(to, scale: scaleFactor), control: scalePoint(control, scale: scaleFactor))
        case .addCurve(let to, let control1, let control2):
            path.addCurve(to: scalePoint(to, scale: scaleFactor), control1: scalePoint(control1, scale: scaleFactor), control2: scalePoint(control2, scale: scaleFactor))
        case .addLine(let to):
            path.addLine(to: scalePoint(to, scale: scaleFactor))
        case .closeSubpath:
            ()
            path.closeSubpath()
        case .Arc(radiusX: let radiusX, largeArc: let largeArc, sweep: let sweep, to: let to):
            let to = scalePoint(to, scale: scaleFactor)
            let startPoint = path.currentPoint!
            let radius = radiusX * scaleFactor
//            print("radius: ", radius)
            let centers = findArcCenter(start: startPoint, end: to, radius: radius)!
//            print("Centers: ", centers)
            // choose proper center depending on the current quarter
            //
            let quarter = getQuarter(startPoint, to)
            let center: CGPoint
            if quarter == .first || quarter == .second {
                center = sweep ? centers.1 : centers.0
            } else {
                center = sweep ? centers.0 : centers.1
            }
            let startAngle = Angle(degrees: atan2(startPoint.y - center.y, startPoint.x - center.x) * 180 / .pi)
            let endAngle = Angle(degrees: atan2(to.y - center.y, to.x - center.x) * 180 / .pi)
//            print("Original start/end angle, sweep: ", startAngle, endAngle, sweep)
//            print("Start point \(startPoint), end point \(to), center: \(center)")
            var clockwise = !sweep
            if largeArc {
                clockwise.toggle()
            }
//            print("Normalised start/end angle: ", startAngle, endAngle)
            path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
            
//            path.move(to: to)
        }
    }
}

struct TCharacterOutlineShape : Shape {
    var character: TCharacter
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        let scaleFactor = min(width, height)
        for stroke in character.strokes {
            processPathComponents(components: stroke.outline, scaleFactor: scaleFactor, path: &path)
        }
        return path
    }
}

struct TStrokeShape: Shape {
    var medians: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        let scaleFactor = min(width, height)
        if let first = medians.first {
            path.move(to: scalePoint(first, scale: scaleFactor))
            for point in medians.dropFirst() {
                path.addLine(to: scalePoint(point, scale: scaleFactor))
            }
        }
        return path
    }
}

struct TStrokeOutlineShape: Shape {
    var outline: [StrokePathComponent]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        let scaleFactor = min(width, height)
        processPathComponents(components: outline, scaleFactor: scaleFactor, path: &path)
        return path
    }
}

struct TCrossHair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        // horizontal line
        path.move(to: CGPoint(x: 0.0, y: height / 2.0))
        path.addLine(to: CGPoint(x: width, y: height / 2.0))
        path.closeSubpath()
        // vertical line
        path.move(to: CGPoint(x: width / 2.0, y: 0.0))
        path.addLine(to: CGPoint(x: width / 2.0, y: height))
        path.closeSubpath()
        // diagonal line from top left to bottom right
        path.move(to: CGPoint(x: width / 8.0, y: height / 8.0))
        path.addLine(to: CGPoint(x: 7.0 * width / 8.0, y: 7.0 * height / 8.0))
        path.closeSubpath()
        // diagonal line from top right to bottom left
        path.move(to: CGPoint(x: 7.0 * width / 8.0, y: height / 8.0))
        path.addLine(to: CGPoint(x: width / 8.0, y: 7.0 * height / 8.0))
        path.closeSubpath()
        return path
    }
}

public struct CharacterView: View {
    var character: TCharacter

    public init(character: TCharacter) {
        self.character = character
    }

    public var body: some View {
        GeometryReader {proxy in
            let size = min(proxy.size.width, proxy.size.height)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        TCrossHair()
                            .stroke(.gray.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6]))
                        TCharacterOutlineShape(character: character)
                            .fill(.primary)
                    }
                    .frame(width: size, height: size)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

public struct AnimatableCharacterView: View {
    let character: TCharacter
    @State private var startDate = Date.now
    var showOutline: Bool = true
    
    public init(character: TCharacter, showOutline: Bool) {
        self.character = character
        self.startDate = startDate
        self.showOutline = showOutline
    }
    
    public var body: some View {
        GeometryReader {proxy in
            let size = min(proxy.size.width, proxy.size.height)
            TimelineView(.animation) {timeline in
                let timeDelta = timeline.date.timeIntervalSince(startDate)
                let drawProgress = computeDrawProgress(timeDelta)
                ZStack {
                    TCrossHair()
                        .stroke(.gray.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6]))
                    TCharacterOutlineShape(character: character)
                        .fill(showOutline ? .gray : .white.opacity(0.0))
                    ForEach(0..<drawProgress.count, id: \.self) {idx in
                        TStrokeShape(medians: character.strokes[idx].medians)
                        .trim(to: drawProgress[idx])
                        .stroke(.blue, style: StrokeStyle(lineWidth: 60, lineCap: .round, lineJoin: .round))
                        .mask {
                            TStrokeOutlineShape(outline: character.strokes[idx].outline)
                                .fill(.primary)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            startDate = Date.now
        }
    }
    
    func delayBetweenStrokes(_ idx: Int) -> Double {
        if idx + 1 < character.strokeMap.count {
            if character.strokeMap[idx] != character.strokeMap[idx + 1] {
                return 0.3
            }
        }
        return 0.0
    }
    
    func computeDrawProgress(_ timeDelta: TimeInterval) -> [Double] {
        var result: [Double] = []
        let initialDelay = 0.3
        let finalDelay = 0.5
        let speed = 1.0
        let totalAnimationDuration = character.strokes.enumerated().reduce(into: initialDelay) {totalDuration, pair in
            let idx = pair.0
            let stroke = pair.1
            totalDuration += length(curve: stroke.medians) / speed + delayBetweenStrokes(idx)
        } + finalDelay
        var accumulatedDelay = 0.0
        let modulo = timeDelta.truncatingRemainder(dividingBy: totalAnimationDuration)
        if modulo < initialDelay {
            return character.strokes.map {_ in
                return 0.0
            }
        }
        let modulo2 = modulo - initialDelay
        for idx in 0..<character.strokes.count {
            let stroke = character.strokes[idx]
            let strokeDuration = length(curve: stroke.medians) / speed
            if modulo2 < accumulatedDelay {
                result.append(0.0)
            } else {
                let progress = min(1.0, (modulo2 - accumulatedDelay) / strokeDuration)
                result.append(progress)
            }
            accumulatedDelay += strokeDuration + delayBetweenStrokes(idx)
        }
        return result
    }
}

struct Particle {
    var position: CGPoint
    let deathDate = Date.now.timeIntervalSinceReferenceDate + 1.0
}

class UserStroke {
    var particles: [Particle] = []
    var points: [CGPoint] = []
    func addPoint(_ point: CGPoint) {
        particles.append(.init(position: point))
        points.append(point)
    }
    func update(date: TimeInterval) {
        particles = particles.filter { $0.deathDate > date }
    }
}

public class UserStrokes {
    var strokes: [UserStroke] = [.init()]
    
    public init() {
    }

    func update(date: TimeInterval) {
        var toRemove = IndexSet()
        for (index, stroke) in strokes.enumerated() {
            stroke.update(date: date)
            if index != strokes.indices.last! && stroke.particles.isEmpty {
                toRemove.insert(index)
            }
        }
        strokes.remove(atOffsets: toRemove)
    }
}

public class QuizDataModel: ObservableObject {
    @Published public var character: TCharacter
    @Published public var showOutline: Bool
    @Published public var canvasEnabled: Bool
    @Published public var currentMatchingIdx = 0
    @Published public var drawProgress: [Double] = []
    public var onSuccess: () -> Void
    public init(character: TCharacter, showOutline: Bool = true, canvasEnabled: Bool = true, onSuccess: @escaping () -> Void) {
        self.character = character
        self.showOutline = showOutline
        self.canvasEnabled = canvasEnabled
        self.onSuccess = onSuccess
        drawProgress = character.strokes.map {_ in
            return 0.0
        }
    }
    
    public func animateStrokes() {
        print("Data model animate strokes called!")
        let oldProgress = drawProgress
        for idx in 0..<drawProgress.count {
            drawProgress[idx] = 0.0
        }
        var delay = 0.3
        for idx in 0..<character.strokes.count {
            withAnimation(.easeInOut(duration: 0.5).delay(delay)) {
                drawProgress[idx] = 1.0
            }
            delay += 0.8
        }
        // return to initial state
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.drawProgress = oldProgress
        }
    }
    
    public func resetProgress() {
        currentMatchingIdx = 0
        drawProgress = character.strokes.map {_ in
            return 0.0
        }
    }
}

public struct QuizCharacterView : View {
    @ObservedObject var dataModel: QuizDataModel
    // use state for cache. Do not observe changes
    @State private var userStrokes = UserStrokes()
    @State private var failsInARow = 0
    @State private var matchFinishedFlash = false

    public init(dataModel: QuizDataModel) {
        self.dataModel = dataModel
    }

    func outlineColour(idx: Int) -> Color {
        if matchFinishedFlash {
            return .blue
        }
        if dataModel.currentMatchingIdx > idx {
            return .primary
        }
        if dataModel.showOutline {
            return .secondary
        }
        return .white.opacity(.zero)
    }
    public var body: some View {
        GeometryReader {proxy in
            VStack {
                let width = proxy.size.width
                let height = proxy.size.height
                let size = min(width, height)
                ZStack {
                    Group {
                        TCrossHair()
                            .stroke(.gray.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6]))
                        // use reversed range so that strokes drawn first are on the top
                        // StrokeOutline - the actual drawing of a character
                        ForEach((0..<dataModel.character.strokes.count).reversed(), id: \.self) {idx in
                            TStrokeOutlineShape(outline: dataModel.character.strokes[idx].outline)
                                .fill(outlineColour(idx: idx))
                        }
                        
                    }
                    .frame(width: size, height: size)
                    if dataModel.drawProgress.count > 0 {
                        // simple stroke along the character stroke.
                        // since its masked by the outline, it looks good enough
                        ForEach(0..<dataModel.drawProgress.count, id: \.self) {idx in
                            if idx < dataModel.character.strokes.count {
                                TStrokeShape(medians: dataModel.character.strokes[idx].medians)
                                   .trim(to: dataModel.drawProgress[idx])
                                   .stroke(.blue.opacity(0.7), style: StrokeStyle(lineWidth: 50, lineCap: .round, lineJoin: .miter))
                                   .mask {
                                       TStrokeOutlineShape(outline: dataModel.character.strokes[idx].outline)
                                   }
                            }
                        }
                        .frame(width: size, height: size)
                        if dataModel.canvasEnabled {
                            TimelineView(.animation) {timeline in
                                Canvas {ctx, size in
                                    let timelineDate = timeline.date.timeIntervalSinceReferenceDate
                                    userStrokes.update(date: timelineDate)
                                    ctx.blendMode = .plusLighter
                                    ctx.addFilter(.blur(radius: 3))
                                    ctx.addFilter(.alphaThreshold(min: 0.3, color: .primary))
                                    for stroke in userStrokes.strokes {
                                        var path = Path()
                                        if let first = stroke.particles.first {
                                            path.move(to: first.position)
                                            for particle in stroke.particles.dropFirst() {
                                                ctx.opacity = (particle.deathDate - timelineDate) * 1.5
                                                path.addLine(to: particle.position)
                                                ctx.stroke(path, with: .color(.primary), lineWidth: 10)
                                                path = Path()
                                                path.move(to: particle.position)
                                            }
                                        }
                                    }
                                }
                            }
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged {drag in
                                    if let stroke = userStrokes.strokes.last {
                                        stroke.addPoint(drag.location)
                                    }
                                }
                                .onEnded {drag in
                                    // match the previous stroke
                                    var mergedCharacterStroke: [CGPoint] = []
                                    var subStrokeCount = 0
                                    let strokeToMatch = dataModel.character.strokeMap[dataModel.currentMatchingIdx]
                                    var subStrokeIndices: [Int] = []
                                    for idx in 0..<dataModel.character.strokeMap.count {
                                        if dataModel.character.strokeMap[idx] == strokeToMatch {
                                            mergedCharacterStroke.append(contentsOf: dataModel.character.strokes[idx].medians)
                                            subStrokeCount += 1
                                            subStrokeIndices.append(idx)
                                        }
                                    }
                                    if strokesMatch(userStroke: scalePoints(userStrokes.strokes.last!.points, width: width, height: height), characterStroke: mergedCharacterStroke) {
                                        failsInARow = 0
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            dataModel.currentMatchingIdx += subStrokeCount
                                        }
                                        if dataModel.currentMatchingIdx == dataModel.character.strokes.count {
                                            withAnimation(.easeInOut(duration: 0.3).delay(0.5)) {
                                                matchFinishedFlash = true
                                            }
                                            withAnimation(.easeInOut(duration: 0.3).delay(0.8)) {
                                                matchFinishedFlash = false
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                                dataModel.onSuccess()
                                            }
                                        }
                                    } else {
                                        // trigger stroke animation after N successive failures
                                        failsInARow += 1
                                        if failsInARow >= 3 {
                                            var delay = 0.0
                                            let strokeTooltipDuration = 0.5
                                            for idx in subStrokeIndices {
                                                withAnimation(.easeInOut(duration: strokeTooltipDuration).delay(delay)) {
                                                    dataModel.drawProgress[idx] = 1.0
                                                }
                                                delay += strokeTooltipDuration
                                            }
                                            for idx in subStrokeIndices {
                                                withAnimation(.easeInOut(duration: 0.05).delay(delay + 0.3)) {
                                                    dataModel.drawProgress[idx] = 0.0
                                                }
                                            }
                                        }
                                    }
                                    userStrokes.strokes.append(.init())
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
