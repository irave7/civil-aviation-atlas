import Foundation

/// Spoken forms for Mandarin narration. The visual caption retains the original identifiers.
enum AviationSpeech {
    private static let digits = Array("零一二三四五六七八九")
    private static let runway = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])([0-3][0-9])(?:([LCR])(?![A-Za-z0-9])|(?=/[0-3][0-9]|(?:号)?\s*跑道))"#)
    private static let aircraft = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])([ABC])([1378][0-9]{2}|919)(?:-([0-9]{1,3}))?(neo|NEO)?(?![A-Za-z0-9])"#)
    private static let pairedRunway = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])([0-3][0-9])([LCR]?)/([0-3][0-9])([LCR]?)(?![A-Za-z0-9])"#)
    private static let boeing = try! NSRegularExpression(pattern: #"(波音)\s*(7[0-9]7)(?:[-–]([0-9]{1,3}))?"#)
    private static let flight = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])([A-Z]{2})([0-9]{2,4})(?![A-Za-z0-9])"#)
    private static let operators = ["MU": "东航", "CA": "国航", "CZ": "南航", "MF": "厦航", "SQ": "新航",
                                    "CX": "国泰", "EK": "阿联酋航空", "JL": "日航", "LH": "汉莎"]

    static func mandarin(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "长乐国际机场", with: "常乐国际机场")
            .replacingOccurrences(of: "长乐机场", with: "常乐机场")
            .replacingOccurrences(of: "重庆", with: "崇庆")
            .replacingOccurrences(of: "厦门", with: "夏门")
        result = replacing(in: result, pattern: aircraft) { groups in
            let spoken = groups[1] + readDigits(groups[2])
            return spoken + (groups[3].isEmpty ? "" : "杠" + readDigits(groups[3])) + groups[4]
        }
        result = replacing(in: result, pattern: boeing) { groups in
            groups[1] + readDigits(groups[2]) + (groups[3].isEmpty ? "" : "杠" + readDigits(groups[3]))
        }
        result = replacing(in: result, pattern: pairedRunway) { groups in
            guard let first = runwayEnd(groups[1], side: groups[2]),
                  let second = runwayEnd(groups[3], side: groups[4]) else { return groups[0] }
            return first + "、" + second
        }
        result = replacing(in: result, pattern: flight) { groups in
            (operators[groups[1]] ?? groups[1]) + readDigits(groups[2])
        }
        return replacing(in: result, pattern: runway) { groups in
            runwayEnd(groups[1], side: groups[2]) ?? groups[0]
        }
    }

    private static func runwayEnd(_ digits: String, side: String) -> String? {
        guard let number = Int(digits), (1...36).contains(number) else { return nil }
        return readDigits(digits) + (["L": "左", "C": "中", "R": "右"][side] ?? "")
    }

    private static func readDigits(_ value: String) -> String {
        String(value.compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    private static func replacing(in input: String, pattern: NSRegularExpression,
                                  with transform: ([String]) -> String) -> String {
        let source = input as NSString
        let output = NSMutableString(string: input)
        for match in pattern.matches(in: input, range: NSRange(location: 0, length: source.length)).reversed() {
            let groups = (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            output.replaceCharacters(in: match.range, with: transform(groups))
        }
        return output as String
    }
}

enum FlightAudioText {
    static let observation = catalogue("observation-scripts", directory: "ObservationVoices")
    private static let flight = catalogue("flight-transcripts", directory: "Narration")

    static func transcript(for recording: URL?) -> String? {
        recording.flatMap { flight[$0.deletingPathExtension().lastPathComponent] }
    }

    static func resource(_ name: String, ext: String, directory: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: directory)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/" + directory)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    private static func catalogue(_ name: String, directory: String) -> [String: String] {
        guard let url = resource(name, ext: "json", directory: directory),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}
