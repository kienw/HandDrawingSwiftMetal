//
//  LayerListView.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/12/31.
//

import SwiftUI

struct LayerListView: View {
    @ObservedObject var layerManager: LayerManager

    var didTapLayer: (LayerEntity) -> Void
    var didTapVisibility: (LayerEntity, Bool) -> Void
    var didMove: (LayerEntity, IndexSet, Int) -> Void

    var body: some View {
        List {
            ForEach(Array(layerManager.layers.reversed()), id: \.id) { layer in
                layerRow(
                    layer: layer,
                    selected: layerManager.selectedLayer == layer,
                    didTapRow: { targetLayer in
                        didTapLayer(targetLayer)
                    },
                    didTapVisibleButton: { targetLayer in
                        didTapVisibility(targetLayer, !targetLayer.isVisible)
                    }
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .onMove(perform: { source, destination in
                guard let targetLayer = layerManager.selectedLayer else { return }
                didMove(targetLayer, source, destination)
            })
            .listRowSeparator(.hidden)
        }
        .listStyle(PlainListStyle())
    }

}

extension LayerListView {
    func layerRow(
        layer: LayerEntity,
        selected: Bool,
        didTapRow: @escaping ((LayerEntity) -> Void),
        didTapVisibleButton: @escaping ((LayerEntity) -> Void)
    ) -> some View {
        ZStack {
            Color(backgroundColor(selected))

            HStack {
                Spacer()
                    .frame(width: 8)

                if let image = layer.thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .scaledToFit()
                        .background(Color.white)
                        .cornerRadius(4)
                        .overlay(
                            Rectangle()
                                .stroke(.gray.opacity(0.5), lineWidth: 1.0)
                        )
                }

                Text(layer.title)
                    .font(.subheadline)
                    .foregroundColor(Color(textColor(selected)))

                Spacer()
                
                Text("A: \(layer.alpha)")
                    .font(.caption2)
                    .foregroundColor(Color(uiColor: .gray))

                Image(systemName: layer.isVisible ? "eye" : "eye.slash.fill")
                    .frame(width: 32, height: 32)
                    .foregroundColor(Color(iconColor(layer: layer, selected)))
                    .onTapGesture {
                        didTapVisibleButton(layer)
                    }

                Spacer()
                    .frame(width: 8)
            }
        }
        .onTapGesture {
            didTapRow(layer)
        }
    }
}

// Colors
extension LayerListView {
    private func backgroundColor(_ selected: Bool) -> UIColor {
        if selected {
            return UIColor(named: "component") ?? .clear
        } else {
            return UIColor(named: "reversalComponent") ?? .clear
        }
    }
    private func textColor(_ selected: Bool) -> UIColor {
        if selected {
            return UIColor(named: "reversalComponent") ?? .clear
        } else {
            return UIColor(named: "component") ?? .clear
        }
    }
    private func iconColor(layer: LayerEntity, _ selected: Bool) -> UIColor {
        if selected {
            if layer.isVisible {
                return .white
            } else {
                return .lightGray
            }
        } else {
            if layer.isVisible {
                return .black
            } else {
                return .darkGray
            }
        }
    }
}

#Preview {

    LayerListView(
        layerManager: LayerManager(),
        didTapLayer: { layer in
            print("Tap layer")
        },
        didTapVisibility: { layer, isVisible in
            print("Tap visibility")
        },
        didMove: { layer, source, destination in
            print("Moved")
        }
    )

}
