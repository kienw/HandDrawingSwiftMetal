//
//  CanvasViewModel.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/12/10.
//

import MetalKit
import Combine

protocol CanvasViewModelDelegate {

    var commandBuffer: MTLCommandBuffer { get }
    var rootTexture: MTLTexture { get }
    func callSetNeedsDisplayOnCanvasView()

}

class CanvasViewModel {

    var delegate: CanvasViewModelDelegate?

    let drawing = Drawing()
    let lineDrawing = LineDrawing()
    let smoothLineDrawing = SmoothLineDrawing()

    let drawingTool = DrawingToolModel()

    var pauseDisplayLinkPublisher: AnyPublisher<Bool, Never> {
        pauseDisplayLinkSubject.eraseToAnyPublisher()
    }

    var frameSize: CGSize = .zero {
        didSet {
            drawing.frameSize = frameSize
        }
    }

    /// A name of the file to be saved
    var projectName: String = Calendar.currentDate

    var zipFileNameName: String {
        projectName + "." + URL.zipSuffix
    }

    var undoObject: UndoObject {
        return UndoObject(index: drawing.layerManager.index,
                          layers: drawing.layerManager.layers)
    }

    var addUndoObjectToUndoStackPublisher: AnyPublisher<Void, Never> {
        addUndoObjectToUndoStackSubject.eraseToAnyPublisher()
    }

    var clearUndoPublisher: AnyPublisher<Void, Never> {
        clearUndoSubject.eraseToAnyPublisher()
    }

    private let touchManager = TouchManager()
    private let actionManager = ActionManager()

    let device: MTLDevice = MTLCreateSystemDefaultDevice()!

    /// A protocol for managing transformations
    private let transforming = Transforming()

    /// A protocol for managing file input and output
    private (set) var fileIO: FileIO!

    private let pauseDisplayLinkSubject = CurrentValueSubject<Bool, Never>(true)

    private let addUndoObjectToUndoStackSubject = PassthroughSubject<Void, Never>()

    private let clearUndoSubject = PassthroughSubject<Void, Never>()

    private var cancellables = Set<AnyCancellable>()

    init(fileIO: FileIO = FileIOImpl()) {
        self.fileIO = fileIO

        drawing.addUndoObjectToUndoStackPublisher
            .subscribe(addUndoObjectToUndoStackSubject)
            .store(in: &cancellables)

        drawing.pauseDisplayLinkPublisher
            .sink { [weak self] in
                self?.pauseDisplayLinkLoop($0)
            }
            .store(in: &cancellables)

        drawing.layerManager.addUndoObjectToUndoStackPublisher
            .subscribe(addUndoObjectToUndoStackSubject)
            .store(in: &cancellables)

        drawing.mergeAllLayersToRootTexturePublisher
            .sink { [weak self] in
                self?.mergeAllLayersToRootTexture()
            }
            .store(in: &cancellables)

        drawing.callSetNeedsDisplayOnCanvasViewPublisher
            .sink { [weak self] in
                self?.delegate?.callSetNeedsDisplayOnCanvasView()
            }
            .store(in: &cancellables)

        drawingTool.drawingToolPublisher
            .sink { [weak self] tool in
                self?.drawing.layerManager.setDrawingLayer(tool)
            }
            .store(in: &cancellables)

        drawingTool.setDrawingTool(.brush)
    }

}

extension CanvasViewModel {

    func handleFingerInputGesture(_ touches: Set<UITouch>, with event: UIEvent?, on view: UIView) {
        defer {
            touchManager.removeIfTouchPhaseIsEnded(touches: touches)
            if touchManager.touchPointsDictionary.isEmpty {
                actionManager.reset()
            }
        }
        touchManager.appendFingerTouches(event, in: view)

        let newState: ActionState = .init(from: touchManager.touchPointsDictionary)

        switch actionManager.updateState(newState) {
        case .drawing:
            if let lineSegment: LineSegment = drawing.makeLineSegment(
                touchManager,
                with: smoothLineDrawing,
                drawingTool: drawingTool
            ) {
                drawing.drawSegmentOnTexture(
                    lineSegment,
                    drawingTool,
                    delegate?.rootTexture,
                    delegate?.commandBuffer
                )
            }

        case .transforming:
            drawing.transformCanvas(
                touchPointData: touchManager,
                transforming: transforming,
                drawingTool: drawingTool
            )

        default:
            break
        }
    }

    func handlePencilInputGesture(_ touches: Set<UITouch>, with event: UIEvent?, on view: UIView) {
        defer {
            touchManager.removeIfTouchPhaseIsEnded(touches: touches)
            if touchManager.touchPointsDictionary.isEmpty {
                actionManager.reset()
            }
        }
        touchManager.appendPencilTouches(event, in: view)
    }

}
extension CanvasViewModel {

    func didTapResetTransformButton() {
        resetMatrix()
        drawing.callSetNeedsDisplayOnCanvasView()
    }

    func didTapNewCanvasButton() {

        clearUndoSubject.send()

        projectName = Calendar.currentDate

        resetMatrix()

        drawing.initLayers(textureSize: drawing.textureSize)

        drawing.mergeAllLayersToRootTexture()
        drawing.callSetNeedsDisplayOnCanvasView()
    }

}

extension CanvasViewModel {

    func initTextureSizeIfSizeIsZero(frameSize: CGSize, drawableSize: CGSize) {
        if drawing.textureSize == .zero &&
           frameSize.isSameRatio(drawableSize) {
            drawing.setTextureSize(drawableSize)
        }
    }

    func resetMatrix() {
        transforming.updateMatrix(.identity)
        drawing.setMatrix(.identity)
    }

    func mergeAllLayersToRootTexture() {
        guard
            let rootTexture = delegate?.rootTexture,
            let commandBuffer = delegate?.commandBuffer
        else { return }

        drawing.addMergeAllLayersCommands(
            backgroundColor: drawingTool.backgroundColor,
            onto: rootTexture,
            to: commandBuffer)
    }

    /// Start or stop the display link loop.
    func pauseDisplayLinkLoop(_ pause: Bool) {
        if pause {
            if pauseDisplayLinkSubject.value == false {
                // Pause the display link after updating the display.
                delegate?.callSetNeedsDisplayOnCanvasView()
                pauseDisplayLinkSubject.send(true)
            }

        } else {
            if pauseDisplayLinkSubject.value == true {
                pauseDisplayLinkSubject.send(false)
            }
        }
    }

}
