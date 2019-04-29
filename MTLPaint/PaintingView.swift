//
//  PaintingView.swift
//  MTLPaint
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/1/4.
//  Migrated to Metal by OOPer in cooperation with shlab.jp, on 2019/4/26.
//

import UIKit
import Metal
import MetalKit

enum LoadAction {
    case load
    case clear(red: Double, green: Double, blue: Double, alpha: Double)
}
/*
 //### Calling this method caused Segmentation Fault: 11 in Xcode 10.2.1
extension LoadAction {
    func apply(to attachement: MTLRenderPassColorAttachmentDescriptor) {
        switch self {
        case let .clear(red: red, green: green, blue: blue, alpha: alpha):
            attachement.loadAction = .clear
            attachement.clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: alpha)
        case .load:
            attachement.loadAction = .load
        }
    }
}
 */

//CONSTANTS:

let kBrushOpacity = (1.0 / 3.0)
let kBrushPixelStep = 3
let kBrushScale = 2


// Shaders
let PROGRAM_POINT = 0

let UNIFORM_MVP = 0
let UNIFORM_POINT_SIZE = 1
let UNIFORM_VERTEX_COLOR = 2
//let UNIFORM_TEXTURE = 3
//let NUM_UNIFORMS = 4

//let ATTRIB_VERTEX = 0
//let NUM_ATTRIBS = 1

//typealias programInfo_t = (
//    vert: String, frag: String,
//    uniform: [GLint],
//    id: GLuint)
struct ProgramInfo {
    var vert: String
    var frag: String
    var uniform: [MTLBuffer?] = []
    var pipelineState: MTLRenderPipelineState!
}

//var program: [programInfo_t] = [
//    ("point.vsh",   "point.fsh", Array(repeating: 0, count: NUM_UNIFORMS), 0),     // PROGRAM_POINT
//]
var program: [ProgramInfo] = [
    ProgramInfo(vert: "PointVertex", frag: "PointFragment", uniform: [], pipelineState: nil),     // PROGRAM_POINT
]
let NUM_PROGRAMS = program.count


// Texture
//typealias textureInfo_t = (
//    id: GLuint,
//    width: GLsizei, height: GLsizei)
struct TextureInfo {
    var texture: MTLTexture?
    var sampler: MTLSamplerState?
    
    init() {
        texture = nil
        sampler = nil
    }
}


class PaintingView: UIView {
    // The pixel dimensions of the backbuffer
    //private var backingWidth: GLint = 0
    private var backingWidth: Int = 0
    //private var backingHeight: GLint = 0
    private var backingHeight: Int = 0

//    private var context: EAGLContext!
    private var metalDevice: MTLDevice
    private var metalCommandQueue: MTLCommandQueue
    
//    // OpenGL names for the renderbuffer and framebuffers used to render to this view
//    private var viewRenderbuffer: GLuint = 0, viewFramebuffer: GLuint = 0
    //### [kEAGLDrawablePropertyRetainedBacking]
    private var renderTargetTexture: MTLTexture!
//
//    // OpenGL name for the depth buffer that is attached to viewFramebuffer, if it exists (0 if it does not exist)
//    private var depthRenderbuffer: GLuint = 0

    //private var brushTexture: textureInfo_t = (0, 0, 0)     // brush texture
    private var brushTexture: TextureInfo!     // brush texture
    //private var brushColor: [GLfloat] = [0, 0, 0, 0]          // brush color
    private var brushColor: [Float] = [0, 0, 0, 0]          // brush color

    private var firstTouch: Bool = false
    private var needsErase: Bool = false

//    // Shader objects
//    private var vertexShader: GLuint = 0
//    private var fragmentShader: GLuint = 0
//    private var shaderProgram: GLuint = 0

//    // Buffer Objects
//    private var vboId: GLuint = 0
    
    //View port
    private var viewport: MTLViewport!

    private var initialized: Bool = false

    var location: CGPoint = CGPoint()
    var previousLocation: CGPoint = CGPoint()

    // Implement this to override the default layer class (which is [CALayer class]).
    // We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.
    override class var layerClass : AnyClass {
        //return CAEAGLLayer.self
        return CAMetalLayer.self
    }

    // The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
    required init?(coder: NSCoder) {
        guard
            let metalDevice = MTLCreateSystemDefaultDevice(),
            let metalCommandQueue = metalDevice.makeCommandQueue()
        else {
            fatalError("Metal is unavalable")
        }
        self.metalDevice = metalDevice
        self.metalCommandQueue = metalCommandQueue

        super.init(coder: coder)
        //let eaglLayer = self.layer as! CAEAGLLayer
        let metalLayer = self.layer as! CAMetalLayer
        metalLayer.framebufferOnly = false

        //eaglLayer.isOpaque = true
        metalLayer.isOpaque = true
        // In this application, we want to retain the EAGLDrawable contents after a call to presentRenderbuffer.
        //eaglLayer.drawableProperties = [
        //    kEAGLDrawablePropertyRetainedBacking: true,
        //    kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
        //]
        //### No simple ways to simulate `kEAGLDrawablePropertyRetainedBacking: true`
        //### See codes marked as [kEAGLDrawablePropertyRetainedBacking]
        metalLayer.pixelFormat = .bgra8Unorm
//
//        context = EAGLContext(api: .openGLES2)
//
//        if context == nil || !EAGLContext.setCurrent(context) {
//            fatalError("EAGLContext cannot be created")
//        }

        // Set the view's scale factor as you wish
        self.contentScaleFactor = UIScreen.main.scale

        // Make sure to start with a cleared buffer
        needsErase = true

    }

    // If our view is resized, we'll be asked to layout subviews.
    // This is the perfect opportunity to also update the framebuffer so that it is
    // the same size as our display area.
    override func layoutSubviews() {
//        EAGLContext.setCurrent(context)

        if !initialized {
            //initialized = self.initGL()
            initialized = initMetal()
        } else {
            //self.resize(from: self.layer as! CAEAGLLayer)
            self.resize(from: self.layer as! CAMetalLayer)
        }

        // Clear the framebuffer the first time it is allocated
        if needsErase {
            self.erase()
            needsErase = false
        }
    }

    private func setupShaders() {
        let defaultLibrary = metalDevice.makeDefaultLibrary()!
        for i in 0..<NUM_PROGRAMS {
            //let vsrc = readData(forResource: program[i].vert)
            let vertexProgram = defaultLibrary.makeFunction(name: program[i].vert)!
            //let fsrc = readData(forResource: program[i].frag)
            let fragmentProgram = defaultLibrary.makeFunction(name: program[i].frag)!
            //var attribUsed: [String] = []
            //var attrib: [GLuint] = []
            //let attribName: [String] = [
            //    "inVertex",
            //    ]
            //let uniformName: [String] = [
            //    "MVP", "pointSize", "vertexColor", "texture",
            //    ]

            //var prog: GLuint = 0
            //vsrc.withUnsafeBytes {vsrcBytes in
            //    let vsrcChars = vsrcBytes.bindMemory(to: GLchar.self).baseAddress!

            //    // auto-assign known attribs
            //    for (j, name) in attribName.enumerated() {
            //        if strstr(vsrcChars, name) != nil {
            //            attrib.append(j.ui)
            //            attribUsed.append(name)
            //        }
            //    }

            //    fsrc.withUnsafeBytes {fsrcBytes in
            //        let fsrcChars = fsrcBytes.bindMemory(to: GLchar.self).baseAddress!
            //        _ = glue.createProgram(UnsafeMutablePointer(mutating: vsrcChars), UnsafeMutablePointer(mutating: fsrcChars),
            //                               attribUsed, attrib,
            //                               uniformName, &program[i].uniform,
            //                               &prog)
            //    }
            //}
            //program[i].id = prog
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            //### Blending setups
            // Enable blending and set a blending function appropriate for premultiplied alpha pixel data
            pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            program[i].pipelineState = try! metalDevice
                .makeRenderPipelineState(descriptor: pipelineStateDescriptor)

            // Set constant/initalize uniforms
            if i == PROGRAM_POINT {
//                glUseProgram(program[PROGRAM_POINT].id)

                // the brush texture will be bound to texture unit 0
                //glUniform1i(program[PROGRAM_POINT].uniform[UNIFORM_TEXTURE], 0)
                //### Texture will be bound to encoder

                // viewing matrices
                print(backingWidth, backingHeight)
                //let projectionMatrix = GLKMatrix4MakeOrtho(0, backingWidth.f, 0, backingHeight.f, -1, 1)
                let projectionMatrix = float4x4.orthoLeftHand(0, backingWidth.f, 0, backingHeight.f, -1, 1)
                //let modelViewMatrix = GLKMatrix4Identity
                let modelViewMatrix = float4x4.identity
                //var MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix)
                var MVPMatrix = projectionMatrix * modelViewMatrix

                //withUnsafePointer(to: &MVPMatrix) {ptrMVP in
                //    ptrMVP.withMemoryRebound(to: GLfloat.self, capacity: 16) {ptrGLfloat in
                //        glUniformMatrix4fv(program[PROGRAM_POINT].uniform[UNIFORM_MVP], 1, GL_FALSE.ub, ptrGLfloat)
                //    }
                //}
                let uniformMVP = metalDevice.makeBuffer(bytes: &MVPMatrix, length: MemoryLayout<float4x4>.size)
                
                // point size
                //glUniform1f(program[PROGRAM_POINT].uniform[UNIFORM_POINT_SIZE], brushTexture.width.f / kBrushScale.f)
                var pointSize = (brushTexture.texture?.width.f ?? 0) / kBrushScale.f
                let uniformPointSize = metalDevice.makeBuffer(bytes: &pointSize, length: MemoryLayout<Float>.size)

                // initialize brush color
                //glUniform4fv(program[PROGRAM_POINT].uniform[UNIFORM_VERTEX_COLOR], 1, brushColor)
                let uniformVertexColor = metalDevice.makeBuffer(bytes: brushColor, length: MemoryLayout<Float>.size * brushColor.count)
                
                program[i].uniform = [uniformMVP, uniformPointSize, uniformVertexColor]
            }
        }

//        glError()
    }

    // Create a texture from an image
    //private func texture(fromName name: String) -> textureInfo_t {
    private func texture(fromName name: String) -> TextureInfo {
        //var texId: GLuint = 0
        //var texture: textureInfo_t = (0, 0, 0)
        var texture = TextureInfo()

        // First create a UIImage object from the data in a image file, and then extract the Core Graphics image
        let brushImage = UIImage(named: name)?.cgImage

        // Get the width and height of the image
        let width: size_t = brushImage!.width
        let height: size_t = brushImage!.height

        // Make sure the image exists
        if brushImage != nil {
            
            // Allocate  memory needed for the bitmap context
            //var brushData = [GLubyte](repeating: 0, count: width * height * 4)
            var brushData = [UInt8](repeating: 0, count: width * height * 4)
            // Use  the bitmatp creation function provided by the Core Graphics framework.
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            let brushContext = CGContext(data: &brushData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: (brushImage?.colorSpace!)!, bitmapInfo: bitmapInfo)
            // After you create the context, you can draw the  image to the context.
            brushContext?.draw(brushImage!, in: CGRect(x: 0.0, y: 0.0, width: width.g, height: height.g))
            // You don't need the context at this point, so you need to release it to avoid memory leaks.
            //### ARC manages
            // Use OpenGL ES to generate a name for the texture.
            //glGenTextures(1, &texId)
            // Bind the texture name.
            //glBindTexture(GL_TEXTURE_2D.ui, texId)
            let loader = MTKTextureLoader(device: metalDevice)
            do {
                texture.texture = try loader.newTexture(cgImage: brushContext!.makeImage()!)
            } catch {
                print(error)
                return texture
            }
            // Set the texture parameters to use a minifying filter and a linear filer (weighted average)
            //glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_MIN_FILTER.ui, GL_LINEAR)
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            texture.sampler = metalDevice.makeSamplerState(descriptor: samplerDescriptor)
            // Specify a 2D texture image, providing the a pointer to the image data in memory
            //glTexImage2D(GL_TEXTURE_2D.ui, 0, GL_RGBA, width.i, height.i, 0, GL_RGBA.ui, GL_UNSIGNED_BYTE.ui, brushData)
            //### MTKTextureLoader automatically generates 2D texture
            // Release  the image data; it's no longer needed
            //### ARC manages

//            texture.id = texId
//            texture.width = width.i
//            texture.height = height.i
        }

        return texture
    }

//    private func initGL() -> Bool {
    @discardableResult
    private func initMetal() -> Bool {
//        // Generate IDs for a framebuffer object and a color renderbuffer
//        glGenFramebuffers(1, &viewFramebuffer)
//        glGenRenderbuffers(1, &viewRenderbuffer)
//
//        glBindFramebuffer(GL_FRAMEBUFFER.ui, viewFramebuffer)
//        glBindRenderbuffer(GL_RENDERBUFFER.ui, viewRenderbuffer)
//        // This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
//        // allowing us to draw into a buffer that will later be rendered to screen wherever the layer is (which corresponds with our view).
//        context.renderbufferStorage(GL_RENDERBUFFER.l, from: (self.layer as! EAGLDrawable))
//        glFramebufferRenderbuffer(GL_FRAMEBUFFER.ui, GL_COLOR_ATTACHMENT0.ui, GL_RENDERBUFFER.ui, viewRenderbuffer)
//
//        glGetRenderbufferParameteriv(GL_RENDERBUFFER.ui, GL_RENDERBUFFER_WIDTH.ui, &backingWidth)
        backingWidth = Int(self.bounds.width * self.contentScaleFactor)
//        glGetRenderbufferParameteriv(GL_RENDERBUFFER.ui, GL_RENDERBUFFER_HEIGHT.ui, &backingHeight)
        backingHeight = Int(self.bounds.height * self.contentScaleFactor)
//
//        // For this sample, we do not need a depth buffer. If you do, this is how you can create one and attach it to the framebuffer:
//        //    glGenRenderbuffers(1, &depthRenderbuffer);
//        //    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
//        //    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
//        //    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
//
//        if glCheckFramebufferStatus(GL_FRAMEBUFFER.ui) != GL_FRAMEBUFFER_COMPLETE.ui {
//            NSLog("failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER.ui))
//            return false
//        }

        // Setup the view port in Pixels
        //glViewport(0, 0, backingWidth, backingHeight)
        viewport = MTLViewport(originX: 0, originY: 0, width: backingWidth.d, height: backingHeight.d, znear: 0, zfar: 1)
//
//        // Create a Vertex Buffer Object to hold our data
//        glGenBuffers(1, &vboId)

        // Load the brush texture
        brushTexture = self.texture(fromName: "Particle.png")

        // Load shaders
        self.setupShaders()

        // Enable blending and set a blending function appropriate for premultiplied alpha pixel data
        //glEnable(GL_BLEND.ui)
        //glBlendFunc(GL_ONE.ui, GL_ONE_MINUS_SRC_ALPHA.ui)
        //### Blending setups moved into setupShaders()

        // Playback recorded path, which is "Shake Me"
        let recordedPaths = NSArray(contentsOfFile: Bundle.main.path(forResource: "Recording", ofType: "data")!)! as! [Data]
        if recordedPaths.count != 0 {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 200 * NSEC_PER_MSEC.d / NSEC_PER_SEC.d) {
                self.playback(recordedPaths, fromIndex: 0)
            }
        }

        return true
    }

    @discardableResult
    //private func resize(from layer: CAEAGLLayer) -> Bool {
    private func resize(from layer: CAMetalLayer) -> Bool {
        // Allocate color buffer backing based on the current layer size
        //glBindRenderbuffer(GL_RENDERBUFFER.ui, viewRenderbuffer)
        //context.renderbufferStorage(GL_RENDERBUFFER.l, from: layer)
        //### Set nil to refresh renderTargetTexture
        renderTargetTexture = nil
        //glGetRenderbufferParameteriv(GL_RENDERBUFFER.ui, GL_RENDERBUFFER_WIDTH.ui, &backingWidth)
        backingWidth = Int(self.bounds.width * self.contentScaleFactor)
        //glGetRenderbufferParameteriv(GL_RENDERBUFFER.ui, GL_RENDERBUFFER_HEIGHT.ui, &backingHeight)
        backingHeight = Int(self.bounds.height * self.contentScaleFactor)

//        // For this sample, we do not need a depth buffer. If you do, this is how you can allocate depth buffer backing:
//        //    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
//        //    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
//        //    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
//
//        if glCheckFramebufferStatus(GL_FRAMEBUFFER.ui) != GL_FRAMEBUFFER_COMPLETE.ui {
//            NSLog("Failed to make complete framebuffer objectz %x", glCheckFramebufferStatus(GL_FRAMEBUFFER.ui))
//            return false
//        }

        // Update projection matrix
        //let projectionMatrix = GLKMatrix4MakeOrtho(0, backingWidth.f, 0, backingHeight.f, -1, 1)
        let projectionMatrix = float4x4.orthoLeftHand(0, backingWidth.f, 0, backingHeight.f, -1, 1)
        //let modelViewMatrix = GLKMatrix4Identity // this sample uses a constant identity modelView matrix
        let modelViewMatrix = float4x4.identity // this sample uses a constant identity modelView matrix
        //var MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix)
        var MVPMatrix = projectionMatrix * modelViewMatrix

        //glUseProgram(program[PROGRAM_POINT].id)
        //withUnsafePointer(to: &MVPMatrix) {ptrMVP in
        //    ptrMVP.withMemoryRebound(to: GLfloat.self, capacity: 16) {ptrGLfloat in
        //        glUniformMatrix4fv(program[PROGRAM_POINT].uniform[UNIFORM_MVP], 1, GL_FALSE.ub, ptrGLfloat)
        //    }
        //}
        let uniformMVP = metalDevice.makeBuffer(bytes: &MVPMatrix, length: MemoryLayout<float4x4>.size)
        program[PROGRAM_POINT].uniform[UNIFORM_MVP] = uniformMVP

        // Update viewport
        //glViewport(0, 0, backingWidth, backingHeight)
        viewport = MTLViewport(originX: 0, originY: 0, width: backingWidth.d, height: backingHeight.d, znear: 0, zfar: 1)

        return true
    }

    // Releases resources when they are not longer needed.
//    deinit {
//        // Destroy framebuffers and renderbuffers
//        if viewFramebuffer != 0 {
//            glDeleteFramebuffers(1, &viewFramebuffer)
//        }
//        if viewRenderbuffer != 0 {
//            glDeleteRenderbuffers(1, &viewRenderbuffer)
//        }
//        if depthRenderbuffer != 0 {
//            glDeleteRenderbuffers(1, &depthRenderbuffer)
//        }
//        // texture
//        if brushTexture.id != 0 {
//            glDeleteTextures(1, &brushTexture.id)
//        }
//        // vbo
//        if vboId != 0 {
//            glDeleteBuffers(1, &vboId)
//        }
//
//        // tear down context
//        if EAGLContext.current() === context {
//            EAGLContext.setCurrent(context)
//        }
//    }
  
    private static let defaultLoadAction: LoadAction = .clear(red: 0, green: 0, blue: 0, alpha: 0)
    private func drawInNextDrawable(
        loadAction: LoadAction = defaultLoadAction,
        drawing: (MTLRenderCommandEncoder)->Void
    ) {
        
        guard let drawable = (self.layer as! CAMetalLayer).nextDrawable() else {
            return
        }
        //### [kEAGLDrawablePropertyRetainedBacking]
        if renderTargetTexture == nil {
            renderTargetTexture = createRenderTargetTexture(from: drawable.texture)
        }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor.colorAttachments[0]!
        //### [kEAGLDrawablePropertyRetainedBacking]
        //### First draw to the offline render target
        attachment.texture = self.renderTargetTexture
        //### Calling this method caused Segmentation Fault: 11 in Xcode 10.2.1
        //  loadAction.apply(to: renderPassDescriptor.colorAttachments[0])
        // or
        //  apply(loadAction, to: renderPassDescriptor.colorAttachments[0])
        switch loadAction {
        case .load:
            attachment.loadAction = .load
        case let .clear(red: red, green: green, blue: blue, alpha: alpha):
            // Clear the buffer
            attachment.loadAction = .clear
            attachment.clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        attachment.storeAction = .store

        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else {
            return
        }
        
        guard let renderEncoder = commandBuffer
            .makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
        }

        drawing(renderEncoder)
        
        renderEncoder.endEncoding()
        
        // Display the buffer
        //### [kEAGLDrawablePropertyRetainedBacking]
        //### Copy render target to drawable
        let blit = commandBuffer.makeBlitCommandEncoder()!
        let sourceSize = MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1)
        blit.copy(from: renderTargetTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: sourceSize, to: drawable.texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
/*
     //### Calling this method caused Segmentation Fault: 11 in Xcode 10.2.1
    private func apply(_ loadAction: LoadAction, to attachement: MTLRenderPassColorAttachmentDescriptor) {
        switch loadAction {
        case .load:
            attachement.loadAction = .load
        case let .clear(red: red, green: green, blue: blue, alpha: alpha):
            attachement.loadAction = .clear
            attachement.clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    }
*/
    
    // Erases the screen
    func erase() {
        //EAGLContext.setCurrent(context)

        // Clear the buffer
        //glBindFramebuffer(GL_FRAMEBUFFER.ui, viewFramebuffer)
        //glClearColor(0.0, 0.0, 0.0, 0.0)
        //glClear(GL_COLOR_BUFFER_BIT.ui)
        //### included in the prologue part of `drawInNextDrawable`
        drawInNextDrawable{_ in
            //Nothing more...
        }

        // Display the buffer
        //glBindRenderbuffer(GL_RENDERBUFFER.ui, viewRenderbuffer)
        //context.presentRenderbuffer(GL_RENDERBUFFER.l)
        //### included in the epilogue part of `drawInNextDrawable`
    }

    // Drawings a line onscreen based on where the user touches
    private func renderLine(from _start: CGPoint, to _end: CGPoint) {
//        struct Static {
//            static var vertexBuffer: [GLfloat] = []
//        }

//        EAGLContext.setCurrent(context)
//        glBindFramebuffer(GL_FRAMEBUFFER.ui, viewFramebuffer)

        // Convert locations from Points to Pixels
        let scale = self.contentScaleFactor
        var start = _start
        start.x *= scale
        start.y *= scale
        var end = _end
        end.x *= scale
        end.y *= scale

        // Allocate vertex array buffer
        //### No need to make this array static
        var vertexBuffer: [Float] = []

        // Add points to the buffer so there are drawing points every X pixels
        let count = max(Int(ceilf(sqrtf((end.x - start.x).f * (end.x - start.x).f + (end.y - start.y).f * (end.y - start.y).f) / kBrushPixelStep.f)), 1)
        //Static.vertexBuffer.reserveCapacity(count * 2)
        vertexBuffer.reserveCapacity(count * 2)
        //Static.vertexBuffer.removeAll(keepingCapacity: true)
        for i in 0..<count {

            //Static.vertexBuffer.append(start.x.f + (end.x - start.x).f * (i.f / count.f))
            vertexBuffer.append(start.x.f + (end.x - start.x).f * (i.f / count.f))
            //Static.vertexBuffer.append(start.y.f + (end.y - start.y).f * (i.f / count.f))
            vertexBuffer.append(start.y.f + (end.y - start.y).f * (i.f / count.f))
        }

        drawInNextDrawable(loadAction: .load) {encoder in
        // Load data to the Vertex Buffer Object
        //glBindBuffer(GL_ARRAY_BUFFER.ui, vboId)
        //glBufferData(GL_ARRAY_BUFFER.ui, count*2*MemoryLayout<GLfloat>.size, Static.vertexBuffer, GL_DYNAMIC_DRAW.ui)
            encoder.setVertexBytes(vertexBuffer, length: count*2*MemoryLayout<Float>.size, index: 0)

//        glEnableVertexAttribArray(ATTRIB_VERTEX.ui)
//        glVertexAttribPointer(ATTRIB_VERTEX.ui, 2, GL_FLOAT.ui, GL_FALSE.ub, 0, nil)

        // Draw
        //glUseProgram(program[PROGRAM_POINT].id)
            encoder.setRenderPipelineState(program[PROGRAM_POINT].pipelineState)
            encoder.setVertexBuffer(program[PROGRAM_POINT].uniform[UNIFORM_MVP], offset: 0, index: 1)
            encoder.setVertexBuffer(program[PROGRAM_POINT].uniform[UNIFORM_POINT_SIZE], offset: 0, index: 2)
            encoder.setVertexBuffer(program[PROGRAM_POINT].uniform[UNIFORM_VERTEX_COLOR], offset: 0, index: 3)
            encoder.setFragmentTexture(brushTexture.texture, index: 0)
            encoder.setFragmentSamplerState(brushTexture.sampler, index: 0)
        //glDrawArrays(GL_POINTS.ui, 0, count.i)
            encoder.setViewport(viewport)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
        }
        // Display the buffer
        //glBindRenderbuffer(GL_RENDERBUFFER.ui, viewRenderbuffer)
        //context.presentRenderbuffer(GL_RENDERBUFFER.l)
        //### included in the epilogue part of `drawInNextDrawable`
    }

    // Reads previously recorded points and draws them onscreen. This is the Shake Me message that appears when the application launches.

    private func playback(_ recordedPaths: [Data], fromIndex index: Int) {
        // NOTE: Recording.data is stored with 32-bit floats
        // To make it work on both 32-bit and 64-bit devices, we make sure we read back 32 bits each time.

        let data = recordedPaths[index]
        let count = data.count / (MemoryLayout<Float32>.size*2) // each point contains 64 bits (32-bit x and 32-bit y)

        // Render the current path
        data.withUnsafeBytes { bytes in
            let floats = bytes.bindMemory(to: Float32.self).baseAddress!
            for i in 0..<count - 1 {

                var x = floats[2*i]
                var y = floats[2*i+1]
                let point1 = CGPoint(x: x.g, y: y.g)

                x = floats[2*(i+1)]
                y = floats[2*(i+1)+1]
                let point2 = CGPoint(x: x.g, y: y.g)

                self.renderLine(from: point1, to: point2)
            }
        }

        // Render the next path after a short delay
        if recordedPaths.count > index+1 {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 10 * NSEC_PER_MSEC.d / NSEC_PER_SEC.d) {
                self.playback(recordedPaths, fromIndex: index+1)
            }
        }
    }


    // Handles the start of a touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let bounds = self.bounds
        let touch = event!.touches(for: self)!.first!
        firstTouch = true
        // Convert touch point from UIView referential to OpenGL one (upside-down flip)
        location = touch.location(in: self)
        location.y = bounds.size.height - location.y
    }

    // Handles the continuation of a touch.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let bounds = self.bounds
        let touch = event!.touches(for: self)!.first!

        // Convert touch point from UIView referential to OpenGL one (upside-down flip)
        if firstTouch {
            firstTouch = false
            previousLocation = touch.previousLocation(in: self)
            previousLocation.y = bounds.size.height - previousLocation.y
        } else {
            location = touch.location(in: self)
            location.y = bounds.size.height - location.y
            previousLocation = touch.previousLocation(in: self)
            previousLocation.y = bounds.size.height - previousLocation.y
        }

        // Render the stroke
        self.renderLine(from: previousLocation, to: location)
    }

    // Handles the end of a touch event when the touch is a tap.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let bounds = self.bounds
        let touch = event!.touches(for: self)!.first!
        if firstTouch {
            firstTouch = false
            previousLocation = touch.previousLocation(in: self)
            previousLocation.y = bounds.size.height - previousLocation.y
            self.renderLine(from: previousLocation, to: location)
        }
    }

    // Handles the end of a touch event.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // If appropriate, add code necessary to save the state of the application.
        // This application is not saving state.
    }

    func setBrushColor(red: CGFloat, green: CGFloat, blue: CGFloat) {
        // Update the brush color
        brushColor[0] = red.f * kBrushOpacity.f
        brushColor[1] = green.f * kBrushOpacity.f
        brushColor[2] = blue.f * kBrushOpacity.f
        brushColor[3] = kBrushOpacity.f

        if initialized {
            //glUseProgram(program[PROGRAM_POINT].id)
            //glUniform4fv(program[PROGRAM_POINT].uniform[UNIFORM_VERTEX_COLOR], 1, brushColor)
            let uniformVertexColor = metalDevice.makeBuffer(bytes: brushColor, length: MemoryLayout<Float>.size * brushColor.count)
            program[PROGRAM_POINT].uniform[UNIFORM_VERTEX_COLOR] = uniformVertexColor
        }
    }


    override var canBecomeFirstResponder : Bool {
        return true
    }

    //### [kEAGLDrawablePropertyRetainedBacking]
    private func createRenderTargetTexture(from texture: MTLTexture) -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = MTLTextureType.type2D
        textureDescriptor.width = texture.width
        textureDescriptor.height = texture.height
        textureDescriptor.pixelFormat = texture.pixelFormat
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        
        let sampleTexture = metalDevice.makeTexture(descriptor: textureDescriptor)
        return sampleTexture!
    }
}
