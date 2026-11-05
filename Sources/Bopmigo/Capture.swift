import SwiftUI
import UIKit
import CoreImage

/// Marks views to cover in screenshots and takes the redacted screenshot.
@MainActor
enum Redactor {
    private static let marked = NSHashTable<UIView>.weakObjects()

    static func mark(_ view: UIView, _ on: Bool) { on ? marked.add(view) : marked.remove(view) }
    static func isPrivate(_ view: UIView) -> Bool { marked.contains(view) }

    /// A screenshot of the app's window with private areas covered, or nil.
    /// Passwords and views marked private are blacked out before the image ever leaves the phone.
    static func screenshot() -> UIImage? {
        guard let window = Presenter.keyWindow else { return nil }
        var covers: [CGRect] = []
        collect(window, in: window, into: &covers)
        let bounds = window.bounds
        func render(scale: CGFloat) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            return UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
                window.drawHierarchy(in: bounds, afterScreenUpdates: false)
                UIColor.black.setFill()
                for rect in covers { UIBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 4).fill() }
            }
        }
        // The screen's own sharpness (3x on most iPhones), so text stays crisp.
        var image = render(scale: window.screen.scale)
        if Bopmigo.hideAllText { image = pixelate(image) ?? image }
        return image
    }

    /// JPEG at high quality: sharp at full resolution and well under the 2 MB limit.
    static func encode(_ image: UIImage?) -> String? {
        guard let image else { return nil }
        for quality in [0.85, 0.7, 0.5] as [CGFloat] {
            if let data = image.jpegData(compressionQuality: quality), data.count < 1_800_000 { return data.base64EncodedString() }
        }
        return nil
    }

    private static func collect(_ view: UIView, in window: UIWindow, into covers: inout [CGRect]) {
        if view.isHidden || view.alpha < 0.01 { return }
        let secure = (view as? UITextField)?.isSecureTextEntry == true
        if secure || marked.contains(view) {
            covers.append(view.convert(view.bounds, to: window))
            return
        }
        for sub in view.subviews { collect(sub, in: window, into: &covers) }
    }

    /// Blocks out every word but keeps the layout readable, for apps with sensitive text.
    private static func pixelate(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image), let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(14 * image.scale, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cg = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }
}

/// The invisible view behind `.bopmigoPrivate()` in SwiftUI.
struct PrivateMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        Redactor.mark(view, true)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

/// Device and app details sent with each report. No identifiers beyond what the app sets.
@MainActor
enum DeviceContext {
    static func current() -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "App"
        let screen = UIScreen.main.bounds.size
        var context: [String: Any] = [
            "release": "\(version) (\(build))",
            "sdk": "\(name) on iOS, Bopmigo \(Client.version)",
            "device": model(),
            "os": "iOS \(UIDevice.current.systemVersion)",
            "viewport": "\(Int(screen.width)) × \(Int(screen.height))",
            "pixelRatio": Double(UIScreen.main.scale),
            "language": Locale.preferredLanguages.first ?? Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "appId": Bundle.main.bundleIdentifier ?? "",
        ]
        if let screen = Bopmigo.screen { context["screen"] = screen }
        for (k, v) in Bopmigo.user { context[k] = v }
        for (k, v) in Bopmigo.custom.prefix(20) { context[k] = v }
        return context
    }

    private static func model() -> String {
        var info = utsname()
        uname(&info)
        let id = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        if id == "x86_64" || id == "arm64" { return "\(UIDevice.current.model) (Simulator)" }
        return "\(UIDevice.current.model) (\(id))"
    }
}
