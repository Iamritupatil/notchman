import Foundation
import Photos

/// The screenshot you just took, read straight from Photos, so tapping TL;DR in
/// the Dynamic Island needs no shortcut and never opens Notchman. It's read on
/// the iPhone and never uploaded.
enum RecentScreenshot {
    static var isAuthorized: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }

    static var canAsk: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined
    }

    @discardableResult
    static func requestAccess() async -> Bool {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized
    }

    /// The newest screenshot taken within `seconds`, as image data. Screenshots
    /// can take a moment to land in Photos, so it looks again briefly.
    static func latest(within seconds: TimeInterval) async -> Data? {
        guard isAuthorized else { return nil }
        for attempt in 0..<3 {
            if let asset = newestScreenshot(since: Date().addingTimeInterval(-seconds)) {
                return await imageData(for: asset)
            }
            if attempt < 2 { try? await Task.sleep(for: .milliseconds(700)) }
        }
        return nil
    }

    private static func newestScreenshot(since date: Date) -> PHAsset? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0 AND creationDate > %@",
                                        PHAssetMediaSubtype.photoScreenshot.rawValue, date as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: .image, options: options).firstObject
    }

    private static func imageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
