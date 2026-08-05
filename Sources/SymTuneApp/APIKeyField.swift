import SwiftUI
import SymairaTheme
import SymTuneCore

/// A SecureField that stores the entered value in the Keychain on submit.
///
/// The stored account is `<providerID>-api-key` under the standard
/// `com.symaira.symtune` service — the same slot the providers read at
/// construction time. The field is deliberately a local write: nothing here
/// ever reads the value back into `config.toml`.
struct APIKeyField: View {
    let providerID: String
    let label: String
    let placeholder: String

    @State private var value: String
    @State private var saved = false

    init(providerID: String, label: String, placeholder: String) {
        self.providerID = providerID
        self.label = label
        self.placeholder = placeholder
        self._value = State(initialValue: KeychainCredentials.read(
            service: "com.symaira.symtune",
            account: "\(providerID)-api-key"
        ) ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            SecureField(label, text: $value, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if saved {
                Text("saved")
                    .font(.caption2)
                    .foregroundStyle(SymairaTheme.positive)
            } else {
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(SymairaTheme.goldPrimary)
            }
        }
        .padding(.leading, 20)
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            _ = KeychainCredentials.delete(service: "com.symaira.symtune", account: "\(providerID)-api-key")
            value = ""
        } else {
            guard KeychainCredentials.write(
                service: "com.symaira.symtune",
                account: "\(providerID)-api-key",
                value: trimmed
            ) else {
                return
            }
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            saved = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) {
                    saved = false
                }
            }
        }
    }
}
