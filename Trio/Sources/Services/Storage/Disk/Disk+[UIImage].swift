import Foundation
import UIKit

public extension Disk {
    /// Save an array of images to disk
    ///
    /// - Parameters:
    ///   - value: array of images to store
    ///   - directory: user directory to store the images in
    ///   - path: folder location to store the images (i.e. "Folder/")
    /// - Throws: Error if there were any issues creating a folder and writing the given images to it
    static func save(_ value: [UIImage], to directory: Directory, as path: String) throws {
        do {
            let folderUrl = try createURL(for: path, in: directory)
            try createSubfoldersBeforeCreatingFile(at: folderUrl)
            try FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: false, attributes: nil)
            for i in 0 ..< value.count {
                let image = value[i]
                var imageData: Data
                var imageName = "\(i)"
                var pngData: Data?
                var jpegData: Data?
                #if swift(>=4.2)
                    if let data = image.pngData() {
                        pngData = data
                    } else if let data = image.jpegData(compressionQuality: 1) {
                        jpegData = data
                    }
                #else
                    if let data = UIImagePNGRepresentation(image) {
                        pngData = data
                    } else if let data = UIImageJPEGRepresentation(image, 1) {
                        jpegData = data
                    }
                #endif
                if let data = pngData {
                    imageData = data
                    imageName = imageName + ".png"
                } else if let data = jpegData {
                    imageData = data
                    imageName = imageName + ".jpg"
                } else {
                    throw createError(
                        .serialization,
                        description: "Could not serialize UIImage \(i) in the array to Data.",
                        failureReason: "UIImage \(i) could not serialize to PNG or JPEG data.",
                        recoverySuggestion: "Make sure there are no corrupt images in the array."
                    )
                }
                let imageUrl = folderUrl.appendingPathComponent(imageName, isDirectory: false)
                try imageData.write(to: imageUrl, options: .atomic)
            }
        } catch {
            throw error
        }
    }

    /// Append an image to a folder
    ///
    /// - Parameters:
    ///   - value: image to store to disk
    ///   - path: folder location to store the image (i.e. "Folder/")
    ///   - directory: user directory to store the image file in
    /// - Throws: Error if there were any issues writing the image to disk
    static func append(_ value: UIImage, to path: String, in directory: Directory) throws {
        do {
            if let folderUrl = try? getExistingFileURL(for: path, in: directory) {
                let fileUrls = try FileManager.default.contentsOfDirectory(
                    at: folderUrl,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                var largestFileNameInt = -1
                for i in 0 ..< fileUrls.count {
                    let fileUrl = fileUrls[i]
                    if let fileNameInt = fileNameInt(fileUrl) {
                        if fileNameInt > largestFileNameInt {
                            largestFileNameInt = fileNameInt
                        }
                    }
                }
                let newFileNameInt = largestFileNameInt + 1
                var imageData: Data
                var imageName = "\(newFileNameInt)"
                var pngData: Data?
                var jpegData: Data?
                #if swift(>=4.2)
                    if let data = value.pngData() {
                        pngData = data
                    } else if let data = value.jpegData(compressionQuality: 1) {
                        jpegData = data
                    }
                #else
                    if let data = UIImagePNGRepresentation(value) {
                        pngData = data
                    } else if let data = UIImageJPEGRepresentation(value, 1) {
                        jpegData = data
                    }
                #endif
                if let data = pngData {
                    imageData = data
                    imageName = imageName + ".png"
                } else if let data = jpegData {
                    imageData = data
                    imageName = imageName + ".jpg"
                } else {
                    throw createError(
                        .serialization,
                        description: "Could not serialize UIImage to Data.",
                        failureReason: "UIImage could not serialize to PNG or JPEG data.",
                        recoverySuggestion: "Make sure image is not corrupt."
                    )
                }
                let imageUrl = folderUrl.appendingPathComponent(imageName, isDirectory: false)
                try imageData.write(to: imageUrl, options: .atomic)
            } else {
                let array = [value]
                try save(array, to: directory, as: path)
            }
        } catch {
            throw error
        }
    }

    /// Append an array of images to a folder
    ///
    /// - Parameters:
    ///   - value: images to store to disk
    ///   - path: folder location to store the images (i.e. "Folder/")
    ///   - directory: user directory to store the images in
    /// - Throws: Error if there were any issues writing the images to disk
    static func append(_ value: [UIImage], to path: String, in directory: Directory) throws {
        do {
            if let _ = try? getExistingFileURL(for: path, in: directory) {
                for image in value {
                    try append(image, to: path, in: directory)
                }
            } else {
                try save(value, to: directory, as: path)
            }
        } catch {
            throw error
        }
    }

    /// Retrieve an array of images from a folder on disk
    ///
    /// - Parameters:
    ///   - path: path of folder holding desired images
    ///   - directory: user directory where images' folder was created
    ///   - type: here for Swifty generics magic, use [UIImage].self
    /// - Returns: [UIImage] from disk
    /// - Throws: Error if there were any issues retrieving the specified folder of images
    static func retrieve(_ path: String, from directory: Directory, as _: [UIImage].Type) throws -> [UIImage] {
        do {
            let url = try getExistingFileURL(for: path, in: directory)
            let fileUrls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            let sortedFileUrls = fileUrls.sorted(by: { (url1, url2) -> Bool in
                if let fileNameInt1 = fileNameInt(url1), let fileNameInt2 = fileNameInt(url2) {
                    return fileNameInt1 <= fileNameInt2
                }
                return true
            })
            var images = [UIImage]()
            for i in 0 ..< sortedFileUrls.count {
                let fileUrl = sortedFileUrls[i]
                let data = try Data(contentsOf: fileUrl)
                if let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            return images
        } catch {
            throw error
        }
    }
}
