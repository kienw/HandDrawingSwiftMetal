//
//  CanvasViewModel.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/12/10.
//

import MetalKit
import Combine

final class CanvasViewModel {

    let canvasTransformer = CanvasTransformer()

    let textureLayers = TextureLayers()

    let textureLayerUndoManager = TextureLayerUndoManager()

    let drawingTool = CanvasDrawingToolStatus()

    var frameSize: CGSize = .zero

    /// A name of the file to be saved
    var projectName: String = Calendar.currentDate

    var pauseDisplayLinkPublisher: AnyPublisher<Bool, Never> {
        pauseDisplayLinkSubject.eraseToAnyPublisher()
    }

    var requestShowingActivityIndicatorPublisher: AnyPublisher<Bool, Never> {
        requestShowingActivityIndicatorSubject.eraseToAnyPublisher()
    }

    var requestShowingAlertPublisher: AnyPublisher<String, Never> {
        requestShowingAlertSubject.eraseToAnyPublisher()
    }

    var requestShowingToastPublisher: AnyPublisher<ToastModel, Never> {
        requestShowingToastSubject.eraseToAnyPublisher()
    }

    var requestShowingLayerViewPublisher: AnyPublisher<Bool, Never> {
        requestShowingLayerViewSubject.eraseToAnyPublisher()
    }

    var refreshCanvasPublisher: AnyPublisher<CanvasModel, Never> {
        refreshCanvasSubject.eraseToAnyPublisher()
    }

    var refreshCanvasWithUndoObjectPublisher: AnyPublisher<TextureLayerUndoObject, Never> {
        refreshCanvasWithUndoObjectSubject.eraseToAnyPublisher()
    }

    var refreshCanUndoPublisher: AnyPublisher<Bool, Never> {
        refreshCanUndoSubject.eraseToAnyPublisher()
    }
    var refreshCanRedoPublisher: AnyPublisher<Bool, Never> {
        refreshCanRedoSubject.eraseToAnyPublisher()
    }

    private var grayscaleCurve: CanvasGrayscaleTexturePointIterator?

    private let fingerScreenTouchManager = FingerScreenTouchManager()

    private let pencilScreenTouchManager = PencilScreenTouchManager()

    private let inputDevice = InputDevice()

    private let screenTouchGesture = ScreenTouchGesture()

    private var localRepository: LocalRepository?

    /// A texture that combines the texture of the currently selected `TextureLayer` and `DrawingTexture`
    private let currentTexture = CanvasCurrentTexture()

    /// A protocol for managing current drawing texture
    private (set) var drawingTexture: DrawingTextureProtocol?
    /// A drawing texture with a brush
    private let brushDrawingTexture = BrushDrawingTexture()
    /// A drawing texture with an eraser
    private let eraserDrawingTexture = EraserDrawingTexture()

    private let pauseDisplayLinkSubject = CurrentValueSubject<Bool, Never>(true)

    private let requestShowingActivityIndicatorSubject = CurrentValueSubject<Bool, Never>(false)

    private let requestShowingAlertSubject = PassthroughSubject<String, Never>()

    private let requestShowingToastSubject = PassthroughSubject<ToastModel, Never>()

    private let requestShowingLayerViewSubject = CurrentValueSubject<Bool, Never>(false)

    private let refreshCanvasSubject = PassthroughSubject<CanvasModel, Never>()

    private let refreshCanvasWithUndoObjectSubject = PassthroughSubject<TextureLayerUndoObject, Never>()

    private let refreshCanUndoSubject = PassthroughSubject<Bool, Never>()

    private let refreshCanRedoSubject = PassthroughSubject<Bool, Never>()

    private var cancellables = Set<AnyCancellable>()

    init(
        localRepository: LocalRepository = DocumentsLocalRepository()
    ) {
        self.localRepository = localRepository

        textureLayerUndoManager.addTextureLayersToUndoStackPublisher
            .sink { [weak self] in
                guard let `self` else { return }
                self.textureLayerUndoManager.addUndoObject(
                    undoObject: .init(
                        index: self.textureLayers.index,
                        layers: self.textureLayers.layers
                    ),
                    textureLayers: self.textureLayers
                )
                self.textureLayers.updateSelectedTextureAddress()
            }
            .store(in: &cancellables)

        textureLayerUndoManager.refreshCanvasPublisher
            .sink { [weak self] undoObject in
                self?.refreshCanvasWithUndoObjectSubject.send(undoObject)
            }
            .store(in: &cancellables)

        textureLayerUndoManager.canUndoPublisher
            .sink { [weak self] value in
                self?.refreshCanUndoSubject.send(value)
            }
            .store(in: &cancellables)

        textureLayerUndoManager.canRedoPublisher
            .sink { [weak self] value in
                self?.refreshCanRedoSubject.send(value)
            }
            .store(in: &cancellables)

        drawingTool.drawingToolPublisher
            .sink { [weak self] tool in
                guard let `self` else { return }
                switch tool {
                case .brush:
                    self.drawingTexture = self.brushDrawingTexture
                case .eraser:
                    self.drawingTexture = self.eraserDrawingTexture
                }
            }
            .store(in: &cancellables)

        drawingTool.setDrawingTool(.brush)
    }

    func initCanvas(
        textureSize: CGSize,
        renderTarget: MTKRenderTextureProtocol
    ) {
        brushDrawingTexture.initTexture(textureSize)
        eraserDrawingTexture.initTexture(textureSize)

        currentTexture.initTexture(textureSize: textureSize)
        textureLayers.initLayers(textureSize: textureSize)

        renderTarget.initRenderTexture(textureSize: textureSize)

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture!,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }

    func apply(
        model: CanvasModel,
        to renderTarget: MTKRenderTextureProtocol
    ) {
        projectName = model.projectName

        textureLayerUndoManager.clear()

        brushDrawingTexture.initTexture(model.textureSize)
        eraserDrawingTexture.initTexture(model.textureSize)

        currentTexture.initTexture(textureSize: model.textureSize)
        textureLayers.initLayers(
            newLayers: model.layers,
            layerIndex: model.layerIndex,
            textureSize: model.textureSize
        )

        for i in 0 ..< textureLayers.layers.count {
            textureLayers.layers[i].updateThumbnail()
        }

        drawingTool.setBrushDiameter(model.brushDiameter)
        drawingTool.setEraserDiameter(model.eraserDiameter)
        drawingTool.setDrawingTool(.init(rawValue: model.drawingTool))

        renderTarget.initRenderTexture(textureSize: model.textureSize)

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }

    func apply(
        undoObject: TextureLayerUndoObject,
        to renderTarget: MTKRenderTextureProtocol
    ) {
        currentTexture.clearTexture()
        textureLayers.initLayers(
            index: undoObject.index,
            layers: undoObject.layers
        )

        for i in 0 ..< textureLayers.layers.count {
            textureLayers.layers[i].updateThumbnail()
        }

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }

}

extension CanvasViewModel {
    func onViewDidAppear(
        _ drawableTextureSize: CGSize,
        renderTarget: MTKRenderTextureProtocol
    ) {
        // Initialize the canvas here if the renderTexture's texture is nil
        if renderTarget.renderTexture == nil {
            initCanvas(
                textureSize: drawableTextureSize,
                renderTarget: renderTarget
            )
        }

        // Update the display of the Undo and Redo buttons
        textureLayerUndoManager.updateUndoComponents()
    }

    // Manage all finger positions on the screen using a Dictionary,
    // determine the gesture from it,
    // and based on that, either draw a line on the canvas or transform the canvas.
    func onFingerGestureDetected(
        touches: Set<UITouch>,
        with event: UIEvent?,
        view: UIView,
        renderTarget: MTKRenderTextureProtocol
    ) {
        guard inputDevice.update(.finger) != .pencil else { return }

        fingerScreenTouchManager.append(
            event: event,
            in: view
        )

        switch screenTouchGesture.update(
            .init(from: fingerScreenTouchManager.touchArrayDictionary)
        ) {
        case .drawing:
            if !(grayscaleCurve is SmoothCanvasGrayscaleTexturePointIterator) {
                grayscaleCurve = SmoothCanvasGrayscaleTexturePointIterator()
            }
            if fingerScreenTouchManager.currentDictionaryKey == nil {
                fingerScreenTouchManager.currentDictionaryKey = fingerScreenTouchManager.touchArrayDictionary.keys.first
            }
            guard 
                let grayscaleCurve,
                let currentTouchKey = fingerScreenTouchManager.currentDictionaryKey
            else { return }

            let screenTouchPoints = fingerScreenTouchManager.getTouchPoints(for: currentTouchKey)
            let latestScreenTouchPoints = screenTouchPoints.elements(after: fingerScreenTouchManager.latestCanvasTouchPoint) ?? screenTouchPoints
            fingerScreenTouchManager.latestCanvasTouchPoint = latestScreenTouchPoints.last

            let touchPhase = latestScreenTouchPoints.currentTouchPhase

            let grayscaleTexturePoints: [CanvasGrayscaleDotPoint] = latestScreenTouchPoints.map {
                .init(
                    touchPoint: $0.convertToTextureCoordinatesAndApplyMatrix(
                        matrix: canvasTransformer.matrix,
                        frameSize: frameSize,
                        drawableSize: renderTarget.viewDrawable?.texture.size ?? .zero,
                        textureSize: renderTarget.renderTexture?.size ?? .zero
                    ),
                    diameter: CGFloat(drawingTool.diameter)
                )
            }

            grayscaleCurve.appendToIterator(
                points: grayscaleTexturePoints,
                touchPhase: touchPhase
            )

            drawPoints(
                grayscaleTexturePoints: grayscaleCurve.makeCurvePoints(
                    atEnd: touchPhase == .ended
                ),
                drawingTool: drawingTool,
                with: grayscaleCurve,
                touchPhase: touchPhase,
                on: textureLayers,
                with: renderTarget.commandBuffer
            )

            renderTextures(
                textureLayers: textureLayers,
                touchPhase: touchPhase,
                on: renderTarget
            )

        case .transforming:
            transformCanvas(
                fingerScreenTouchManager.touchArrayDictionary,
                on: renderTarget
            )

        default:
            break
        }

        fingerScreenTouchManager.removeIfLastElementMatches(phases: [.ended, .cancelled])

        if fingerScreenTouchManager.isEmpty && isAllFingersReleasedFromScreen(touches: touches, with: event) {
            initDrawingParameters()
        }
    }

    // Draw lines on the canvas using the data sent from an Apple Pencil.
    func onPencilGestureDetected(
        touches: Set<UITouch>,
        with event: UIEvent?,
        view: UIView,
        renderTarget: MTKRenderTextureProtocol
    ) {
        if inputDevice.status == .finger {
            cancelFingerInput(renderTarget)
        }
        let _ = inputDevice.update(.pencil)

        pencilScreenTouchManager.append(
            event: event,
            in: view
        )
        if !(grayscaleCurve is DefaultCanvasGrayscaleTexturePointIterator) {
            grayscaleCurve = DefaultCanvasGrayscaleTexturePointIterator()
        }
        guard let grayscaleCurve else { return }

        let screenTouchPoints = pencilScreenTouchManager.touchArray
        let latestScreenTouchPoints = screenTouchPoints.elements(after: pencilScreenTouchManager.latestCanvasTouchPoint) ?? screenTouchPoints
        pencilScreenTouchManager.latestCanvasTouchPoint = screenTouchPoints.last

        let touchPhase = latestScreenTouchPoints.currentTouchPhase

        let grayscaleTexturePoints: [CanvasGrayscaleDotPoint] = latestScreenTouchPoints.map {
            .init(
                touchPoint: $0.convertToTextureCoordinatesAndApplyMatrix(
                    matrix: canvasTransformer.matrix,
                    frameSize: frameSize,
                    drawableSize: renderTarget.viewDrawable?.texture.size ?? .zero,
                    textureSize: renderTarget.renderTexture?.size ?? .zero
                ),
                diameter: CGFloat(drawingTool.diameter)
            )
        }

        grayscaleCurve.appendToIterator(
            points: grayscaleTexturePoints,
            touchPhase: touchPhase
        )

        drawPoints(
            grayscaleTexturePoints: grayscaleCurve.makeCurvePoints(
                atEnd: touchPhase == .ended
            ),
            drawingTool: drawingTool,
            with: grayscaleCurve,
            touchPhase: touchPhase,
            on: textureLayers,
            with: renderTarget.commandBuffer
        )

        renderTextures(
            textureLayers: textureLayers,
            touchPhase: touchPhase,
            on: renderTarget
        )

        if [UITouch.Phase.ended, UITouch.Phase.cancelled].contains(pencilScreenTouchManager.touchArray.currentTouchPhase) {
            initDrawingParameters()
        }
    }

}

extension CanvasViewModel {

    private func initDrawingParameters() {
        inputDevice.reset()
        screenTouchGesture.reset()

        canvasTransformer.reset()

        fingerScreenTouchManager.reset()
        pencilScreenTouchManager.reset()
        grayscaleCurve = nil
    }

    private func cancelFingerInput(_ renderTarget: MTKRenderTextureProtocol) {
        fingerScreenTouchManager.reset()
        canvasTransformer.reset()
        drawingTexture?.clearDrawingTexture()
        renderTarget.clearCommandBuffer()
        renderTarget.setNeedsDisplay()
    }

}

extension CanvasViewModel {

    private func drawPoints(
        grayscaleTexturePoints: [CanvasGrayscaleDotPoint],
        drawingTool: CanvasDrawingToolStatus,
        with grayscaleCurve: CanvasGrayscaleTexturePointIterator?,
        touchPhase: UITouch.Phase,
        on textureLayers: TextureLayers,
        with commandBuffer: MTLCommandBuffer
    ) {
        if let drawingTexture = drawingTexture as? EraserDrawingTexture,
           let selectedTexture = textureLayers.selectedLayer?.texture {
            drawingTexture.drawPointsOnEraserDrawingTexture(
                points: grayscaleTexturePoints,
                alpha: drawingTool.eraserAlpha,
                srcTexture: selectedTexture,
                commandBuffer
            )
        } else if let drawingTexture = drawingTexture as? BrushDrawingTexture {
            drawingTexture.drawPointsOnBrushDrawingTexture(
                points: grayscaleTexturePoints,
                color: drawingTool.brushColor,
                alpha: drawingTool.brushColor.alpha,
                commandBuffer
            )
        }

        // Combine `selectedLayer.texture` and `drawingTexture`, then render them onto currentTexture
        drawingTexture?.drawDrawingTexture(
            includingSelectedTexture: textureLayers.selectedLayer?.texture,
            on: currentTexture.currentTexture,
            with: commandBuffer
        )

        if touchPhase == .ended {
            // Add `textureLayer` to the undo stack 
            // when the drawing is ended and before `DrawingTexture` is merged with `selectedLayer.texture`
            textureLayerUndoManager.addCurrentLayersToUndoStack()

            // Draw `drawingTexture` onto `selectedLayer.texture`
            drawingTexture?.mergeDrawingTexture(
                into: textureLayers.selectedLayer?.texture,
                commandBuffer
            )
        }
    }

    private func renderTextures(
        textureLayers: TextureLayers,
        touchPhase: UITouch.Phase,
        on renderTarget: MTKRenderTextureProtocol
    ) {
        // Render the textures of `textureLayers` onto `renderTarget.renderTexture` with the backgroundColor
        textureLayers.drawAllTextures(
            currentTexture: currentTexture,
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        pauseDisplayLinkLoop(
            [UITouch.Phase.ended, UITouch.Phase.cancelled].contains(touchPhase),
            renderTarget: renderTarget
        )

        if [UITouch.Phase.ended, UITouch.Phase.cancelled].contains(touchPhase) {
            initDrawingParameters()
        }

        if requestShowingLayerViewSubject.value && touchPhase == .ended {
            // Makes a thumbnail with a slight delay to allow processing after the Metal command buffer has completed
            updateCurrentLayerThumbnailWithDelay(nanosecondsDuration: 1000_000)
        }
    }

    private func transformCanvas(
        _ touchPointsDictionary: [TouchHashValue: [CanvasTouchPoint]],
        on renderTarget: MTKRenderTextureProtocol
    ) {
        if canvasTransformer.isCurrentKeysNil {
            canvasTransformer.initTransforming(touchPointsDictionary)
        }

        canvasTransformer.transformCanvas(
            screenCenter: .init(
                x: frameSize.width * 0.5,
                y: frameSize.height * 0.5
            ),
            touchPointsDictionary
        )

        if touchPointsDictionary.containsPhases([.ended]) {
            canvasTransformer.finishTransforming()
        }

        pauseDisplayLinkLoop(
            touchPointsDictionary.containsPhases(
                [.ended, .cancelled]
            ),
            renderTarget: renderTarget
        )
    }

}

extension CanvasViewModel {

    /// Start or stop the display link loop.
    private func pauseDisplayLinkLoop(_ pause: Bool, renderTarget: MTKRenderTextureProtocol) {
        if pause {
            if pauseDisplayLinkSubject.value == false {
                // Pause the display link after updating the display.
                renderTarget.setNeedsDisplay()
                pauseDisplayLinkSubject.send(true)
            }

        } else {
            if pauseDisplayLinkSubject.value == true {
                pauseDisplayLinkSubject.send(false)
            }
        }
    }

    private func isAllFingersReleasedFromScreen(
        touches: Set<UITouch>,
        with event: UIEvent?
    ) -> Bool {
        touches.count == event?.allTouches?.count &&
        touches.contains { $0.phase == .ended || $0.phase == .cancelled }
    }

    private func updateCurrentLayerThumbnailWithDelay(nanosecondsDuration: UInt64) {
        Task {
            try await Task.sleep(nanoseconds: nanosecondsDuration)

            DispatchQueue.main.async { [weak self] in
                guard let `self` else { return }
                self.textureLayers.updateThumbnail(index: self.textureLayers.index)
            }
        }
    }

}

extension CanvasViewModel {
    // MARK: Toolbar
    func didTapUndoButton() {
        textureLayerUndoManager.undo()
    }
    func didTapRedoButton() {
        textureLayerUndoManager.redo()
    }

    func didTapLayerButton() {
        textureLayers.updateThumbnail(index: textureLayers.index)
        requestShowingLayerViewSubject.send(!requestShowingLayerViewSubject.value)
    }

    func didTapResetTransformButton(renderTarget: MTKRenderTextureProtocol) {
        canvasTransformer.setMatrix(.identity)
        renderTarget.setNeedsDisplay()
    }

    func didTapNewCanvasButton(renderTarget: MTKRenderTextureProtocol) {
        guard 
            let renderTexture = renderTarget.renderTexture
        else { return }

        projectName = Calendar.currentDate

        canvasTransformer.setMatrix(.identity)

        brushDrawingTexture.initTexture(renderTexture.size)
        eraserDrawingTexture.initTexture(renderTexture.size)

        currentTexture.initTexture(textureSize: renderTexture.size)
        textureLayers.initLayers(textureSize: renderTexture.size)

        textureLayerUndoManager.clear()

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }

    func didTapLoadButton(filePath: String) {
        loadFile(from: filePath)
    }
    func didTapSaveButton(renderTarget: MTKRenderTextureProtocol) {
        saveFile(renderTexture: renderTarget.renderTexture!)
    }

    // MARK: Layers
    func didTapLayer(
        layer: TextureLayer,
        renderTarget: MTKRenderTextureProtocol
    ) {
        guard let index = textureLayers.getIndex(layer: layer) else { return }
        textureLayers.index = index

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }
    func didTapAddLayerButton(
        renderTarget: MTKRenderTextureProtocol
    ) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let renderTexture = renderTarget.renderTexture
        else { return }

        textureLayerUndoManager.addCurrentLayersToUndoStack()

        let layer: TextureLayer = .init(
            texture: MTKTextureUtils.makeBlankTexture(
                device,
                renderTexture.size
            ),
            title: TimeStampFormatter.current(template: "MMM dd HH mm ss")
        )
        textureLayers.addLayer(layer)

        // Makes a thumbnail
        if let index = textureLayers.getIndex(layer: layer) {
            textureLayers.updateThumbnail(index: index)
        }

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }
    func didTapRemoveLayerButton(
        renderTarget: MTKRenderTextureProtocol
    ) {
        guard
            textureLayers.layers.count > 1,
            let layer = textureLayers.selectedLayer
        else { return }

        textureLayerUndoManager.addCurrentLayersToUndoStack()

        textureLayers.removeLayer(layer)

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }
    func didTapLayerVisibility(
        layer: TextureLayer,
        isVisible: Bool,
        renderTarget: MTKRenderTextureProtocol
    ) {
        guard 
            let index = textureLayers.getIndex(layer: layer)
        else { return }

        textureLayers.updateLayer(
            index: index,
            isVisible: isVisible
        )

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }
    func didChangeLayerAlpha(
        layer: TextureLayer,
        value: Int,
        renderTarget: MTKRenderTextureProtocol
    ) {
        guard
            let index = textureLayers.getIndex(layer: layer)
        else { return }

        textureLayers.updateLayer(
            index: index,
            alpha: value
        )

        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }
    func didEditLayerTitle(
        layer: TextureLayer,
        title: String
    ) {
        guard
            let index = textureLayers.getIndex(layer: layer)
        else { return }

        textureLayers.updateLayer(
            index: index,
            title: title
        )
    }
    func didMoveLayers(
        layer: TextureLayer,
        source: IndexSet,
        destination: Int,
        renderTarget: MTKRenderTextureProtocol
    ) {
        textureLayerUndoManager.addCurrentLayersToUndoStack()

        textureLayers.moveLayer(
            fromOffsets: source,
            toOffset: destination
        )

        textureLayers.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        textureLayers.drawAllTextures(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }

}

extension CanvasViewModel {

    private func loadFile(from filePath: String) {
        localRepository?.loadDataFromDocuments(
            sourceURL: URL.documents.appendingPathComponent(filePath)
        )
        .handleEvents(
            receiveSubscription: { [weak self] _ in self?.requestShowingActivityIndicatorSubject.send(true) },
            receiveCompletion: { [weak self] _ in self?.requestShowingActivityIndicatorSubject.send(false) }
        )
        .sink(receiveCompletion: { [weak self] completion in
            switch completion {
            case .finished: self?.requestShowingToastSubject.send(.init(title: "Success", systemName: "hand.thumbsup.fill"))
            case .failure(let error): self?.requestShowingAlertSubject.send(error.localizedDescription) }
        }, receiveValue: { [weak self] response in
            self?.refreshCanvasSubject.send(response)
        })
        .store(in: &cancellables)
    }

    private func saveFile(renderTexture: MTLTexture) {
        localRepository?.saveDataToDocuments(
            renderTexture: renderTexture,
            textureLayers: textureLayers,
            drawingTool: drawingTool,
            to: URL.documents.appendingPathComponent(
                CanvasModel.getZipFileName(projectName: projectName)
            )
        )
        .handleEvents(
            receiveSubscription: { [weak self] _ in self?.requestShowingActivityIndicatorSubject.send(true) },
            receiveCompletion: { [weak self] _ in self?.requestShowingActivityIndicatorSubject.send(false) }
        )
        .sink(receiveCompletion: { [weak self] completion in
            switch completion {
            case .finished: self?.requestShowingToastSubject.send(.init(title: "Success", systemName: "hand.thumbsup.fill"))
            case .failure(let error): self?.requestShowingAlertSubject.send(error.localizedDescription) }
        }, receiveValue: {})
        .store(in: &cancellables)
    }

}
