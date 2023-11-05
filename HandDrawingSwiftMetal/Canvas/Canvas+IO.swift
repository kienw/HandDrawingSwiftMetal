//
//  Canvas+IO.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/11/04.
//

import Foundation

extension Canvas {
    var fileNamePath: String {
        projectName + "." + Canvas.zipSuffix
    }
    static var zipSuffix: String {
        "zip"
    }
    static var thumbnailPath: String {
        "thumbnail.png"
    }
    static var jsonFilePath: String {
        "data"
    }
    func write(to folderUrl: URL) throws {

        let textureName = UUID().uuidString
        let textureDataUrl = folderUrl.appendingPathComponent(textureName)

        // Texture
        autoreleasepool {
            try? Data(layers.currentTexture.bytes).write(to: textureDataUrl)
        }

        // Thumbnail
        let imageURL = folderUrl.appendingPathComponent(Canvas.thumbnailPath)
        try outputImage?.resize(height: 512, scale: 1.0)?.pngData()?.write(to: imageURL)

        // Data
        let codableData = CanvasCodableData(textureSize: textureSize,
                                            textureName: textureName,
                                            drawingTool: drawingTool.rawValue,
                                            brushDiameter: brushDiameter,
                                            eraserDiameter: eraserDiameter)

        if let jsonData = try? JSONEncoder().encode(codableData) {
            let jsonUrl = folderUrl.appendingPathComponent(Canvas.jsonFilePath)
            try? String(data: jsonData, encoding: .utf8)?.write(to: jsonUrl, atomically: true, encoding: .utf8)
        }
    }
    func load(from codableData: CanvasCodableData, projectName: String, folderURL: URL) {
        self.projectName = projectName

        if let textureName = codableData.textureName,
           let textureSize = codableData.textureSize {

            let textureUrl = folderURL.appendingPathComponent(textureName)
            let textureData: Data? = try? Data(contentsOf: textureUrl)

            if let texture = device?.makeTexture(textureSize, textureData?.encodedHexadecimals) {
                layers.setTexture(texture)
            }
        }

        if let drawingTool = codableData.drawingTool {
            self.drawingTool = .init(rawValue: drawingTool) ?? .brush
        }

        if let diameter = codableData.brushDiameter {
            self.brushDiameter = diameter
        }
        if let diameter = codableData.eraserDiameter {
            self.eraserDiameter = diameter
        }
        
        clearUndo()

        refreshRootTexture()
        setNeedsDisplay()
    }
    
    func setTexture(textureSize: CGSize, folderUrl: URL, textureName: String) {

        let textureUrl = folderUrl.appendingPathComponent(textureName)
        let textureData: Data? = try? Data(contentsOf: textureUrl)

        if let texture = device?.makeTexture(textureSize, textureData?.encodedHexadecimals) {
            layers.setTexture(texture)
        }
    }
}
