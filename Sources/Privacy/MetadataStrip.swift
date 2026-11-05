// NuDefndr - nudefndr.com
// Transparency Repository - Metadata stripping for the vault and clean sharing (v2.6.7)

import Foundation
import ImageIO

enum MetadataStrip {
    struct Disclosure: Equatable {
        var hasLocation = false

        var camera: String?

        var taken: Date?

        var hasOther = false

        var isEmpty: Bool { !hasLocation && camera == nil && taken == nil && !hasOther }
    }

    static func disclosure(at url: URL) -> Disclosure {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return Disclosure(hasOther: true)
        }
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let model = (tiff?[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lens = (exif?[kCGImagePropertyExifLensModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String

        return Disclosure(
            hasLocation: gps?[kCGImagePropertyGPSLatitude] != nil || gps?[kCGImagePropertyGPSLongitude] != nil,
            camera: [model, lens].compactMap { $0 }.first { !$0.isEmpty },
            taken: stamp.flatMap { exifDateFormatter.date(from: $0) },
            hasOther: !isClean(source)
        )
    }

    static func isClean(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return isClean(source)
    }

    private static func isReadableImage(_ source: CGImageSource) -> Bool {
        CGImageSourceGetType(source) != nil
            && CGImageSourceGetStatus(source) == .statusComplete
            && CGImageSourceGetCount(source) > 0
    }

    private static let harmlessTIFF: Set<CFString> = [
        kCGImagePropertyTIFFOrientation, kCGImagePropertyTIFFTileWidth, kCGImagePropertyTIFFTileLength,
        kCGImagePropertyTIFFXResolution, kCGImagePropertyTIFFYResolution, kCGImagePropertyTIFFResolutionUnit,
        kCGImagePropertyTIFFCompression, kCGImagePropertyTIFFPhotometricInterpretation
    ]
    private static let harmlessExif: Set<CFString> = [
        kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension, kCGImagePropertyExifColorSpace,
        kCGImagePropertyExifVersion, kCGImagePropertyExifFlashPixVersion, kCGImagePropertyExifComponentsConfiguration
    ]
    private static let harmlessXMP: Set<String> = [
        "tiff:Orientation", "tiff:TileWidth", "tiff:TileLength", "tiff:XResolution", "tiff:YResolution",
        "tiff:ResolutionUnit", "tiff:Compression", "tiff:PhotometricInterpretation", "exif:PixelXDimension", "exif:PixelYDimension", "exif:ColorSpace",
        "iio:hasXMP", "iio:hasIIM"
    ]
    private static let pngText: [CFString] = [
        kCGImagePropertyPNGAuthor, kCGImagePropertyPNGComment, kCGImagePropertyPNGCopyright,
        kCGImagePropertyPNGCreationTime, kCGImagePropertyPNGDescription, kCGImagePropertyPNGDisclaimer,
        kCGImagePropertyPNGSoftware, kCGImagePropertyPNGSource, kCGImagePropertyPNGTitle
    ]

    private static func isClean(_ source: CGImageSource) -> Bool {
        guard isReadableImage(source) else { return false }
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return false }

            for key in removedDictionaries {
                guard let block = properties[key] as? [CFString: Any] else { continue }
                let harmless = key == kCGImagePropertyTIFFDictionary ? harmlessTIFF
                    : key == kCGImagePropertyExifDictionary ? harmlessExif : []
                if block.keys.contains(where: { !harmless.contains($0) }) { return false }
            }
            if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
               pngText.contains(where: { png[$0] != nil }) { return false }
            if let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil),
               let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] {
                for tag in tags {
                    let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? ""
                    let name = CGImageMetadataTagCopyName(tag) as String? ?? ""
                    if !harmlessXMP.contains("\(prefix):\(name)") { return false }
                }
            }
        }
        return true
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    static func strippedImageData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, CGImageSourceGetCount(source), nil),
              copyStripped(from: source, to: destination) else { return nil }
        return output as Data
    }

    static func writeStripped(from input: URL, to output: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let type = CGImageSourceGetType(source),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, type, CGImageSourceGetCount(source), nil)
        else { return false }
        return copyStripped(from: source, to: destination)
    }

    private static let removedDictionaries: [CFString] = [
        kCGImagePropertyGPSDictionary,
        kCGImagePropertyExifDictionary,
        kCGImagePropertyExifAuxDictionary,
        kCGImagePropertyTIFFDictionary,
        kCGImagePropertyIPTCDictionary,
        kCGImagePropertyMakerAppleDictionary,
        kCGImagePropertyMakerCanonDictionary,
        kCGImagePropertyMakerNikonDictionary,
        kCGImagePropertyMakerMinoltaDictionary,
        kCGImagePropertyMakerFujiDictionary,
        kCGImagePropertyMakerOlympusDictionary,
        kCGImagePropertyMakerPentaxDictionary,

        kCGImagePropertyDNGDictionary,
        kCGImagePropertyCIFFDictionary,
        kCGImageProperty8BIMDictionary
    ]

    private static func copyStripped(from source: CGImageSource, to destination: CGImageDestination) -> Bool {
        let isPNG = CGImageSourceGetType(source).map { $0 as String == "public.png" } ?? false
        for index in 0..<CGImageSourceGetCount(source) {
            var removal = Dictionary(uniqueKeysWithValues: removedDictionaries.map { ($0, kCFNull as Any) })

            if isPNG {
                removal[kCGImagePropertyPNGDictionary] = Dictionary(uniqueKeysWithValues: pngText.map { ($0, kCFNull as Any) })
            }
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let orientation = properties[kCGImagePropertyOrientation] {
                removal[kCGImagePropertyOrientation] = orientation
            }
            CGImageDestinationAddImageFromSource(destination, source, index, removal as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }
}
