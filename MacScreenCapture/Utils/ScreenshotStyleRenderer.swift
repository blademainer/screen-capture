import AppKit
import Foundation

struct ScreenshotStyleRenderer {
    struct OutputStyle {
        let roundedCorners: Bool
        let cornerRadius: CGFloat
        let dropShadow: Bool
        let shadowRadius: CGFloat
        let shadowColor: NSColor
    }

    struct DeviceFrameStyle {
        let bezel: CGFloat
        let padding: CGFloat
        let cornerRadius: CGFloat
        let shadowRadius: CGFloat
        let bodyColor: NSColor
        let shadowColor: NSColor
    }

    static func applyOutputStyle(to image: NSImage, style: OutputStyle) -> NSImage {
        var currentImage = image
        var appliedCornerRadius: CGFloat?

        if style.roundedCorners {
            currentImage = renderRoundedImage(currentImage, radius: style.cornerRadius)
            appliedCornerRadius = style.cornerRadius
        }

        if style.dropShadow {
            currentImage = renderShadowedImage(
                currentImage,
                shadowRadius: style.shadowRadius,
                shadowColor: style.shadowColor,
                cornerRadius: appliedCornerRadius
            )
        }

        return currentImage
    }

    static func renderRoundedImage(_ image: NSImage, radius: CGFloat) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()

        let rect = NSRect(origin: .zero, size: image.size)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.addClip()
        image.draw(in: rect)

        output.unlockFocus()
        return output
    }

    static func renderShadowedImage(_ image: NSImage, shadowRadius: CGFloat, shadowColor: NSColor, cornerRadius: CGFloat? = nil) -> NSImage {
        let padding = max(CGFloat(24), shadowRadius * 2)
        let outputSize = NSSize(width: image.size.width + padding * 2, height: image.size.height + padding * 2)
        let output = NSImage(size: outputSize)

        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        let shadow = NSShadow()
        shadow.shadowBlurRadius = shadowRadius
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowColor = shadowColor.withAlphaComponent(0.28)
        shadow.set()

        let imageRect = NSRect(x: padding, y: padding, width: image.size.width, height: image.size.height)
        let backgroundPath: NSBezierPath
        if let cornerRadius, cornerRadius > 0 {
            backgroundPath = NSBezierPath(
                roundedRect: imageRect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
        } else {
            backgroundPath = NSBezierPath(rect: imageRect)
        }

        NSColor.white.setFill()
        backgroundPath.fill()
        image.draw(in: imageRect)

        output.unlockFocus()
        return output
    }

    static func renderDeviceFrame(around image: NSImage, style: DeviceFrameStyle) -> NSImage {
        let titleBar = max(24, style.bezel * 0.8)
        let frameSize = NSSize(
            width: image.size.width + style.bezel * 2 + style.padding * 2,
            height: image.size.height + style.bezel * 2 + titleBar + style.padding * 2
        )
        let output = NSImage(size: frameSize)

        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: frameSize).fill()

        let bodyRect = NSRect(
            x: style.padding,
            y: style.padding,
            width: image.size.width + style.bezel * 2,
            height: image.size.height + style.bezel * 2 + titleBar
        )

        let shadow = NSShadow()
        shadow.shadowBlurRadius = style.shadowRadius
        shadow.shadowOffset = NSSize(width: 0, height: -max(4, style.shadowRadius / 3))
        shadow.shadowColor = style.shadowColor.withAlphaComponent(style.shadowRadius > 0 ? 0.32 : 0)
        shadow.set()

        style.bodyColor.setFill()
        NSBezierPath(roundedRect: bodyRect, xRadius: style.cornerRadius, yRadius: style.cornerRadius).fill()

        NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        let screenRect = NSRect(
            x: bodyRect.minX + style.bezel,
            y: bodyRect.minY + style.bezel,
            width: image.size.width,
            height: image.size.height
        )
        image.draw(in: screenRect)

        let cameraRect = NSRect(x: bodyRect.midX - 5, y: bodyRect.maxY - 22, width: 10, height: 10)
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: cameraRect).fill()

        output.unlockFocus()
        return output
    }
}
