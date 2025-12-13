import SwiftUI
import Swinject

extension TherapyProfileList {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            List {
                if let activeProfile = state.activeProfile {
                    activeProfileSection(activeProfile)
                }

                profilesSection

                if state.canCreateProfile {
                    addProfileSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Therapy Profiles")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if state.canCreateProfile {
                        Button(action: state.createNewProfile) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .alert("Delete Profile", isPresented: $state.showDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    state.profileToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    state.deleteProfile()
                }
            } message: {
                if let error = state.deleteError {
                    Text(error)
                } else if let profile = state.profileToDelete {
                    Text("Are you sure you want to delete '\(profile.name)'? This cannot be undone.")
                }
            }
            .onAppear {
                configureView()
            }
        }

        @ViewBuilder
        private func activeProfileSection(_ profile: TherapyProfile) -> some View {
            Section {
                ProfileSwitchInfoBanner(
                    profileName: profile.name,
                    isOverride: state.isManualOverrideActive
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if state.isManualOverrideActive {
                    Button(action: state.clearOverride) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Revert to Scheduled Profile")
                        }
                    }
                }
            } header: {
                Text("Current Status")
            }
        }

        @ViewBuilder
        private var profilesSection: some View {
            Section {
                ForEach(state.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isActive: state.activeProfile?.id == profile.id,
                        daysDescription: state.daysDescription(for: profile),
                        onTap: { state.editProfile(profile) },
                        onActivate: { state.activateProfile(profile) },
                        onOverride: { state.activateProfileAsOverride(profile) },
                        onDuplicate: { state.duplicateProfile(profile) },
                        onDelete: state.canDeleteProfile(profile) ? { state.confirmDelete(profile) } : nil
                    )
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Tap a profile to edit. Each day of the week can only be assigned to one profile.")
            }
        }

        @ViewBuilder
        private var addProfileSection: some View {
            Section {
                Button(action: state.createNewProfile) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Add New Profile")
                    }
                }
            } footer: {
                Text("\(state.profiles.count) of \(TherapyProfile.maxProfiles) profiles used")
            }
        }
    }
}

// MARK: - Profile Row

private struct ProfileRow: View {
    let profile: TherapyProfile
    let isActive: Bool
    let daysDescription: String
    let onTap: () -> Void
    let onActivate: () -> Void
    let onOverride: () -> Void
    let onDuplicate: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if profile.isDefault {
                            Text("Default")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }

                    Text(daysDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if !isActive {
                Button(action: onActivate) {
                    Label("Activate", systemImage: "checkmark.circle")
                }

                Button(action: onOverride) {
                    Label("Override for Today", systemImage: "clock.badge.exclamationmark")
                }

                Divider()
            }

            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            if let deleteAction = onDelete {
                Divider()

                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let deleteAction = onDelete {
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isActive {
                Button(action: onActivate) {
                    Label("Activate", systemImage: "checkmark.circle")
                }
                .tint(.green)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct TherapyProfileListRootView_Previews: PreviewProvider {
        static var previews: some View {
            NavigationView {
                Text("Preview requires resolver setup")
            }
        }
    }
#endif
