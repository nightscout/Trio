import SwiftUI

/// Lists the releases preceding this build, each pushing its own notes.
struct ReleaseNotesListView: View {
    let releases: [ReleaseNotes]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                ForEach(releases) { release in
                    NavigationLink(destination: ReleaseNotesDetailView(notes: release)) {
                        HStack {
                            Text(release.name)
                                .foregroundColor(.primary)

                            Spacer()

                            Text(release.publishedDateString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }.listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Previous Versions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
