import PhotosUI
import SwiftUI

struct SendReportView: View {
    static let maxScreenshots = ReportLimits.maxImages

    let submitter: ReportSubmitting
    let logExport: LogExport?
    let context: ProblemReport.Context

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var draft = ReportDraft.load()
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var screenshots: [ReportScreenshot] = []
    @State private var screenshotTask: Task<Void, Never>?
    @State private var isLoadingScreenshots = false
    @State private var isSending = false
    @State private var sendProgress = 0.0
    @State private var sentID: String?
    @State private var sendError: ReportSubmitError?
    @State private var showError = false

    var body: some View {
        Form {
            if isSending {
                Section {
                    ProgressView(value: sendProgress) {
                        Text("Sending Report")
                    }
                }
                .listRowBackground(Color.chart)
            }

            Section(
                content: {
                    TextField("Title (optional)", text: $draft.title)
                    ZStack(alignment: .topLeading) {
                        if draft.description.isEmpty {
                            Text("Describe what happened and what you expected")
                                .foregroundColor(Color(.placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $draft.description)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .accessibilityLabel(Text("Describe what happened and what you expected"))
                    }
                },
                footer: {
                    Text("\(draft.description.unicodeScalars.count) of \(ReportDraft.maxDescriptionLength) characters")
                }
            )
            .listRowBackground(Color.chart)

            screenshotsSection

            Section(
                content: {
                    Toggle("Attach My Logs", isOn: $draft.attachLogs)
                },
                header: { Text("Your Logs") },
                footer: {
                    Text("Includes glucose, insulin, carbs and your settings. Passwords and serial numbers are removed.")
                }
            )
            .listRowBackground(Color.chart)

            contactSection

            Section(
                content: {
                    LabeledContent("App Version", value: appVersion)
                    LabeledContent("Build", value: "\(context.branch) \(context.commit)")
                    LabeledContent("iPhone Model", value: context.deviceModel)
                    LabeledContent("iOS Version", value: context.osVersion)
                    LabeledContent("Pump", value: context.pumpModel ?? String(localized: "None"))
                    LabeledContent("CGM", value: context.cgmModel ?? String(localized: "None"))
                },
                header: { Text("Also Sent") },
                footer: {
                    Text(
                        "Reports go only to the Trio team and are deleted after 90 days. You can delete a report yourself at any time."
                    )
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Send to the Trio Team")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSending)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                        .accessibilityLabel(Text("Sending"))
                } else {
                    Button("Submit", action: send)
                        .disabled(!draft.canSubmit || isLoadingScreenshots)
                }
            }
        }
        .disabled(isSending)
        .onChange(of: draft) { _, draft in
            draft.save()
        }
        .onChange(of: draft.title) { _, title in
            if title.unicodeScalars.count > ReportDraft.maxTitleLength {
                draft.title = title.prefix(scalars: ReportDraft.maxTitleLength)
            }
        }
        .onChange(of: draft.description) { _, description in
            if description.unicodeScalars.count > ReportDraft.maxDescriptionLength {
                draft.description = description.prefix(scalars: ReportDraft.maxDescriptionLength)
            }
        }
        .onChange(of: photoSelection) { _, items in
            loadScreenshots(items)
        }
        .alert(
            "Report Sent",
            isPresented: Binding(get: { sentID != nil }, set: { if !$0 { sentID = nil } }),
            presenting: sentID
        ) { id in
            Button("Copy ID") {
                UIPasteboard.general.string = id
                dismiss()
            }
            Button("Done", role: .cancel) { dismiss() }
        } message: { id in
            Text("Thank you. Your report ID is \(id). Mention it if you ask about this on Discord or Facebook.")
        }
        .alert("Couldn't Send Report", isPresented: $showError, presenting: sendError) { error in
            if error.canRetry {
                Button("Try Again", action: send)
            }
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private var screenshotsSection: some View {
        Section(
            content: {
                if !screenshots.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, screenshot in
                                Image(uiImage: screenshot.image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityLabel(Text("Screenshot \(index + 1)"))
                            }
                        }
                    }
                }
                PhotosPicker(selection: $photoSelection, maxSelectionCount: Self.maxScreenshots, matching: .images) {
                    HStack {
                        Text(screenshots.isEmpty ? "Add Screenshots" : "Change Screenshots")
                        if isLoadingScreenshots {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            },
            header: { Text("Screenshots") },
            footer: { Text("Up to \(Self.maxScreenshots) screenshots or photos.") }
        )
        .listRowBackground(Color.chart)
    }

    private var contactSection: some View {
        Section(
            content: {
                Toggle("Stay Anonymous", isOn: $draft.isAnonymous)
                if !draft.isAnonymous {
                    TextField("Name", text: $draft.contact.name)
                        .textContentType(.name)
                    TextField("Email", text: $draft.contact.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Discord Name", text: $draft.contact.discord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("GitHub Username", text: $draft.contact.github)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            },
            header: { Text("Contact") },
            footer: {
                if draft.isAnonymous {
                    Text("The report won't include your name or contact details.")
                } else {
                    Text("Fill in any of these so the team can follow up with you.")
                }
            }
        )
        .listRowBackground(Color.chart)
    }

    private var appVersion: String {
        let version = context.devVersion == ProblemReport.Context.unknown ? context.appVersion : context.devVersion
        return "\(version) (\(context.buildNumber))"
    }

    private func loadScreenshots(_ items: [PhotosPickerItem]) {
        screenshotTask?.cancel()
        isLoadingScreenshots = !items.isEmpty
        screenshotTask = Task { @MainActor in
            var loaded: [ReportScreenshot] = []
            for (index, item) in items.enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let screenshot = await Task.detached(priority: .userInitiated) {
                    ReportScreenshot(data: data, index: index + 1)
                }.value
                if let screenshot { loaded.append(screenshot) }
            }
            guard !Task.isCancelled else { return }
            screenshots = loaded
            isLoadingScreenshots = false
        }
    }

    private func send() {
        guard draft.canSubmit, !isSending else { return }
        isSending = true
        sendProgress = 0
        let draft = draft
        let screenshots = screenshots.map(\.attachment)
        Task { @MainActor in
            do {
                var attachments = screenshots
                if draft.attachLogs {
                    attachments.append(try await logsAttachment())
                }
                sentID = try await submitter.send(draft.report(context: context, attachments: attachments)) { progress in
                    Task { @MainActor in sendProgress = progress }
                }
            } catch {
                warning(.ui, "Sending a problem report failed", error: error)
                sendError = error as? ReportSubmitError ?? .network(error.localizedDescription)
                showError = true
            }
            isSending = false
        }
    }

    private func logsAttachment() async throws -> ProblemReport.Attachment {
        guard let logExport else { throw ReportSubmitError.logsUnavailable }
        do {
            let file = try await logExport.makeFile(.all, days: 3)
            let data = try await Task.detached(priority: .userInitiated) {
                defer { LogExport.discard(file) }
                return try Data(contentsOf: file)
            }.value
            return ProblemReport.Attachment(filename: "logs.zip", contentType: "application/zip", data: data)
        } catch {
            warning(.ui, "Preparing logs for a problem report failed", error: error)
            throw ReportSubmitError.logsUnavailable
        }
    }
}
