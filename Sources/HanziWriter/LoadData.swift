//
//  LoadData.swift
//  HanziWriter
//
//  Created by Maksim Gaiduk on 17/09/2023.
//

import Foundation

enum StrokePathComponent: Equatable {
    case move(to: CGPoint)
    case addQuadCurve(to: CGPoint, control: CGPoint)
    case addCurve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case addLine(to: CGPoint)
    case closeSubpath
    case Arc(radiusX: Double, largeArc: Bool, sweep: Bool, to: CGPoint)
    
    // used in tests for easy fixed-precision comparison
    func toString() -> String {
        switch self {
        case .move(let to):
            return String(format: "M %.2f %.2f", to.x, to.y)
        case .addQuadCurve(let to, let control):
            return String(format: "Q %.2f %.2f %.2f %.2f", control.x, control.y, to.x, to.y)
        case .addCurve(let to, let control1, let control2):
            return String(format: "C %.2f %.2f %.2f %.2f %.2f %.2f", control1.x, control1.y, control2.x, control2.y, to.x, to.y)
        case .addLine(let to):
            return String(format: "L %.2f %.2f", to.x, to.y)
        case .closeSubpath:
            return "Z"
        case .Arc(let radiusX, let largeArc, let sweep, let to):
            return String(format: "A %.2f %d %d %2.f %2.f", radiusX, largeArc, sweep, to.x, to.y)
        }
    }
}

struct StrokeData: Identifiable {
    var id: Int
    var outline: [StrokePathComponent]
    var medians: [CGPoint]
}

public struct TCharacter: Sendable {
    let character: String
    // parsed SVG path data
    let strokes: [StrokeData]
    let strokeMap: [Int]
}

// struct for JSON deserialization
public struct CharacterData: Decodable {
    // actual character, like "我"
    var character: String
    // SVG drawing of a character, divided into strokes
    var strokes: [String]
    // median points used for animation and stoke matching of the strokes
    var medians: [[[Double]]]
    // has to be equal
    // provides the scale of the SVG image so that we can remap it properly
    // we check that width == height to make sure we don't distort the symbol (+ distorted Arcs are not supported)
    var width: Double?
    var height: Double?
    // x and y offsets are used to "center" characters from multiple sources
    var xOffset: Double?
    var yOffset: Double?
    // used to merge several strokes into one
    // splitting a stroke into several makes animation smoother in some cases
    // we still need to teach proper strokes though
    // format: graphical stroke index -> logical stroke index
    var strokeMap: [Int]?
}

enum svgParseError: Error {
    case invalidNumber
    case unexpectedCharacter
    case leadingNumbers
    case argumentError // wrong number of stack arguments
    case unequalRadius // not supported yet
    case arcRotation // not supported yet
    case missingControlPoint // no prev control point for s/S command
    case mediansMismatch // median count != svg path count
}

enum ECommand {
    case m, M, l, L, v, V, h, H, a, A, c, C, s, S, q, Q, z
    
    static func fromChar(_ ch: Character) -> ECommand? {
        switch ch {
        case "m":
            return .m
        case "M":
            return .M
        case "l":
            return .l
        case "L":
            return .L
        case "v":
            return .v
        case "V":
            return .V
        case "h":
            return .h
        case "H":
            return .H
        case "a":
            return .a
        case "A":
            return .A
        case "c":
            return .c
        case "C":
            return .C
        case "s":
            return .s
        case "S":
            return .S
        case "q":
            return .q
        case "Q":
            return .Q
        case "z":
            return .z
        case "Z":
            return .z
        default:
            return nil
        }
    }
}

struct TCommand: Equatable {
    let command: ECommand
    let coords: [Double]
}

func parseNumSequence(_ str: String) throws -> [TCommand] {
    // Parse a string like that:
    // -1.4-.8-2.4,1.1
    // spaces are equal to commas and are used as separators
    // . (dot) and - (minus) can be used as a separator if it is not ambiguous
    var idx = str.startIndex
    var result = [TCommand]()
    var currentCommand: ECommand? = nil
    var nums = [Double]()
    var buf = ""
    var metDot = false
    var metMinus = false
    let flushNums = {
        if !buf.isEmpty {
            if let num = Double(buf) {
                nums.append(num)
            } else {
                throw svgParseError.invalidNumber
            }
        }
        buf = ""
    }
    let flushCommand = {
        if let oldCommand = currentCommand {
            try flushNums()
            result.append(.init(command: oldCommand, coords: nums))
            nums.removeAll()
        } else {
            if !nums.isEmpty {
                throw svgParseError.leadingNumbers
            }
        }
    }
    while idx < str.endIndex {
        let ch = str[idx]
        if let command = ECommand.fromChar(ch) {
            try flushCommand()
            currentCommand = command
            idx = str.index(after: idx)
            continue
        }
        if ch == " " || ch == "," || (ch == "." && metDot) || (ch == "-" && (metMinus || metDot)) {
            try flushNums()
            if !(ch == "." || ch == "-") {
                idx = str.index(after: idx)
            }
            metDot = false
            metMinus = false
            continue
        }
        if ch == "." {
            metDot = true
            buf.append(ch)
            idx = str.index(after: idx)
            continue
        }
        if ch == "-" {
            metMinus = true
            buf.append(ch)
            idx = str.index(after: idx)
            continue
        }
        if ch >= "0" && ch <= "9" || ch == "." {
            metMinus = true
        }
        if ch == "+" || (ch >= "0" && ch <= "9") {
            buf.append(ch)
            idx = str.index(after: idx)
            continue
        }
        print("Unexpected character \(ch) at idx: \(idx) when parsing:\n\(str)")
        throw svgParseError.unexpectedCharacter
    }
    try flushCommand()
    return result
}

func reflectPoint(prevControl: CGPoint, curPoint: CGPoint) -> CGPoint {
    let newX = 2 * curPoint.x - prevControl.x
    let newY = 2 * curPoint.y - prevControl.y
    return CGPoint(x: newX, y: newY)
}

// scale == width == height
func parseSvgPath(_ path: String, remapPoint: (CGPoint) -> CGPoint, scale: Double) throws -> [StrokePathComponent] {
    let commands = try parseNumSequence(path)
    var result: [StrokePathComponent] = []
    var curPoint = CGPoint(x: 0.0, y: 0.0)
    var prevControl: CGPoint? = nil
    for command in commands {
        switch command.command {
        case .m:
            fallthrough
        case .M:
            guard command.coords.count % 2 == 0 else {
                print("Error when parsing command: \n\(path), command: \(command.command), coords: \(command.coords), expected coords.count % 2 == 0")
                throw svgParseError.argumentError
            }
            for idx in stride(from: 0, to: command.coords.count, by: 2) {
                let coordX = command.coords[idx]
                let coordY = command.coords[idx + 1]
                if command.command == .m {
                    curPoint.x += coordX
                    curPoint.y += coordY
                } else {
                    curPoint.x = coordX
                    curPoint.y = coordY
                }
                result.append(.move(to: remapPoint(curPoint)))
            }
        case .l:
            fallthrough
        case .L:
            guard command.coords.count % 2 == 0 else {
                print("Error when parsing command: \n\(path), command: \(command.command), coords: \(command.coords), expected coords.count % 2 == 0")
                throw svgParseError.argumentError
            }
            for idx in stride(from: 0, to: command.coords.count, by: 2) {
                let coordX = command.coords[idx]
                let coordY = command.coords[idx + 1]
                if command.command == .l {
                    curPoint.x += coordX
                    curPoint.y += coordY
                } else {
                    curPoint.x = coordX
                    curPoint.y = coordY
                }
                result.append(.addLine(to: remapPoint(curPoint)))
            }
        case .v:
            fallthrough
        case .V:
            for idx in 0..<command.coords.count {
                let coordY = command.coords[idx]
                if command.command == .v {
                    curPoint.y += coordY
                } else {
                    curPoint.y = coordY
                }
                result.append(.addLine(to: remapPoint(curPoint)))
            }
        case .h:
            fallthrough
        case .H:
            for idx in 0..<command.coords.count {
                let coordX = command.coords[idx]
                if command.command == .h {
                    curPoint.x += coordX
                } else {
                    curPoint.x = coordX
                }
                result.append(.addLine(to: remapPoint(curPoint)))
            }
        case .a:
            fallthrough
        case .A:
            guard command.coords.count % 7 == 0 else {
                print("Error when parsing command: \n\(path), command: \(command.command), coords: \(command.coords), expected coords.count % 7 == 0")
                throw svgParseError.argumentError
            }
            for idx in stride(from: 0, to: command.coords.count, by: 7) {
                let rX = command.coords[idx]
                let rY = command.coords[idx + 1]
                guard rX == rY else {
                    throw svgParseError.unequalRadius
                }
                let rotation = Int(command.coords[idx + 2])
                guard rotation == 0 else {
                    throw svgParseError.arcRotation
                }
                let largeArcFlag = command.coords[idx + 3] > 0
                let sweepFlag = command.coords[idx + 4] > 0
                let coordX = command.coords[idx + 5]
                let coordY = command.coords[idx + 6]
                if command.command == .a {
                    curPoint.x += coordX
                    curPoint.y += coordY
                } else {
                    curPoint.x = coordX
                    curPoint.y = coordY
                }
                result.append(.Arc(radiusX: rX, largeArc: largeArcFlag, sweep: sweepFlag, to: remapPoint(curPoint)))
            }
        case .c:
            fallthrough
        case .C:
            guard command.coords.count % 6 == 0 else {
                print("Error when parsing command: \n\(path), command: \(command.command), coords: \(command.coords), expected coords.count % 6 == 0")
                throw svgParseError.argumentError
            }
            for idx in stride(from: 0, to: command.coords.count, by: 6) {
                let coordX = command.coords[idx + 4]
                let coordY = command.coords[idx + 5]
                let control1: CGPoint
                let control2: CGPoint
                if command.command == .c {
                    let control1X = curPoint.x + command.coords[idx]
                    let control1Y = curPoint.y + command.coords[idx + 1]
                    let control2X = curPoint.x + command.coords[idx + 2]
                    let control2Y = curPoint.y + command.coords[idx + 3]
                    control1 = CGPoint(x: control1X, y: control1Y)
                    control2 = CGPoint(x: control2X, y: control2Y)
                    curPoint.x += coordX
                    curPoint.y += coordY
                } else {
                    let control1X = command.coords[idx]
                    let control1Y = command.coords[idx + 1]
                    let control2X = command.coords[idx + 2]
                    let control2Y = command.coords[idx + 3]
                    control1 = CGPoint(x: control1X, y: control1Y)
                    control2 = CGPoint(x: control2X, y: control2Y)
                    curPoint.x = coordX
                    curPoint.y = coordY
                }
                prevControl = control2
                result.append(.addCurve(to: remapPoint(curPoint), control1: remapPoint(control1), control2: remapPoint(control2)))
            }
        case .s:
            fallthrough
        case .S:
            guard command.coords.count % 4 == 0 else {
                print("Error when parsing command: \n\(path), command: \(command.command), coords: \(command.coords), expected coords.count % 4 == 0")
                throw svgParseError.argumentError
            }
            for idx in stride(from: 0, to: command.coords.count, by: 6) {
                let prevControlUnpacked = prevControl ?? curPoint
                let coordX = command.coords[idx + 2]
                let coordY = command.coords[idx + 3]
                let control1: CGPoint
                let control2: CGPoint
                if command.command == .s {
                    let control2X = curPoint.x + command.coords[idx]
                    let control2Y = curPoint.y + command.coords[idx + 1]
                    control1 = reflectPoint(prevControl: prevControlUnpacked, curPoint: curPoint)
                    control2 = CGPoint(x: control2X, y: control2Y)
                    curPoint.x += coordX
                    curPoint.y += coordY
                } else {
                    let control2X = command.coords[idx]
                    let control2Y = command.coords[idx + 1]
                    control1 = reflectPoint(prevControl: prevControlUnpacked, curPoint: curPoint)
                    control2 = CGPoint(x: control2X, y: control2Y)
                    curPoint.x = coordX
                    curPoint.y = coordY
                }
                result.append(.addCurve(to: remapPoint(curPoint), control1: remapPoint(control1), control2: remapPoint(control2)))
                prevControl = control2
            }
        case .q:
            fallthrough
        case .Q:
            guard command.coords.count % 4 == 0 else {
                print("Error when parsing command: \n\(path), command: \(command.command), coords: \(command.coords), expected coords.count % 4 == 0")
                throw svgParseError.argumentError
            }
            for idx in stride(from: 0, to: command.coords.count, by: 4) {
                let coordX = command.coords[idx + 2]
                let coordY = command.coords[idx + 3]
                let control: CGPoint
                if command.command == .q {
                    let controlX = curPoint.x + command.coords[idx]
                    let controlY = curPoint.y + command.coords[idx + 1]
                    control = CGPoint(x: controlX, y: controlY)
                    curPoint.x += coordX
                    curPoint.y += coordY
                } else {
                    let controlX = command.coords[idx]
                    let controlY = command.coords[idx + 1]
                    control = CGPoint(x: controlX, y: controlY)
                    curPoint.x = coordX
                    curPoint.y = coordY
                }
                result.append(.addQuadCurve(to: remapPoint(curPoint), control: remapPoint(control)))
            }
        case .z:
            guard command.coords.isEmpty else {
                print("Error when parsing command: \n\(path), command: \(command.command), coords: \(command.coords), expected no coords")
                throw svgParseError.argumentError
            }
            result.append(.closeSubpath)
        }
    }
    return result
}

fileprivate func parseMedians(_ medians: [[Double]], remapPoint: (CGPoint) -> CGPoint) -> [CGPoint] {
    var result: [CGPoint] = []
    for pair in medians {
        guard pair.count == 2 else {
            fatalError("Corrupted data: parseMedians")
        }
        let point = CGPoint(x: pair[0], y: pair[1])
        result.append(remapPoint(point))
    }
    
    return result
}

// chiHack is a flag to parse the data in format introduced in https://github.com/chanind/hanzi-writer
// inverts the y axis and sets a specified offset
fileprivate func parseData(_ data: CharacterData, character: String, chiHack: Bool) throws -> TCharacter {
    if data.medians.count != data.strokes.count {
        print("Error when parsing \(data.character). Stroke count: \(data.strokes.count), medians count: \(data.medians.count)")
        throw svgParseError.mediansMismatch
    }
    var strokes: [StrokeData] = []
    for idx in 0..<data.medians.count {
        let remapPoint: (CGPoint) -> CGPoint
        if chiHack {
            // https://github.com/skishore/makemeahanzi#graphicstxt-keys
            // this peculiar function is used to make data provided by makemeahanzi repo work
            remapPoint = {point in
                return CGPoint(
                    x: (point.x + (data.xOffset ?? 0.0)) / 1024.0,
                    y: (900 - point.y - (data.yOffset ?? 0.0)) / 1024.0
                )
            }
        } else {
            remapPoint = {point in
                return CGPoint(
                    x: (point.x + (data.xOffset ?? 0.0)) / (data.width ?? 1024.0),
                    y: (point.y + (data.yOffset ?? 0.0)) / (data.height ?? 1024.0)
                )
            }
        }
        let outline = try! parseSvgPath(data.strokes[idx], remapPoint: remapPoint, scale: 1 / (data.width ?? 1024.0))
        strokes.append(StrokeData(id: idx, outline: outline, medians: parseMedians(data.medians[idx], remapPoint: remapPoint)))
    }
    let strokeMap = data.strokeMap ?? Array(0..<data.medians.count)
    if strokeMap.count != strokes.count {
        fatalError("Stroke map count != stroke count")
    }
    return TCharacter(character: character, strokes: strokes, strokeMap: strokeMap)
}

public class CharacterHolder {
    private(set) public var data: [String: CharacterData]
    private let chiHack: Bool
    public init(chiHack: Bool) {
        self.data = [:]
        self.chiHack = chiHack
    }
    
    init(data: [String : CharacterData], chiHack: Bool) {
        self.data = data
        self.chiHack = chiHack
    }
    
    public func get(_ char: String) -> TCharacter? {
        if let data = data[char] {
            return try? parseData(data, character: char, chiHack: chiHack)
        } else {
            return nil
        }
    }
    
    public static func load(url: URL, chiHack: Bool) async throws -> CharacterHolder {
        let decoder = JSONDecoder()
        var res: [String: CharacterData] = [:]
        let handle = try FileHandle(forReadingFrom: url)
        for try await line in url.lines {
            let characterData = try! decoder.decode(CharacterData.self, from: line.data(using: .utf8)!)
            res[characterData.character] = characterData
            // leave this to try to check data correctness?
            // res[characterData.character] = try parseData(characterData, character: characterData.character, chiHack: chiHack)
        }
        return CharacterHolder(data: res, chiHack: chiHack)
    }
    
    public func merge(from: CharacterHolder) {
        self.data.merge(from.data) {key1, key2 in
            return key1
        }
    }
}
