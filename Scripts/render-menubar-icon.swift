#!/usr/bin/env swift
// Convert the waveform's rounded SVG bars into a tightly cropped vector PDF.
import AppKit

final class WaveformParser: NSObject, XMLParserDelegate {
    var bars: [(CGRect, CGFloat)] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard elementName == "rect",
              let x = Double(attributes["x"] ?? ""), let y = Double(attributes["y"] ?? ""),
              let width = Double(attributes["width"] ?? ""), let height = Double(attributes["height"] ?? "") else { return }
        bars.append((CGRect(x: x, y: y, width: width, height: height),
                     CGFloat(Double(attributes["rx"] ?? "0") ?? 0)))
    }
}
let source = URL(fileURLWithPath: "Resources/vio.icon/Assets/vio_heart_like_waveform_white.svg")
let parser = XMLParser(contentsOf: source)!
let waveform = WaveformParser()
parser.delegate = waveform
guard parser.parse(), !waveform.bars.isEmpty else {
    fatalError("Could not read waveform bars from \(source.path)")
}
let bounds = waveform.bars.reduce(CGRect.null) { $0.union($1.0) }
let scale = 18 / bounds.width
var page = CGRect(x: 0, y: 0, width: 18, height: bounds.height * scale)
let output = URL(fileURLWithPath: "Resources/MenuBarIcon.pdf")
let context = CGContext(output as CFURL, mediaBox: &page, nil)!
context.beginPDFPage(nil)
context.scaleBy(x: scale, y: scale)
context.translateBy(x: -bounds.minX, y: bounds.maxY)
context.scaleBy(x: 1, y: -1)
context.setFillColor(NSColor.black.cgColor)
for (rect, radius) in waveform.bars {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
context.endPDFPage()
context.closePDF()
