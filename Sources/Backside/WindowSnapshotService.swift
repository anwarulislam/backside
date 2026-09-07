import AppKit
import CoreGraphics

@MainActor
enum WindowSnapshotService {
    private typealias CGWindowListCreateImageFunc = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static let legacyCaptureFunc: CGWindowListCreateImageFunc? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: CGWindowListCreateImageFunc.self)
    }()

    /// Captures the target window image. Returns nil if permission is unavailable or capture fails.
    static func capture(windowNumber: CGWindowID, screenRect: CGRect) -> NSImage? {
        guard windowNumber != 0 else { return nil }
        guard let fn = legacyCaptureFunc else { return nil }

        // kCGWindowListOptionIncludingWindow = 8
        // kCGWindowImageBoundsIgnoreFraming = 1
        // kCGWindowImageBestResolution = 8
        let options: UInt32 = 1 | 8
        if let cgImage = fn(screenRect, 8, windowNumber, options)?.takeRetainedValue(),
           cgImage.width > 0, cgImage.height > 0 {
            return NSImage(cgImage: cgImage, size: screenRect.size)
        }
        return nil
    }
}
