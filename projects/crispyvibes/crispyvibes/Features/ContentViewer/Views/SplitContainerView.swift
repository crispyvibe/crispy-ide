import SwiftUI

struct SplitContainerView: View {
    let node: SplitPaneNode
    @ObservedObject var store: SplitViewStore
    let paneContent: (UUID) -> AnyView

    var body: some View {
        SplitNodeView(node: node, store: store, paneContent: paneContent)
    }
}

private struct SplitNodeView: View {
    let node: SplitPaneNode
    @ObservedObject var store: SplitViewStore
    let paneContent: (UUID) -> AnyView

    var body: some View {
        switch node {
        case .leaf(let id):
            paneContent(id).id(id)

        case .split(let id, let orientation, let first, let second, _):
            NativeSplitView(
                isVerticalSplit: orientation == .horizontal,
                primaryAtEnd: false,
                primarySize: Binding(
                    get: { store.ratioBinding(for: id) * 1000 },
                    set: { store.setRatio($0 / 1000, for: id) }
                ),
                minPrimary: 100,
                maxPrimary: .greatestFiniteMagnitude,
                minSecondary: 100
            ) {
                AnyView(SplitNodeView(node: first, store: store, paneContent: paneContent))
            } secondary: {
                AnyView(SplitNodeView(node: second, store: store, paneContent: paneContent))
            }
        }
    }
}
