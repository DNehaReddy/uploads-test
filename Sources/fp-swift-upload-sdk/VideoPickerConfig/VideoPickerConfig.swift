
import UIKit
import Photos
import PhotosUI

/// A configuration class for customizing a PHPicker specifically for video picking on devices running iOS 14.0 or later.
@available(iOS 14.0, *)
public class VideoPickerConfiguration {
    
    /// Creates a new instance of `VideoPickerConfiguration`.
    public init() {}
    
    /// Creates and returns a PHPickerConfiguration object tailored for video selection.
      /// - Returns: A PHPickerConfiguration object pre-configured for video picking.
    public func pickerConfig() -> PHPickerConfiguration {
        
        // Filter to display only videos in the picker
        let mediaFilter = PHPickerFilter.any(of: [.videos])
        var photoPickerConfig = PHPickerConfiguration(photoLibrary: .shared())
        photoPickerConfig.filter = mediaFilter
        
        // Request the current representation of the selected asset
        photoPickerConfig.preferredAssetRepresentationMode = .current
        
        // Limit selection to a single video
        photoPickerConfig.selectionLimit = 1
        
        // Set selection behavior based on iOS version (iOS 15 and above)
        if #available(iOS 15.0, *) {
            photoPickerConfig.selection = .default
        }
        return photoPickerConfig
    }
}

