import SwiftUI

extension Color {
    /// Init from a 6-digit hex string (e.g. GTFS route_color). Falls back to
    /// gray when empty/malformed.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The circular subway "bullet" (e.g. a green ⓒ), colored by the line.
struct SubwayLineBadge: View {
    let name: String
    let colorHex: String
    var size: CGFloat = 34

    var body: some View {
        Text(name)
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: colorHex)))
            .accessibilityLabel("\(name) train")
    }
}

#Preview {
    HStack {
        SubwayLineBadge(name: "C", colorHex: "0039A6")
        SubwayLineBadge(name: "E", colorHex: "0039A6")
        SubwayLineBadge(name: "1", colorHex: "EE352E")
        SubwayLineBadge(name: "7", colorHex: "B933AD")
    }
    .padding()
}
