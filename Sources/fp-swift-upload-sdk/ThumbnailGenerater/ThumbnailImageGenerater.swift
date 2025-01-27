

import Foundation
import AVFoundation

/// A class for generating thumbnail images from AVAssets asynchronously.
public class ThumbnailImageGenerater {
    
    /// Creates a new instance of `ThumbnailImageGenerater`.
    public init() {}
    
    var thumbnailGenerator: AVAssetImageGenerator? = nil
    
    /// Asynchronously extracts a thumbnail image from a provided AVAsset at a specified time.
      /// - Parameters:
      ///   - asset: The AVAsset from which to generate the thumbnail.
      ///   - thumbImage: A completion closure that will be called with the generated CGImage (if successful), or nil otherwise.
    
    public func extractThumbnailAsync(_ asset: AVAsset, thumbImage: @escaping (CGImage?) -> Void) {
        if let thumbnailGenerator = thumbnailGenerator {
            
            /// Cancel any in-progress thumbnail generation tasks.
            thumbnailGenerator.cancelAllCGImageGeneration()
        }
        
        // Create a CMTime object representing 10 seconds, with a preferred timescale of 1
        let time = CMTime(seconds: 10, preferredTimescale: 1)
        
        thumbnailGenerator = AVAssetImageGenerator(asset: asset)
        
        /// Asynchronously generates a CGImage for the specified time from the asset.
        thumbnailGenerator?.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { requestedTime, image, actualTime, result, error in
            switch result {
            case .cancelled:
                print("Thumbnail request canceled")
            case .succeeded:
                thumbImage(image)
            case .failed:
                print("Failed to generate thumbnail",error)
            default:
                fatalError()
            }
        }
    }
}
