// Renders the widget views to PNG for a visual check: swiftc with Shared/ and WidgetViews.swift.
import AppKit
import SwiftUI
import WidgetKit

@MainActor
func render(_ family: WidgetFamily, _ size: CGSize, _ state: ChargerState?, to path: String) {
    let view = ZStack {
        WidgetBackground(total: state?.total ?? 0)
        ChargerWidgetContent(entry: Entry(date: .now, state: state), family: family).padding(16)
    }
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .padding(20)
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

@main
struct RenderWidget {
    static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "."
        var live = SharedStore.load() ?? .placeholder
        live.ts = Date().timeIntervalSince1970
        live.pads = live.pads.map { var p = $0; p.kind = PadKind.forPad(p.id); return p }
        MainActor.assumeIsolated {
            render(.systemSmall, CGSize(width: 170, height: 170), live, to: "\(out)/small.png")
            render(.systemMedium, CGSize(width: 364, height: 170), live, to: "\(out)/medium.png")
            render(.systemMedium, CGSize(width: 364, height: 170), .placeholder, to: "\(out)/medium-busy.png")
        }
    }
}
