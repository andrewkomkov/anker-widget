// Renders the 1024 px app icon: swiftc -parse-as-library tools/make_icon.swift -o /tmp/icon && /tmp/icon out.png
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.21), Color(red: 0.03, green: 0.04, blue: 0.06)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(RadialGradient(colors: [Color(red: 0.36, green: 0.93, blue: 0.55).opacity(0.45), .clear],
                                     center: .bottomLeading, startRadius: 0, endRadius: 760))
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 64, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 560, height: 560)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(LinearGradient(colors: [Color(red: 0.36, green: 0.93, blue: 0.55), Color(red: 0.55, green: 0.94, blue: 1.0)],
                                       startPoint: .bottomLeading, endPoint: .topTrailing),
                        style: StrokeStyle(lineWidth: 64, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 560, height: 560)
            Image(systemName: "bolt.fill")
                .font(.system(size: 300, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.25))
        }
        .frame(width: 824, height: 824)
        .frame(width: 1024, height: 1024)
    }
}

@main
struct MakeIcon {
    @MainActor static func main() {
        let r = ImageRenderer(content: Icon())
        r.scale = 1
        let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: out))
    }
}
