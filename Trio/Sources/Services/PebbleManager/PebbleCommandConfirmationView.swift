import SwiftUI

struct PebbleCommandConfirmationView: View {
    @ObservedObject var commandManager: PebbleCommandManager

    var body: some View {
        List {
            if commandManager.pendingCommands.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        Text("No pending commands")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else {
                ForEach(commandManager.pendingCommands) { command in
                    Section {
                        commandRow(command)
                    }
                }
            }
        }
        .navigationTitle("Pebble Requests")
    }

    @ViewBuilder
    private func commandRow(_ command: PebbleCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: command.type == .bolus ? "syringe" : "fork.knife")
                    .foregroundColor(command.type == .bolus ? .blue : .orange)
                Text(command.type == .bolus ? "Bolus Request" : "Carb Entry Request")
                    .font(.headline)
            }

            if let units = command.bolusUnits {
                Text(String(format: "%.2f U", units))
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            if let grams = command.carbGrams {
                Text(String(format: "%.0f g carbs", grams))
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Text("Requested \(command.createdAt, style: .relative) ago")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Reject") {
                    commandManager.rejectCommand(command.id)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.red)
                .cornerRadius(8)

                Spacer()

                Button("Confirm") {
                    commandManager.confirmCommand(command.id)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.green)
                .cornerRadius(8)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}
