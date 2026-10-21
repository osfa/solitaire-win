import AppKit
import Metal
import MetalKit

private struct StampUniforms {
    var virtW, virtH, cardW, cardH, atlasW, atlasH, offX, offY, strideExtra: Float
    var pad0: Float = 0, pad1: Float = 0, pad2: Float = 0
}

private struct CanvasUniforms {
    var mode: Float = 0, texW: Float = 0, texH: Float = 0, seed: Float = 0, bands: Float = 0, amount: Float = 0
    var dx: Float = 0, dy: Float = 0, rx0: Float = 0, ry0: Float = 0, rx1: Float = 0, ry1: Float = 0
    var feltR: Float = 0, feltG: Float = 128.0 / 255.0, feltB: Float = 0, pad: Float = 0
}

private struct PostUniforms {
    var texW, texH, time, seed, hue, paletteMix, paletteShift, invert, split, tear, feltMix, ftR, ftG, ftB, pixelScale: Float
    var pad: Float = 0
}

/// Keeps the felt-and-trails canvas on the GPU and draws it to the view through the post effects.
final class Renderer {
    static let felt = MTLClearColor(red: 0, green: 128.0 / 255.0, blue: 0, alpha: 1)
    static let referenceHeight = 540.0

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let stampPipe: MTLRenderPipelineState
    private let canvasPipe: MTLRenderPipelineState
    private let postPipe: MTLRenderPipelineState
    private let atlas: MTLTexture
    private var canvas: MTLTexture?
    private var scratch: MTLTexture?
    private var scrollAcc = SIMD2<Double>(0, 0)
    private var time = 0.0
    private let seed = Float.random(in: 0...1000)
    private var snapshotRequest: URL?

    private(set) var pixelScale = 1.0
    var virtualSize: SIMD2<Double> {
        guard let canvas else { return .zero }
        return SIMD2(Double(canvas.width), Double(canvas.height)) / pixelScale
    }
    var hasTargets: Bool { canvas != nil }

    init?(view: MTKView) {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let lib = try? device.makeLibrary(source: shaderSource, options: nil) else { return nil }
        self.device = device
        self.queue = queue

        func pipe(_ vs: String, _ fs: String, _ format: MTLPixelFormat) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: vs)
            d.fragmentFunction = lib.makeFunction(name: fs)
            d.colorAttachments[0].pixelFormat = format
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let s = pipe("stampVS", "stampFS", .rgba8Unorm),
              let c = pipe("fullVS", "canvasFS", .rgba8Unorm),
              let p = pipe("fullVS", "postFS", view.colorPixelFormat) else { return nil }
        stampPipe = s
        canvasPipe = c
        postPipe = p

        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: CardArt.atlasW,
                                                         height: CardArt.atlasH, mipmapped: false)
        d.usage = .shaderRead
        guard let atlas = device.makeTexture(descriptor: d) else { return nil }
        let bytes = CardArt.makeAtlas()
        atlas.replace(region: MTLRegionMake2D(0, 0, CardArt.atlasW, CardArt.atlasH), mipmapLevel: 0,
                      withBytes: bytes, bytesPerRow: CardArt.atlasW * 4)
        self.atlas = atlas
    }

    /// Returns true when the canvas was (re)made, which wipes it.
    func ensureTargets(size: CGSize) -> Bool {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return false }
        if let canvas, canvas.width == w, canvas.height == h { return false }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        canvas = device.makeTexture(descriptor: d)
        scratch = device.makeTexture(descriptor: d)
        var s = Double(h) / Self.referenceHeight
        if s >= 1.5 { s = s.rounded() }
        pixelScale = s
        return canvas != nil
    }

    func requestSnapshot(to url: URL) { snapshotRequest = url }

    func render(in view: MTKView, engine: Engine, params: Params, dt: Double) {
        // MTKView.currentDrawable only refreshes inside MTKView.draw(), which we never call.
        guard let layer = view.layer as? CAMetalLayer, let drawable = layer.nextDrawable(), canvas != nil,
              let cmd = queue.makeCommandBuffer() else { return }
        time += dt
        let look = params.look

        if engine.wipe || !engine.stamps.isEmpty { encodeStamps(cmd, engine: engine, look: look) }

        let ps = Float(pixelScale)
        for op in engine.canvasOps {
            var u = CanvasUniforms()
            switch op {
            case let .slices(seed, bands, shift):
                u.mode = 1; u.seed = Float(seed); u.bands = Float(bands); u.amount = Float(shift) * ps
            case let .erase(x0, y0, x1, y1):
                u.mode = 3; u.rx0 = Float(x0) * ps; u.ry0 = Float(y0) * ps; u.rx1 = Float(x1) * ps; u.ry1 = Float(y1) * ps
            case let .melt(seed, column, amount):
                u.mode = 4; u.seed = Float(seed); u.bands = Float(column) * ps; u.amount = Float(amount) * ps
            }
            encodeCanvasPass(cmd, u)
        }
        scrollAcc += look.scroll * dt * pixelScale
        let whole = scrollAcc.rounded(.towardZero)
        if whole != .zero {
            scrollAcc -= whole
            var u = CanvasUniforms()
            u.mode = 2; u.dx = Float(whole.x); u.dy = Float(whole.y)
            encodeCanvasPass(cmd, u)
        }

        var post = PostUniforms(texW: Float(canvas!.width), texH: Float(canvas!.height), time: Float(time), seed: seed,
                                hue: Float(look.hue), paletteMix: Float(look.paletteMix),
                                paletteShift: Float(max(0, look.paletteShift)), invert: Float(look.invert),
                                split: Float(look.rgbSplit) * ps, tear: Float(look.tear), feltMix: Float(look.feltMix),
                                ftR: Float(look.feltTint.x), ftG: Float(look.feltTint.y), ftB: Float(look.feltTint.z),
                                pixelScale: ps)
        encodePost(cmd, target: drawable.texture, &post)

        var snap: (MTLTexture, URL)?
        if let url = snapshotRequest {
            snapshotRequest = nil
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: canvas!.width,
                                                             height: canvas!.height, mipmapped: false)
            d.usage = [.renderTarget]
            d.storageMode = .managed
            if let t = device.makeTexture(descriptor: d) {
                encodePost(cmd, target: t, &post)
                if let blit = cmd.makeBlitCommandEncoder() {
                    blit.synchronize(resource: t)
                    blit.endEncoding()
                }
                snap = (t, url)
            }
        }

        cmd.present(drawable)
        cmd.commit()
        if let (t, url) = snap {
            cmd.waitUntilCompleted()
            Self.writePNG(t, to: url)
        }
    }

    private func encodeStamps(_ cmd: MTLCommandBuffer, engine: Engine, look: LookParams) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = canvas
        rp.colorAttachments[0].loadAction = engine.wipe ? .clear : .load
        rp.colorAttachments[0].clearColor = Self.felt
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rp) else { return }
        let n = engine.stamps.count
        if n > 0, let buf = device.makeBuffer(bytes: engine.stamps, length: n * MemoryLayout<Stamp>.stride, options: .storageModeShared) {
            let size = virtualSize
            var u = StampUniforms(virtW: Float(size.x), virtH: Float(size.y),
                                  cardW: Float(CardArt.cardW), cardH: Float(CardArt.cardH),
                                  atlasW: Float(CardArt.atlasW), atlasH: Float(CardArt.atlasH),
                                  offX: Float(look.atlasOffset.x), offY: Float(look.atlasOffset.y),
                                  strideExtra: Float(look.strideExtra))
            enc.setRenderPipelineState(stampPipe)
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<StampUniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<StampUniforms>.stride, index: 1)
            enc.setFragmentTexture(atlas, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: n)
        }
        enc.endEncoding()
    }

    private func encodeCanvasPass(_ cmd: MTLCommandBuffer, _ uniforms: CanvasUniforms) {
        guard let src = canvas, let dst = scratch else { return }
        var u = uniforms
        u.texW = Float(src.width)
        u.texH = Float(src.height)
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = dst
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(canvasPipe)
        enc.setFragmentTexture(src, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<CanvasUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        canvas = dst
        scratch = src
    }

    private func encodePost(_ cmd: MTLCommandBuffer, target: MTLTexture, _ u: inout PostUniforms) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(postPipe)
        enc.setFragmentTexture(canvas, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<PostUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private static func writePNG(_ t: MTLTexture, to url: URL) {
        let w = t.width, h = t.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        t.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue),
              let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
