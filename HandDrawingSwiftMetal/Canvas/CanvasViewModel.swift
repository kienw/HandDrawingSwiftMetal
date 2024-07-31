//
//  CanvasViewModel.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/12/10.
//

import MetalKit
import Combine

enum CanvasViewModelError: Error {
    case failedToApplyData
}

final class CanvasViewModel {

    var renderTarget: MTKRenderTextureProtocol?

    let canvasTransformer = CanvasTransformer()

    let layerManager = ImageLayerManager()

    let layerUndoManager = LayerUndoManager()

    let drawingTool = DrawingToolModel()

    let inputManager = InputManager()

    var frameSize: CGSize = .zero {
        didSet {

            layerManager.frameSize = frameSize

            canvasTransformer.screenCenter = .init(
                x: frameSize.width * 0.5,
                y: frameSize.height * 0.5
            )
        }
    }

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

    var requestShowingLayerViewPublisher: AnyPublisher<Void, Never> {
        requestShowingLayerViewSubject.eraseToAnyPublisher()
    }

    var refreshCanvasPublisher: AnyPublisher<CanvasModel, Never> {
        refreshCanvasSubject.eraseToAnyPublisher()
    }

    var refreshCanvasWithUndoObjectPublisher: AnyPublisher<UndoObject, Never> {
        refreshCanvasWithUndoObjectSubject.eraseToAnyPublisher()
    }

    private var grayscaleCurve: GrayscaleCurve?

    private let fingerScreenTouchManager = FingerScreenTouchManager()

    private let pencilScreenTouchManager = PencilScreenTouchManager()

    private let actionManager = ActionManager()

    private var localRepository: LocalRepository?

    private let pauseDisplayLinkSubject = CurrentValueSubject<Bool, Never>(true)

    private let requestShowingActivityIndicatorSubject = CurrentValueSubject<Bool, Never>(false)

    private let requestShowingAlertSubject = PassthroughSubject<String, Never>()

    private let requestShowingToastSubject = PassthroughSubject<ToastModel, Never>()

    private let requestShowingLayerViewSubject = PassthroughSubject<Void, Never>()

    private let refreshCanvasSubject = PassthroughSubject<CanvasModel, Never>()

    private let refreshCanvasWithUndoObjectSubject = PassthroughSubject<UndoObject, Never>()

    private var cancellables = Set<AnyCancellable>()

    init(
        localRepository: LocalRepository = DocumentsLocalRepository()
    ) {
        self.localRepository = localRepository

        layerUndoManager.addCurrentLayersToUndoStackPublisher
            .sink { [weak self] in
                guard let `self` else { return }
                self.layerUndoManager.addUndoObject(
                    undoObject: .init(
                        index: self.layerManager.index,
                        layers: self.layerManager.layers
                    ),
                    layerManager: self.layerManager
                )
                self.layerManager.updateTextureAddress()
            }
            .store(in: &cancellables)

        layerUndoManager.refreshCanvasPublisher
            .sink { [weak self] undoObject in
                self?.refreshCanvasWithUndoObjectSubject.send(undoObject)
            }
            .store(in: &cancellables)

        layerUndoManager.updateUndoComponents()

        drawingTool.drawingToolPublisher
            .sink { [weak self] tool in
                self?.layerManager.setDrawingLayer(tool)
            }
            .store(in: &cancellables)

        drawingTool.setDrawingTool(.brush)
    }

    func initCanvas(
        textureSize: CGSize,
        renderTarget: MTKRenderTextureProtocol
    ) {
        layerManager.initialize(textureSize: textureSize)

        renderTarget.initRenderTexture(textureSize: textureSize)

        layerManager.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        layerManager.mergeAllLayers(
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

        layerUndoManager.clear()

        layerManager.initialize(
            textureSize: model.textureSize,
            layerIndex: model.layerIndex,
            layers: model.layers
        )

        drawingTool.setBrushDiameter(model.brushDiameter)
        drawingTool.setEraserDiameter(model.eraserDiameter)
        drawingTool.setDrawingTool(.init(rawValue: model.drawingTool))

        renderTarget.initRenderTexture(textureSize: model.textureSize)

        layerManager.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        refreshCanvasWithMergingDrawingLayers()
    }

    func apply(
        undoObject: UndoObject,
        to renderTarget: MTKRenderTextureProtocol
    ) {
        layerManager.initLayers(
            index: undoObject.index,
            layers: undoObject.layers
        )

        layerManager.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        refreshCanvasWithMergingDrawingLayers()
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
    }

    func onFingerGestureDetected(
        touches: Set<UITouch>,
        with event: UIEvent?,
        view: UIView,
        renderTarget: MTKRenderTextureProtocol
    ) {
        defer {
            fingerScreenTouchManager.removeIfLastElementMatches(phases: [.ended, .cancelled])
            if fingerScreenTouchManager.isEmpty && isAllFingersReleasedFromScreen(touches: touches, with: event) {
                initDrawingParameters()
            }
        }

        guard
            inputManager.updateCurrentInput(.finger) != .pencil
        else { return }

        fingerScreenTouchManager.append(
            event: event,
            in: view
        )

        switch actionManager.updateState(
            .init(from: fingerScreenTouchManager.touchArrayDictionary)
        ) {
        case .drawing:
            if !(grayscaleCurve is SmoothGrayscaleCurve) {
                grayscaleCurve = SmoothGrayscaleCurve()
            }
            if grayscaleCurve?.currentDictionaryKey == nil {
                grayscaleCurve?.currentDictionaryKey = fingerScreenTouchManager.touchArrayDictionary.keys.first
            }
            guard let key = grayscaleCurve?.currentDictionaryKey else { return }

            let touchPoints = fingerScreenTouchManager.getTouchPoints(for: key)
            let latestTouchPoints = touchPoints.elements(after: grayscaleCurve?.startAfterPoint) ?? touchPoints
            grayscaleCurve?.startAfterPoint = touchPoints.last

            // Add the `layers` of `LayerManager` to the undo stack just before the drawing is completed
            if touchPoints.last?.phase == .ended {
                layerUndoManager.addCurrentLayersToUndoStack()
            }

            drawCurveOnCanvas(
                latestTouchPoints,
                with: grayscaleCurve,
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
    }

    func onPencilGestureDetected(
        touches: Set<UITouch>,
        with event: UIEvent?,
        view: UIView,
        renderTarget: MTKRenderTextureProtocol
    ) {
        defer {
            pencilScreenTouchManager.removeIfLastElementMatches(phases: [.ended, .cancelled])
            if pencilScreenTouchManager.isEmpty && isAllFingersReleasedFromScreen(touches: touches, with: event) {
                initDrawingParameters()
            }
        }

        if inputManager.state == .finger {
            cancelFingerInput(renderTarget)
        }
        inputManager.updateCurrentInput(.pencil)

        pencilScreenTouchManager.append(
            event: event,
            in: view
        )
        if !(grayscaleCurve is DefaultGrayscaleCurve) {
            grayscaleCurve = DefaultGrayscaleCurve()
        }

        let touchPoints = pencilScreenTouchManager.touchArray
        let latestTouchPoints = touchPoints.elements(after: grayscaleCurve?.startAfterPoint) ?? touchPoints
        grayscaleCurve?.startAfterPoint = touchPoints.last

        // Add the `layers` of `LayerManager` to the undo stack just before the drawing is completed
        if touchPoints.last?.phase == .ended {
            layerUndoManager.addCurrentLayersToUndoStack()
        }

        drawCurveOnCanvas(
            latestTouchPoints,
            with: grayscaleCurve,
            on: renderTarget
        )
    }

}

extension CanvasViewModel {

    private func initDrawingParameters() {
        inputManager.clear()
        actionManager.clear()

        canvasTransformer.reset()

        fingerScreenTouchManager.reset()
        pencilScreenTouchManager.reset()
        grayscaleCurve = nil
    }

    private func cancelFingerInput(_ renderTarget: MTKRenderTextureProtocol) {
        fingerScreenTouchManager.reset()
        canvasTransformer.reset()
        layerManager.clearDrawingLayer()
        renderTarget.clearCommandBuffer()
        renderTarget.setNeedsDisplay()
    }

}

extension CanvasViewModel {

    private func drawCurveOnCanvas(
        _ screenTouchPoints: [TouchPoint],
        with grayscaleCurve: GrayscaleCurve?,
        on renderTarget: MTKRenderTextureProtocol
    ) {
        let touchPhase = screenTouchPoints.last?.phase ?? .cancelled

        let grayscaleCurveTexturePoints = makeGrayscaleTextureCurvePoints(
            screenTouchPoints: screenTouchPoints,
            grayscaleCurve: grayscaleCurve,
            renderTarget: renderTarget
        )

        drawCurve(
            grayScaleTextureCurvePoints: grayscaleCurveTexturePoints,
            drawingTool: drawingTool,
            touchPhase: touchPhase,
            on: renderTarget
        )

        if touchPhase == .ended || touchPhase == .cancelled {
            initDrawingParameters()
        }
    }

    private func makeGrayscaleTextureCurvePoints(
        screenTouchPoints: [TouchPoint],
        grayscaleCurve: GrayscaleCurve?,
        renderTarget: MTKRenderTextureProtocol
    ) -> [GrayscaleTexturePoint] {
        let touchPhase = screenTouchPoints.last?.phase ?? .cancelled

        let grayscaleTexturePoints: [GrayscaleTexturePoint] = screenTouchPoints.map {
            .init(
                touchPoint: $0.convertLocationToTextureScaleAndApplyMatrix(
                    matrix: canvasTransformer.matrix,
                    frameSize: frameSize,
                    drawableSize: renderTarget.viewDrawable?.texture.size ?? .zero,
                    textureSize: renderTarget.renderTexture?.size ?? .zero
                ),
                diameter: CGFloat(drawingTool.diameter)
            )
        }

        grayscaleCurve?.appendToIterator(
            points: grayscaleTexturePoints,
            touchPhase: touchPhase
        )

        return grayscaleCurve?.makeCurvePointsFromIterator(
            touchPhase: touchPhase
        ) ?? []
    }

    private func drawCurve(
        grayScaleTextureCurvePoints: [GrayscaleTexturePoint],
        drawingTool: DrawingToolModel,
        touchPhase: UITouch.Phase,
        on renderTarget: MTKRenderTextureProtocol
    ) {
        if let drawingLayer = layerManager.drawingLayer as? DrawingEraserLayer {
            drawingLayer.drawOnEraserDrawingTexture(
                points: grayScaleTextureCurvePoints,
                alpha: drawingTool.eraserAlpha,
                srcTexture: layerManager.selectedTexture!,
                renderTarget.commandBuffer
            )
        } else if let drawingLayer = layerManager.drawingLayer as? DrawingBrushLayer {
            drawingLayer.drawOnBrushDrawingTexture(
                points: grayScaleTextureCurvePoints,
                color: drawingTool.brushColor,
                alpha: drawingTool.brushColor.alpha,
                renderTarget.commandBuffer
            )
        }

        if touchPhase == .ended {
            layerManager.drawingLayer?.mergeDrawingTexture(
                into: layerManager.selectedTexture!,
                renderTarget.commandBuffer
            )
        }

        layerManager.drawAllLayers(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTarget.renderTexture,
            renderTarget.commandBuffer
        )

        pauseDisplayLinkLoop(
            touchPhase == .ended || touchPhase == .cancelled,
            renderTarget: renderTarget
        )
    }

    private func transformCanvas(
        _ touchPointsDictionary: [TouchHashValue: [TouchPoint]],
        on renderTarget: MTKRenderTextureProtocol
    ) {
        if canvasTransformer.isCurrentKeysNil {
            canvasTransformer.initTransforming(touchPointsDictionary)
        }

        canvasTransformer.transformCanvas(touchPointsDictionary)

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

    func refreshCanvasWithMergingAllLayers() {
        guard 
            let renderTarget
        else { return }

        layerManager.updateUnselectedLayers(
            to: renderTarget.commandBuffer
        )
        refreshCanvasWithMergingDrawingLayers()
    }

    func refreshCanvasWithMergingDrawingLayers() {
        guard 
            let renderTarget,
            let renderTexture = renderTarget.renderTexture
        else { return }

        layerManager.mergeAllLayers(
            backgroundColor: drawingTool.backgroundColor,
            onto: renderTexture,
            renderTarget.commandBuffer
        )

        renderTarget.setNeedsDisplay()
    }

    private func isAllFingersReleasedFromScreen(
        touches: Set<UITouch>,
        with event: UIEvent?
    ) -> Bool {
        touches.count == event?.allTouches?.count &&
        touches.contains { $0.phase == .ended || $0.phase == .cancelled }
    }

    /// Start or stop the display link loop.
    private func pauseDisplayLinkLoop(_ pause: Bool) {
        if pause {
            if pauseDisplayLinkSubject.value == false {
                // Pause the display link after updating the display.
                renderTarget?.setNeedsDisplay()
                pauseDisplayLinkSubject.send(true)
            }

        } else {
            if pauseDisplayLinkSubject.value == true {
                pauseDisplayLinkSubject.send(false)
            }
        }
    }

}

extension CanvasViewModel {
    // MARK: Toolbar
    func didTapUndoButton() {
        layerUndoManager.undo()
    }
    func didTapRedoButton() {
        layerUndoManager.redo()
    }

    func didTapLayerButton() {
        Task {
            try? await layerManager.updateCurrentThumbnail()

            DispatchQueue.main.async { [weak self] in
                self?.requestShowingLayerViewSubject.send()
            }
        }
    }

    func didTapResetTransformButton() {
        canvasTransformer.setMatrix(.identity)
        renderTarget?.setNeedsDisplay()
    }

    func didTapNewCanvasButton() {

        projectName = Calendar.currentDate

        canvasTransformer.setMatrix(.identity)
        layerManager.initialize(textureSize: layerManager.textureSize)

        layerUndoManager.clear()

        refreshCanvasWithMergingAllLayers()
    }

    func didTapLoadButton(filePath: String) {
        loadFile(from: filePath)
    }
    func didTapSaveButton(renderTarget: MTKRenderTextureProtocol) {
        saveFile(renderTexture: renderTarget.renderTexture!)
    }

    // MARK: Layers
    func didTapLayer(layer: ImageLayerCellItem) {
        layerManager.updateIndex(layer)
        refreshCanvasWithMergingAllLayers()
    }
    func didTapAddLayerButton() {
        layerUndoManager.addCurrentLayersToUndoStack()

        layerManager.addNewLayer()
        refreshCanvasWithMergingAllLayers()
    }
    func didTapRemoveLayerButton() {
        guard
            layerManager.layers.count > 1,
            let layer = layerManager.selectedLayer
        else { return }

        layerUndoManager.addCurrentLayersToUndoStack()

        layerManager.removeLayer(layer)
        refreshCanvasWithMergingAllLayers()
    }
    func didTapLayerVisibility(layer: ImageLayerCellItem, isVisible: Bool) {
        layerManager.update(layer, isVisible: isVisible)
        refreshCanvasWithMergingAllLayers()
    }
    func didChangeLayerAlpha(layer: ImageLayerCellItem, value: Int) {
        layerManager.update(layer, alpha: value)
        refreshCanvasWithMergingDrawingLayers()
    }
    func didEditLayerTitle(layer: ImageLayerCellItem, title: String) {
        layerManager.updateTitle(layer, title)
    }
    func didMoveLayers(layer: ImageLayerCellItem, source: IndexSet, destination: Int) {
        layerUndoManager.addCurrentLayersToUndoStack()

        layerManager.moveLayer(
            fromOffsets: source,
            toOffset: destination
        )
        refreshCanvasWithMergingAllLayers()
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
            layerManager: layerManager,
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
