import Foundation
import CoreGraphics
import ImageIO

public enum ImageFileError: Error, LocalizedError {
    case cannotDecode
    case cannotWrite

    public var errorDescription: String? {
        switch self {
        case .cannotDecode: return "画像を読み込めませんでした（PNG / JPEG のみ対応）"
        case .cannotWrite: return "PNG の書き出しに失敗しました"
        }
    }
}

/// ImageIO の薄いラッパー。
public enum ImageFile {
    public static func load(url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ImageFileError.cannotDecode
        }
        return image
    }

    public static func load(data: Data) throws -> CGImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ImageFileError.cannotDecode
        }
        return image
    }

    /// 一覧表示用の縮小画像。巨大なベゼル PNG をそのまま UI に載せないために使う。
    public static func thumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw ImageFileError.cannotWrite
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ImageFileError.cannotWrite }
    }
}
