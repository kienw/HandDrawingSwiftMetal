//
//  DrawingToolModel.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2024/03/09.
//

import UIKit
import Combine

final class DrawingToolModel {

    var drawingTool: DrawingToolType {
        drawingToolSubject.value
    }
    var diameter: Float {
        diameterSubject.value
    }
    var backgroundColor: UIColor {
        backgroundColorSubject.value
    }

    var drawingToolPublisher: AnyPublisher<DrawingToolType, Never> {
        drawingToolSubject.eraseToAnyPublisher()
    }
    var diameterPublisher: AnyPublisher<Float, Never> {
        diameterSubject.eraseToAnyPublisher()
    }
    var backgroundColorPublisher: AnyPublisher<UIColor, Never> {
        backgroundColorSubject.eraseToAnyPublisher()
    }

    private let drawingToolSubject = CurrentValueSubject<DrawingToolType, Never>(.brush)

    private let diameterSubject = CurrentValueSubject<Float, Never>(1.0)

    private let backgroundColorSubject = CurrentValueSubject<UIColor, Never>(.white)

    let matrixSubject = CurrentValueSubject<CGAffineTransform, Never>(.identity)

    let textureSizeSubject = CurrentValueSubject<CGSize, Never>(.zero)

    let pauseDisplayLinkSubject = CurrentValueSubject<Bool, Never>(false)

    let commitCommandToMergeAllLayersToRootTextureSubject = PassthroughSubject<Void, Never>()

    let commitCommandsInCommandBuffer = PassthroughSubject<Void, Never>()

    /// An instance for managing texture layers
    let layerManager = LayerManager()

    var frameSize: CGSize = .zero {
        didSet {
            layerManager.frameSize = frameSize
        }
    }

    private (set) var brushColor: UIColor
    private (set) var eraserAlpha: Int
    private (set) var brushDiameter: Int
    private (set) var eraserDiameter: Int

    private let device: MTLDevice = MTLCreateSystemDefaultDevice()!

    private var blurSize: Float = BlurredDotSize.initBlurSize

    private var cancellables = Set<AnyCancellable>()

    init(
        brushDiameter: Int = 8,
        eraserDiameter: Int = 44,
        brushColor: UIColor = .black.withAlphaComponent(0.75),
        eraserAlpha: Int = 150,
        backgroundColor: UIColor = .white
    ) {
        self.brushDiameter = brushDiameter
        self.eraserDiameter = eraserDiameter
        self.brushColor = brushColor
        self.eraserAlpha = eraserAlpha

        setBackgroundColor(backgroundColor)

        drawingToolSubject
            .sink { [weak self] tool in
                self?.layerManager.setDrawingLayer(tool)
            }
            .store(in: &cancellables)

        layerManager.commitCommandToMergeAllLayersToRootTextureSubject
            .sink { [weak self] in
                guard let `self` else { return }
                commitCommandToMergeAllLayersToRootTextureSubject.send()
            }
            .store(in: &cancellables)
    }

}

extension DrawingToolModel {

    func setDrawingTool(_ tool: DrawingToolType) {

        switch tool {
        case .brush:
            diameterSubject.send(DrawingToolBrush.diameterFloatValue(brushDiameter))
        case .eraser:
            diameterSubject.send(DrawingToolEraser.diameterFloatValue(eraserDiameter))
        }

        drawingToolSubject.send(tool)
    }

    func setBrushColor(_ color: UIColor) {
        brushColor = color
    }
    func setEraserAlpha(_ alpha: Int) {
        eraserAlpha = alpha
    }

}

extension DrawingToolModel {

    var brushDotSize: BlurredDotSize {
        BlurredDotSize(diameter: brushDiameter, blurSize: blurSize)
    }
    var eraserDotSize: BlurredDotSize {
        BlurredDotSize(diameter: eraserDiameter, blurSize: blurSize)
    }

    @objc func handleDiameterSlider(_ sender: UISlider) {
        if drawingToolSubject.value == .brush {
            setBrushDiameter(sender.value)

        } else if drawingToolSubject.value == .eraser {
            setEraserDiameter(sender.value)
        }
    }

    func setBrushDiameter(_ value: Float) {
        brushDiameter = DrawingToolBrush.diameterIntValue(value)
    }
    func setEraserDiameter(_ value: Float) {
        eraserDiameter = DrawingToolEraser.diameterIntValue(value)
    }

    func setBrushDiameter(_ value: Int) {
        brushDiameter = value
    }
    func setEraserDiameter(_ value: Int) {
        eraserDiameter = value
    }

}

extension DrawingToolModel {

    func setBackgroundColor(_ color: UIColor) {
        self.backgroundColorSubject.send(color)
    }
    
}

extension DrawingToolModel {

    func initLayers(textureSize: CGSize) {
        layerManager.reset(textureSize)
    }

    func addCommandToMergeAllLayers(
        onto dstTexture: MTLTexture?,
        to commandBuffer: MTLCommandBuffer
    ) {
        guard   let dstTexture,
                let selectedTexture = layerManager.selectedTexture,
                let selectedTextures = layerManager.drawingLayer?.getDrawingTextures(selectedTexture)
        else { return }

        layerManager.addCommandToMergeAllLayers(
            selectedTextures: selectedTextures.compactMap { $0 },
            selectedAlpha: layerManager.selectedLayerAlpha,
            backgroundColor: backgroundColorSubject.value.rgb,
            onto: dstTexture,
            to: commandBuffer
        )
    }

}
