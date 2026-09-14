import SwiftUI

extension History.RootView {
    func requestDelete(_ target: History.DeletionTarget) {
        deletionTarget = target
    }

    @ViewBuilder func historyConfirmations(_ content: some View) -> some View {
        let target = deletionTarget

        content
            .glassActionSheet(
                Text(target?.title(units: state.units) ?? ""),
                message: target?.message(units: state.units).map { Text($0) },
                isPresented: Binding(
                    get: { deletionTarget != nil },
                    set: { if !$0 { deletionTarget = nil } }
                ),
                actions: [
                    GlassSheetAction("Delete", role: .destructive) {
                        switch target {
                        case let .glucose(glucose):
                            state.invokeGlucoseDeletionTask(glucose.objectID)
                        case let .insulin(pumpEvent):
                            state.invokeInsulinDeletionTask(pumpEvent.objectID)
                        case let .carbs(carbEntry):
                            state.invokeCarbDeletionTask(
                                carbEntry.objectID,
                                isFpuOrComplexMeal: carbEntry.isFPU || carbEntry.fat > 0 || carbEntry.protein > 0
                            )
                        case .none:
                            break
                        }
                    }
                ]
            )
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
    }
}
