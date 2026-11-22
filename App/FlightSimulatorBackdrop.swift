import SwiftUI

#if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
import MapKit
import UIKit
#endif

@MainActor
struct FlightSimulatorBackdrop: View {
    enum Viewpoint: Equatable {
        case cockpit, exterior
    }

    let pose: FlightGroundPose
    let heightMeters: Double
    let viewpoint: Viewpoint
    let onReady: () -> Void

    var body: some View {
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        if DistributionPolicy.mapsAvailable, CLLocationCoordinate2DIsValid(pose.coordinate), pose.heading.isFinite {
            FlightSimulatorTerrainMap(pose: pose, heightMeters: heightMeters, viewpoint: viewpoint, onReady: onReady)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("simulator-terrain-map")
        }
        #else
        Color.clear
        #endif
    }
}

#if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
@MainActor
private struct FlightSimulatorTerrainMap: UIViewRepresentable {
    let pose: FlightGroundPose
    let heightMeters: Double
    let viewpoint: FlightSimulatorBackdrop.Viewpoint
    let onReady: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.delegate = context.coordinator
        context.coordinator.update(frame, on: map, reduceMotion: reduceMotion, onReady: onReady)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(frame, on: map, reduceMotion: reduceMotion, onReady: onReady)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.stop()
        map.delegate = nil
    }

    private var frame: TerrainFrame {
        TerrainFrame(pose: pose, heightMeters: heightMeters, viewpoint: viewpoint)
    }

    fileprivate struct TerrainFrame {
        let center: CLLocationCoordinate2D
        let heading: Double
        let distance: Double
        let pitch: CGFloat

        init(pose: FlightGroundPose, heightMeters: Double, viewpoint: FlightSimulatorBackdrop.Viewpoint) {
            let height = heightMeters.isFinite ? min(13_500, max(0, heightMeters)) : 0
            let high = min(1, height / 2_000)
            let isCockpit = viewpoint == .cockpit
            // Keep airport terrain wide enough to stay within the useful detail of the imagery.
            let eyeHeight = isCockpit ? max(95, height + 18) : max(180, height + 65)
            let tilt = isCockpit ? 67 - 4 * high : 53 - 8 * high
            let radians = tilt * .pi / 180
            // Match the rightward route bearing shown by the chase-camera aircraft model.
            let offset: Double = isCockpit ? 0 : -41
            let course = (pose.heading + offset).truncatingRemainder(dividingBy: 360)
            heading = course < 0 ? course + 360 : course
            pitch = CGFloat(tilt)
            distance = eyeHeight / cos(radians)
            // Place the forward camera's eye over the moving aircraft instead of behind the map target.
            center = isCockpit
                ? FlightSimulatorArc.offset(from: pose.coordinate, course: heading, meters: eyeHeight * tan(radians))
                : pose.coordinate
        }

        var camera: MKMapCamera {
            MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: pitch, heading: heading)
        }

        func movedMeters(from earlier: Self) -> Double {
            FlightSimulatorArc.angularDistance(center, earlier.center) * 6_371_000
        }

        func differs(from earlier: Self) -> Bool {
            let headingDifference = abs(heading - earlier.heading)
            return movedMeters(from: earlier) > max(2, earlier.distance * 0.008)
                || abs(distance - earlier.distance) > max(1.5, earlier.distance * 0.018)
                || min(headingDifference, 360 - headingDifference) > 0.75
                || abs(pitch - earlier.pitch) > 0.5
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let clock = ContinuousClock()
        private var lastFrame: TerrainFrame?
        private var lastApplied: ContinuousClock.Instant?
        private var pendingFrame: TerrainFrame?
        private var updateTask: Task<Void, Never>?
        private var onReady: (() -> Void)?
        private var ready = false
        private var reduceMotion = false

        fileprivate func update(_ next: TerrainFrame, on map: MKMapView, reduceMotion: Bool,
                                onReady: @escaping () -> Void) {
            self.onReady = onReady
            self.reduceMotion = reduceMotion
            pendingFrame = next
            guard updateTask == nil, lastFrame.map({ next.differs(from: $0) }) ?? true else { return }

            // Give the initial scene a chance to render before following a running simulation.
            let interval: Duration = !ready ? .milliseconds(720) : .milliseconds(reduceMotion ? 500 : 280)
            let deadline = lastApplied.map { $0 + interval } ?? clock.now
            guard deadline > clock.now else {
                applyFrame(on: map)
                return
            }

            updateTask = Task { @MainActor [weak self, weak map] in
                guard let self else { return }
                try? await clock.sleep(until: deadline)
                guard !Task.isCancelled, let map else { return }
                updateTask = nil
                applyFrame(on: map)
            }
        }

        func stop() {
            updateTask?.cancel()
            updateTask = nil
            pendingFrame = nil
            onReady = nil
        }

        private func applyFrame(on map: MKMapView) {
            guard let next = pendingFrame else { return }
            pendingFrame = nil
            let previous = lastFrame
            guard previous.map({ next.differs(from: $0) }) ?? true else { return }
            let nearby = previous.map {
                next.movedMeters(from: $0) < max(800, $0.distance * 1.2)
                    && abs(next.center.longitude - $0.center.longitude) < 180
            } ?? false
            lastFrame = next
            lastApplied = clock.now
            map.setCamera(next.camera, animated: ready && !reduceMotion && nearby)
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard fullyRendered, !ready, lastFrame != nil, mapView.window != nil, !mapView.bounds.isEmpty else { return }
            ready = true
            Task { @MainActor [weak self] in self?.onReady?() }
        }
    }
}
#endif
