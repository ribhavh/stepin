import SwiftUI
import MapKit

/// A text field with live autocomplete suggestions (address or place name) and
/// a clear button. Reports the picked completion so the caller can resolve it to
/// a coordinate.
struct AddressField: View {
    let label: String
    let icon: String
    @Binding var text: String
    var onSelect: (MKLocalSearchCompletion, String) -> Void
    var onEdit: () -> Void

    @State private var completer = AddressCompleter()
    @FocusState private var focused: Bool
    @State private var justPicked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.tint).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                    TextField("Address or place", text: $text)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onChange(of: text) { _, newValue in
                            if justPicked { justPicked = false; return }
                            completer.query = newValue
                            onEdit()
                        }
                }
                if !text.isEmpty {
                    Button {
                        text = ""
                        completer.clear()
                        onEdit()
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(label)")
                }
            }

            if focused && !completer.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(completer.suggestions.prefix(5), id: \.self) { suggestion in
                        Button { pick(suggestion) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.leading, 30)
            }
        }
    }

    private func pick(_ suggestion: MKLocalSearchCompletion) {
        let display = suggestion.subtitle.isEmpty
            ? suggestion.title
            : "\(suggestion.title), \(suggestion.subtitle)"
        justPicked = true       // don't re-trigger the completer from this edit
        text = display
        onSelect(suggestion, display)
        completer.clear()
        focused = false
    }
}
