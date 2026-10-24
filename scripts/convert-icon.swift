import Foundation
import ImageIO
import CoreGraphics

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { exit(1) }
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard let rgba = context.makeImage() else { exit(1) }
CGImageDestinationAddImage(destination, rgba, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
