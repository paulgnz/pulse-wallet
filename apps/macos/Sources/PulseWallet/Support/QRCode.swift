import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// Generates a crisp QR code image from a string. Kept black-on-white for
/// maximum scannability across themes (camera apps expect high contrast).
enum QRCode {
    static func image(_ string: String, scale: CGFloat = 10) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
    }
}

/// A QR panel that always reads as black-on-white inside a rounded white card,
/// regardless of the active theme.
struct QRCodeView: View {
    let content: String
    var size: CGFloat = 168

    var body: some View {
        Group {
            if let img = QRCode.image(content) {
                Image(nsImage: img)
                    .interpolation(.none)         // keep modules razor-sharp
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable().scaledToFit().padding(24)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.08)))
    }
}
