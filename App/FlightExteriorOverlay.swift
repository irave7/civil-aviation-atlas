import SwiftUI

struct FlightExteriorOverlay: View {
    let altitudeFeet: Double
    let speedKnots: Double

    var body: some View {
        HStack(spacing: 10) {
            readout(altitudeFeet, unit: "ft", label: "高度", spokenUnit: "英尺", symbol: "arrow.up")
            readout(speedKnots, unit: "kt", label: "地速", spokenUnit: "节", symbol: "speedometer")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.76), in: .rect(cornerRadius: 11))
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulator-exterior-telemetry")
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func readout(_ value: Double, unit: String, label: String, spokenUnit: String, symbol: String) -> some View {
        let number = (value.isFinite ? value : 0).formatted(.number.precision(.fractionLength(0)))
        return Label("\(number) \(unit)", systemImage: symbol)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .accessibilityLabel("\(label) \(number) \(spokenUnit)")
    }
}
