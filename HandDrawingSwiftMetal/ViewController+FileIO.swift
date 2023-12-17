//
//  ViewController+FileIO.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/11/04.
//

import Foundation

extension ViewController {
    func saveCanvas(zipFileName: String, tmpFolderURL: URL) {
        createTemporaryFolder(tmpFolderURL: tmpFolderURL) { [weak self] folderURL in
            guard let currentTexture = self?.canvasView.currentTexture  else { return }

            try self?.canvasViewModel.saveCanvasAsZipFile(texture: currentTexture,
                                                          textureName: UUID().uuidString,
                                                          folderURL: folderURL,
                                                          zipFileName: zipFileName)
        }
    }
    func loadCanvas(zipFilePath: String, tmpFolderURL: URL) {
        createTemporaryFolder(tmpFolderURL: tmpFolderURL) { [weak self] folderURL in

            let data = try self?.canvasViewModel.loadCanvasData(into: folderURL,
                                                                zipFilePath: zipFilePath)

            try self?.canvasViewModel.applyCanvasDataToCanvas(data,
                                                              folderURL: folderURL,
                                                              zipFilePath: zipFilePath)
            self?.initAllComponents()
            self?.canvasView.refreshCanvas()
        }
    }
    private func createTemporaryFolder(tmpFolderURL: URL,
                                       _ tasks: @escaping (URL) throws -> Void) {
        Task {
            let activityIndicatorView = ActivityIndicatorView(frame: view.frame)
            defer {
                try? FileManager.default.removeItem(atPath: tmpFolderURL.path)
                activityIndicatorView.removeFromSuperview()
            }
            view.addSubview(activityIndicatorView)

            do {
                // Clean up the temporary folder when done
                try FileManager.createNewDirectory(url: tmpFolderURL)

                try tasks(tmpFolderURL)

                try await Task.sleep(nanoseconds: UInt64(1_000_000_000))

                view.addSubview(Toast(text: "Success", systemName: "hand.thumbsup.fill"))

            } catch {
                view.addSubview(Toast(text: error.localizedDescription))
            }
        }
    }
}
