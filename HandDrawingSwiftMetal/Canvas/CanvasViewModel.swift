//
//  CanvasViewModel.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/12/10.
//

import MetalKit
import Combine

class CanvasViewModel {

    let parameters = DrawingParameters()

    var frameSize: CGSize = .zero {
        didSet {
            parameters.frameSize = frameSize
        }
    }

    /// A name of the file to be saved
    var projectName: String = Calendar.currentDate

    var zipFileNameName: String {
        projectName + "." + URL.zipSuffix
    }

    var undoObject: UndoObject {
        return UndoObject(index: parameters.layerManager.index,
                          layers: parameters.layerManager.layers)
    }

    var addUndoObjectToUndoStackPublisher: AnyPublisher<Void, Never> {
        addUndoObjectToUndoStackSubject.eraseToAnyPublisher()
    }

    var clearUndoPublisher: AnyPublisher<Void, Never> {
        clearUndoSubject.eraseToAnyPublisher()
    }

    let device: MTLDevice = MTLCreateSystemDefaultDevice()!

    /// A protocol for managing transformations
    private let transforming = Transforming()

    /// A protocol for managing file input and output
    private (set) var fileIO: FileIO!


    private let addUndoObjectToUndoStackSubject = PassthroughSubject<Void, Never>()

    private let clearUndoSubject = PassthroughSubject<Void, Never>()

    private var displayLink: CADisplayLink?

    private var cancellables = Set<AnyCancellable>()

    init(fileIO: FileIO = FileIOImpl()) {
        self.fileIO = fileIO

        parameters.layerManager.addUndoObjectToUndoStackPublisher
            .subscribe(addUndoObjectToUndoStackSubject)
            .store(in: &cancellables)

        parameters.pauseDisplayLinkSubject
            .sink { [weak self] pause in
                self?.pauseDisplayLinkLoop(pause)
            }
            .store(in: &cancellables)

        parameters.setDrawingTool(.brush)

        // Configure the display link for rendering.
        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplayLink(_:)))
        displayLink?.add(to: .current, forMode: .common)
        displayLink?.isPaused = true
    }

}

extension CanvasViewModel {

    func didTapResetTransformButton() {
        resetMatrix()
        parameters.commitCommandsInCommandBuffer.send()
    }

    func didTapNewCanvasButton() {

        clearUndoSubject.send()

        projectName = Calendar.currentDate

        resetMatrix()

        parameters.initLayers(textureSize: parameters.textureSizeSubject.value)

        parameters.commitCommandToMergeAllLayersToRootTextureSubject.send()
    }

}

extension CanvasViewModel {

    func initTextureSizeIfSizeIsZero(frameSize: CGSize, drawableSize: CGSize) {
        if parameters.textureSizeSubject.value == .zero &&
           frameSize.isSameRatio(drawableSize) {
            parameters.textureSizeSubject.send(drawableSize)
        }
    }

    func resetMatrix() {
        transforming.setStoredMatrix(.identity)
        parameters.matrixSubject.send(.identity)
    }

    func getMatrix(transformationData: TransformationData, touchPhase: UITouch.Phase) -> CGAffineTransform? {
        transforming.getMatrix(transformationData: transformationData,
                               frameCenterPoint: Calc.getCenter(frameSize),
                               touchPhase: touchPhase)
    }

    func setMatrix(_ matrix: CGAffineTransform) {
        transforming.setStoredMatrix(matrix)
    }

}

extension CanvasViewModel {

    @objc private func updateDisplayLink(_ displayLink: CADisplayLink) {
        parameters.commitCommandsInCommandBuffer.send()
    }

    /// Start or stop the display link loop based on the 'play' parameter.
    private func pauseDisplayLinkLoop(_ pause: Bool) {
        if pause {
            if displayLink?.isPaused == false {
                // Pause the display link after updating the display.
                parameters.commitCommandsInCommandBuffer.send()
                displayLink?.isPaused = true
            }

        } else {
            if displayLink?.isPaused == true {
                displayLink?.isPaused = false
            }
        }
    }

}
