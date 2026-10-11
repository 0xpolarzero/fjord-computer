import AppKit
import Metal
import QuartzCore
import Testing
@testable import Lookout

@MainActor
@Suite(.hostsWindows) struct TransitionTests {
    @Test func theOverlayOnlyAllocatesThePartOfTheScreenTheMorphUses() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let window = AwayWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 300, height: 200)),
                                styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let bitmap = try #require(CGContext(data: nil, width: 46, height: 200, bitsPerComponent: 8, bytesPerRow: 184,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let picture = NSImage(cgImage: try #require(bitmap.makeImage()), size: NSSize(width: 46, height: 200))
        let bar = BarMorph(frame: NSRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 46, height: 200),
                           snapshot: picture)
        let run = try #require(AppTransition.makeRun(for: window, image: nil, bar: bar))
        defer { run.end(); window.close() }
        let expected = window.frame.union(bar.frame).union(bar.cellFrame).insetBy(dx: -200, dy: -200)
            .intersection(screen.frame)
        #expect(run.overlay.frame == NSRect(origin: UnderTest.away, size: expected.size))
        #expect(run.overlay.contentView?.bounds.size == expected.size)
        #expect(run.overlay.contentView?.layer?.bounds.size == expected.size)
        let shadow = try #require(run.overlay.contentView?.layer?.sublayers?.first)
        #expect(shadow.shadowRadius == AppTransition.shadowRadius)
        #expect(shadow.shadowOffset == AppTransition.shadowOffset)
        run.present()
        let layers = try #require(run.overlay.contentView?.layer?.sublayers)
        #expect(layers.count == 3)
        #expect(run.geometry.screen(layers[1].frame) == window.frame)
        #expect(run.geometry.screen(layers[2].frame) == bar.frame)
        #expect(run.overlay.frame.origin == UnderTest.away)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(run.overlay.frame) })
    }

    @Test func theOverlayStaysFixedThroughReversalsAndResizesBetweenRuns() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let window = AwayWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 300, height: 200)),
                                styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let bar = BarMorph(frame: NSRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 46, height: 200))
        let run = try #require(AppTransition.makeRun(for: window, image: nil, bar: bar))
        defer { run.end(); window.close() }
        let frame = run.overlay.frame
        let geometry = run.geometry.frame
        run.open(reduced: false, done: {})
        run.close(reduced: false, done: {})
        run.open(reduced: false, done: {})
        #expect(run.overlay.frame == frame && run.geometry.frame == geometry)
        run.end()
        let moved = BarMorph(frame: bar.frame.offsetBy(dx: 100, dy: 100))
        let next = try #require(AppTransition.makeRun(for: window, image: nil, bar: moved))
        defer { next.end() }
        #expect(next.overlay === run.overlay)
        #expect(next.overlay.frame.size != frame.size)
        #expect(next.overlay.frame.size == next.geometry.frame.size)
        #expect(next.overlay.frame.origin == UnderTest.away)
    }

    @Test func equalFramesOnDifferentDisplaysDoNotShareAnOverlay() {
        let cache = AppTransition.OverlayCache()
        let frame = NSRect(x: -1920, y: -1080, width: 700, height: 500)
        let first = cache.window(on: .display(1), frame: frame)
        let same = cache.window(on: .display(1), frame: frame.offsetBy(dx: 20, dy: 10))
        #expect(same === first)
        let second = cache.window(on: .display(2), frame: frame)
        #expect(second !== first)
        #expect(second.frame == first.frame)
        #expect(second.frame.origin == UnderTest.away)
        first.close()
        second.close()
    }

    @Test func theBoundsIncludeTheWholeBarAndACellOutsideItAndRoundOutward() {
        let screen = NSRect(x: -1000, y: -500, width: 4000, height: 2000)
        let window = NSRect(x: 500.25, y: 500.75, width: 300.5, height: 200.5)
        let bar = BarMorph(frame: NSRect(x: 100.25, y: 100.75, width: 46, height: 500),
                           cell: NSRect(x: -20.25, y: 100.75, width: 36, height: 36))
        let geometry = AppTransition.OverlayGeometry(window: window, bar: bar, screen: screen, scale: 2)
        #expect(geometry.frame == NSRect(x: -220.5, y: -99.5, width: 1221.5, height: 1001))
        #expect(geometry.frame.contains(window) && geometry.frame.contains(bar.frame) && geometry.frame.contains(bar.cellFrame))
    }

    @Test func everyPoseMapsToTheSameScreenRectAsTheScreenSizedOverlay() {
        let screens = [NSRect(x: 0, y: 0, width: 2560, height: 1440),
                       NSRect(x: -2560, y: 240, width: 2560, height: 1440),
                       NSRect(x: 1920, y: -1440, width: 2560, height: 1440)]
        for screen in screens {
            let windows = [NSRect(x: screen.minX + 400.25, y: screen.minY + 300.75, width: 1180, height: 782),
                           NSRect(x: screen.minX - 50.25, y: screen.minY + 100.75, width: 1000, height: 622),
                           NSRect(x: screen.maxX - 700.25, y: screen.maxY - 500.75, width: 1180, height: 782)]
            let bars = [NSRect(x: screen.minX, y: screen.minY + 200.25, width: 46, height: 800),
                        NSRect(x: screen.maxX - 46, y: screen.minY + 200.25, width: 46, height: 800),
                        NSRect(x: screen.minX + 300.25, y: screen.minY, width: 1000, height: 46),
                        NSRect(x: screen.minX + 300.25, y: screen.maxY - 46, width: 1000, height: 46)]
            for frame in bars {
                for along: CGFloat in [0, 0.5, 1] {
                    let cell = NSRect(x: frame.minX + (frame.width - 36) * along,
                                      y: frame.minY + (frame.height - 36) * along, width: 36, height: 36)
                    let bar = BarMorph(frame: frame, cell: cell)
                    for window in windows {
                        for scale: CGFloat in [1, 2] {
                            let geometry = AppTransition.OverlayGeometry(window: window, bar: bar, screen: screen, scale: scale)
                            #expect(screen.contains(geometry.frame))
                            #expect(geometry.frame.contains(window.intersection(screen)))
                            #expect(geometry.frame.contains(frame))
                            for t: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                                let pose = NSRect(x: cell.minX + (window.minX - cell.minX) * t,
                                                  y: cell.minY + (window.minY - cell.minY) * t,
                                                  width: cell.width + (window.width - cell.width) * t,
                                                  height: cell.height + (window.height - cell.height) * t)
                                let old = pose.offsetBy(dx: -screen.minX, dy: -screen.minY)
                                let local = geometry.local(pose)
                                // Reconstruct the screen rect from layer bounds and position, as presentation poses do.
                                let oldScreen = NSRect(x: old.midX - old.width / 2 + screen.minX,
                                                       y: old.midY - old.height / 2 + screen.minY,
                                                       width: old.width, height: old.height)
                                let reconstructed = NSRect(x: local.midX - local.width / 2, y: local.midY - local.height / 2,
                                                           width: local.width, height: local.height)
                                #expect(geometry.screen(reconstructed) == oldScreen)
                                #expect(geometry.frame.contains(pose.intersection(screen)))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func noBarAndEntirelyAwayFramesHaveValidBounds() {
        let screen = NSRect(x: -2560.25, y: -1440.75, width: 2560, height: 1440)
        let window = NSRect(x: -2000.5, y: -1000.5, width: 300.5, height: 200.5)
        let geometry = AppTransition.OverlayGeometry(window: window, bar: nil, screen: screen, scale: 2)
        #expect(geometry.frame == NSRect(x: -2200.75, y: -1200.75, width: 701, height: 601))
        let away = AppTransition.OverlayGeometry(window: NSRect(origin: UnderTest.away, size: window.size),
                                                 bar: nil, screen: screen, scale: 2)
        #expect(away.frame == screen)
    }

    @Test func anAwayWindowsPictureUsesItsBackingScaleEvenWithoutAScreen() throws {
        let window = PictureWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 100, height: 80)),
                                   styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        #expect(window.screen == nil)
        for scale: CGFloat in [1, 2] {
            window.scale = scale
            let bitmap = try #require(CGContext(data: nil, width: Int(100 * scale), height: Int(80 * scale),
                                               bitsPerComponent: 8, bytesPerRow: Int(100 * scale) * 4,
                                               space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            var picture = AppTransition.Picture(image: try #require(bitmap.makeImage()), frame: window.frame,
                                                scale: scale, destination: .settings)
            #expect(picture.fits(window))
            window.scale = scale == 1 ? 2 : 1
            #expect(!picture.fits(window))
            window.scale = scale
            picture.frame.size.width += 1
            #expect(!picture.fits(window))
        }
    }

    /// `CALayer.render(in:)` omits this shadow. Render detached layers to a Metal texture instead, without a window or
    /// drawable. The alpha guard also rejects an empty reference, so unsupported rendering cannot pass this check.
    @Test func theShadowHasNoVisiblePixelsBeyondItsRoom() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        for scale: CGFloat in [1, 2] {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: 1200 * scale, height: 1000 * scale)
            root.contentsScale = scale
            let shadow = CALayer()
            shadow.frame = CGRect(x: 450 * scale, y: 400 * scale, width: 300 * scale, height: 200 * scale)
            shadow.contentsScale = scale
            shadow.shadowColor = NSColor.black.cgColor
            shadow.shadowRadius = AppTransition.shadowRadius * scale
            shadow.shadowOffset = CGSize(width: AppTransition.shadowOffset.width * scale,
                                         height: AppTransition.shadowOffset.height * scale)
            shadow.shadowOpacity = 1
            shadow.shadowPath = CGPath(roundedRect: shadow.bounds, cornerWidth: 16 * scale, cornerHeight: 16 * scale, transform: nil)
            root.addSublayer(shadow)
            CATransaction.commit()
            let width = Int(root.bounds.width), height = Int(root.bounds.height)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                                      mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
            let texture = try #require(device.makeTexture(descriptor: descriptor))
            let clear = MTLRenderPassDescriptor()
            clear.colorAttachments[0].texture = texture
            clear.colorAttachments[0].loadAction = .clear
            clear.colorAttachments[0].storeAction = .store
            clear.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let clearing = try #require(queue.makeCommandBuffer())
            let encoder = try #require(clearing.makeRenderCommandEncoder(descriptor: clear))
            encoder.endEncoding()
            clearing.commit()
            let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
            renderer.layer = root
            renderer.bounds = root.bounds
            CATransaction.flush()
            renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
            renderer.addUpdate(root.bounds)
            renderer.render()
            renderer.endFrame()
            let reading = try #require(queue.makeCommandBuffer())
            let blit = try #require(reading.makeBlitCommandEncoder())
            if texture.storageMode == .managed { blit.synchronize(resource: texture) }
            blit.endEncoding()
            reading.commit()
            reading.waitUntilCompleted()
            #expect(reading.status == .completed)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { bytes in
                texture.getBytes(bytes.baseAddress!, bytesPerRow: width * 4,
                                 from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            let room = shadow.frame.insetBy(dx: -AppTransition.shadowRoom * scale, dy: -AppTransition.shadowRoom * scale)
            var outside = 0, blur = 0
            for y in 0..<height {
                for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                    let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    if !room.contains(point) { outside += 1 }
                    if !shadow.frame.contains(point) { blur += 1 }
                }
            }
            #expect(blur > 0, "The reference must render a shadow, so the padding check cannot pass on an empty raster")
            #expect(outside == 0)
            #expect(AppTransition.shadowRoom > 4 * AppTransition.shadowRadius + abs(AppTransition.shadowOffset.height))
        }
    }
}

@MainActor
private final class PictureWindow: AwayWindow {
    var scale: CGFloat = 1
    override var backingScaleFactor: CGFloat { scale }
}
