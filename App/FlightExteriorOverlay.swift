import SwiftUI

struct FlightExteriorOverlay: View {
    let altitudeFeet: Double
    let speedKnots: Double

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            readout(altitudeFeet, unit: "ft", label: "高度", spokenUnit: "英尺")
            Rectangle()
                .fill(.white.opacity(0.32))
                .frame(width: 1, height: 20)
                .accessibilityHidden(true)
            readout(speedKnots, unit: "kt", label: "地速", spokenUnit: "节")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Color(white: 0.065).opacity(0.86), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulator-exterior-telemetry")
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func readout(_ value: Double, unit: String, label: String, spokenUnit: String) -> some View {
        let number = (value.isFinite ? value : 0).formatted(.number.precision(.fractionLength(0)))
        return VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AtlasTypography.font(.caption2, weight: .semibold))
                .foregroundStyle(.white.opacity(0.80))
            Text("\(number) \(unit)")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(number) \(spokenUnit)")
    }
}
