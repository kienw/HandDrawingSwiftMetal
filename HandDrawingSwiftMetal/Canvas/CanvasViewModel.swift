//
//  CanvasViewModel.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/12/10.
//

import Foundation

class CanvasViewModel {

    /// Manage drawing
    private (set) var drawing: DrawingProtocol?

    /// Drawing with a brush
    var drawingBrush = DrawingBrush()

    /// Drawing with an eraser
    var drawingEraser = DrawingEraser()

    /// Manage transformations
    var transforming: TransformingProtocol = Transforming()

    func setFrameSize(_ size: CGSize) {
        drawingBrush.frameSize = size
        drawingEraser.frameSize = size
    }
    func initTextures(_ size: CGSize) {
        drawingBrush.initTextures(size)
        drawingEraser.initTextures(size)
    }
    func setCurrentDrawing(_ type: DrawingToolType) {
        switch type {
        case .brush:
            self.drawing = self.drawingBrush
        case .eraser:
            self.drawing = self.drawingEraser
        }
    }
}

// Transforming
extension CanvasViewModel {
    func getMatrix(transformationData: TransformationData,
                   frameCenterPoint: CGPoint,
                   touchState: TouchState) -> CGAffineTransform? {
        transforming.getMatrix(transformationData: transformationData,
                               frameCenterPoint: frameCenterPoint,
                               touchState: touchState)
    }
    func setStoredMatrix(_ matrix: CGAffineTransform) {
        transforming.storedMatrix = matrix
    }
}
