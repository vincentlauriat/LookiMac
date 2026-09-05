import SwiftUI
import AppKit
import LookiKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var keyField = ""
    @State private var status: String?
    @State private var statusIsError = false
    @State private var testing = false

    var body: some View {
        Form {
            Section("Compte Looki") {
                SecureField("Clé API (lk-…)", text: $keyField)
                    .textContentType(.password)
                HStack {
                    Button("Enregistrer la clé") { save() }
                        .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Tester la connexion") { Task { await test() } }
                        .disabled(model.needsSetup || testing)
                    Button("Importer depuis un fichier…") { importFile() }
                    Spacer()
                    Button("Oublier la clé", role: .destructive) { forget() }
                        .disabled(model.needsSetup)
                }
                if let status {
                    Label(status, systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(statusIsError ? .red : .green)
                }
                Text("La clé est conservée dans le trousseau macOS, jamais dans un fichier de l'app. Crée-la sur web.looki.ai › API Keys.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Archive") {
                LabeledContent("Dossier") {
                    Text(model.archiveRoot?.path(percentEncoded: false) ?? "Non défini").lineLimit(1).truncationMode(.middle)
                }
                Button("Choisir le dossier…") { chooseFolder() }
                Text("Chaque jour archivé produit un sous-dossier AAAA/MM/JJ avec les médias, journal.md et moments.json.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Cache") {
                LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: model.cacheSize, countStyle: .file))
                Button("Vider le cache") { Task { try? await model.purgeCache() } }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .task { await model.refreshCacheSize() }
        .onAppear { keyField = model.apiKey ?? "" }
    }

    private func save() {
        do {
            try model.setAPIKey(keyField)
            show("Clé enregistrée.", error: false)
        } catch {
            show("Trousseau : \(error.localizedDescription)", error: true)
        }
    }

    private func forget() {
        do { try model.clearAPIKey(); keyField = ""; show("Clé supprimée.", error: false) }
        catch { show("Trousseau : \(error.localizedDescription)", error: true) }
    }

    private func test() async {
        testing = true; defer { testing = false }
        switch await model.testConnection() {
        case .success(let user):
            let name = user.displayName.isEmpty ? "compte vérifié" : user.displayName
            show("Connexion OK — \(name) (\(user.tz ?? "fuseau inconnu")).", error: false)
        case .failure(let e):
            show(e.userMessage, error: true)
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = URL(filePath: NSHomeDirectory()).appending(path: ".config/looki")
        panel.showsHiddenFiles = true
        panel.message = "Sélectionne credentials.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let creds = try CredentialsFileImporter.read(url)
            keyField = creds.apiKey
            save()
        } catch {
            show("Fichier illisible : \(error.localizedDescription)", error: true)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.chooseArchiveFolder(url) }
        catch { show("Impossible de mémoriser ce dossier : \(error.localizedDescription)", error: true) }
    }

    private func show(_ text: String, error: Bool) { status = text; statusIsError = error }
}
