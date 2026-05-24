import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var vm = SettingsViewModel()
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Feed") {
                    Toggle("Hide low priority", isOn: $vm.hideLowPriority)
                        .onChange(of: vm.hideLowPriority) { _, _ in vm.save() }
                }
                Section("Ranking") {
                    Text("Careers emails (interviews, rejections, applications) are scored automatically and appear under the Careers filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label("Interview → Critical", systemImage: "person.crop.circle.badge.clock")
                    Label("Rejection / offer → High–Critical", systemImage: "briefcase")
                    Label("Newsletters → Low", systemImage: "newspaper")
                }
                Section("History") {
                    Stepper("Keep \(vm.retentionDays) days", value: $vm.retentionDays, in: 7...365)
                        .onChange(of: vm.retentionDays) { _, _ in
                            vm.save()
                            vm.prune(context: context)
                        }
                }
                Section {
                    Button("Delete all data", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete everything?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { vm.deleteAll(context: context) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes all messages and signs out of Gmail.")
            }
        }
    }
}
