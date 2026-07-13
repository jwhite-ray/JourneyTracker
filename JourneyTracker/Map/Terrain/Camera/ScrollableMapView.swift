//
//  ScrollableMapView.swift
//  JourneyTracker
//
//  The gesture engine behind the full-screen map (KAN-20, P3). A `UIScrollView`
//  (via `UIViewRepresentable`) is used ONLY for its native pinch anchoring,
//  momentum, rubber-banding and programmatic zoom — the App Concept doc's
//  "backed by UIScrollView for correct momentum, bounce, and zoom feel." It does
//  not draw the map: a transparent dummy content view carries the zoom/pan, and
//  the scroll state is translated into a `MapCamera` that a separate, screen-sized
//  `Canvas` overlay renders (culled + LOD-thinned). This keeps the Canvas pass
//  tiny at every zoom instead of rasterizing the whole 1,800-mile map.
//
//  Mapping (baseZoom = pt/unit at zoomScale 1, chosen = full-journey fit):
//      camera.zoom   = baseZoom * scrollView.zoomScale
//      camera.center = boundsOrigin + (contentOffset + size/2) / zoomScale / baseZoom
//  and the inverse frames the scroll view to a target camera via `zoom(to:)`.
//

import SwiftUI
import Combine

/// Shares the live camera between the scroll view and the SwiftUI overlay, and
/// lets SwiftUI controls (toggle, double-tap) drive the scroll view.
final class MapCameraController: ObservableObject {
    @Published var camera: MapCamera
    /// False until the scroll view's first layout publishes a real camera — the
    /// overlay waits on this so the first frame never flashes an extreme zoom.
    @Published var isReady = false

    /// Set by the representable's coordinator once the scroll view exists.
    fileprivate var frameHandler: ((MapCamera, Bool) -> Void)?

    init(camera: MapCamera) { self.camera = camera }

    /// Animate the scroll view to a target camera (used by the chapter/overview
    /// toggle and double-tap).
    func frame(_ camera: MapCamera, animated: Bool = true) {
        frameHandler?(camera, animated)
    }
}

/// A `UIScrollView` that reports its first real layout, so we can configure zoom
/// bounds and apply the initial chapter framing once the viewport size is known.
final class CameraScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct ScrollableMapSurface: UIViewRepresentable {
    let presentation: JourneyMapPresentation
    @ObservedObject var controller: MapCameraController
    /// The framing to apply on first layout (chapter by default).
    var initialFraming: MapFraming = .chapter

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CameraScrollView {
        let sv = CameraScrollView()
        sv.delegate = context.coordinator
        sv.backgroundColor = .clear
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.bouncesZoom = true
        sv.contentInsetAdjustmentBehavior = .never
        sv.decelerationRate = .normal

        let content = UIView()
        content.backgroundColor = .clear
        sv.addSubview(content)
        context.coordinator.contentView = content
        context.coordinator.scrollView = sv
        controller.frameHandler = { [weak coordinator = context.coordinator] cam, animated in
            coordinator?.apply(camera: cam, animated: animated)
        }

        sv.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.configureIfNeeded()
        }
        return sv
    }

    func updateUIView(_ uiView: CameraScrollView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ScrollableMapSurface
        weak var scrollView: CameraScrollView?
        weak var contentView: UIView?

        private var configuredSize: CGSize = .zero
        private var didAddDoubleTap = false
        private(set) var baseZoom: CGFloat = 1

        init(_ parent: ScrollableMapSurface) { self.parent = parent }

        // Called on every layout. Configures on first real size, and RECONFIGURES
        // on a size change (rotation / split view) — recomputing baseZoom, content
        // size and zoom limits, and re-framing to preserve the current camera.
        func configureIfNeeded() {
            guard let sv = scrollView, let content = contentView else { return }
            let size = sv.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            let sizeChanged = abs(size.width - configuredSize.width) > 0.5
                || abs(size.height - configuredSize.height) > 0.5
            guard sizeChanged else { return }

            let firstTime = configuredSize == .zero
            // Preserve the camera we're currently showing across a resize.
            let preserved = firstTime
                ? (parent.initialFraming == .overview
                    ? parent.presentation.overviewCamera(viewport: size)
                    : parent.presentation.chapterCamera(viewport: size))
                : parent.controller.camera
            configuredSize = size

            let bounds = parent.presentation.authoring.bounds
            let z = parent.presentation.zoomBounds(viewport: size)
            baseZoom = z.min
            // Reset scale to 1 before resizing content so contentSize stays sane.
            sv.minimumZoomScale = 1
            sv.maximumZoomScale = max(1.0001, z.max / z.min)
            sv.setZoomScale(1, animated: false)
            content.frame = CGRect(origin: .zero,
                                   size: CGSize(width: bounds.width * baseZoom,
                                                height: bounds.height * baseZoom))
            sv.contentSize = content.frame.size

            if !didAddDoubleTap {
                didAddDoubleTap = true
                let dt = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
                dt.numberOfTapsRequired = 2
                sv.addGestureRecognizer(dt)
            }

            setOverscrollInsets()
            apply(camera: preserved, animated: false)
            publishCamera()
        }

        /// A HALF-VIEWPORT overscroll inset on every side. Two jobs at once:
        /// • it lets ANY map point — even one at the very edge of the world — be
        ///   scrolled to screen center, so chapter framing can center a marker that
        ///   sits near the bounds edge (the fix for the drift Rooster saw); and
        /// • with content smaller than the viewport it still allows the explicit
        ///   centered offset `apply` sets, so overview rests centered, not corner-
        ///   pinned. Read/write stay exact inverses (`contentOffset + bounds/2` is
        ///   independent of the inset).
        private func setOverscrollInsets() {
            guard let sv = scrollView else { return }
            let inset = UIEdgeInsets(top: sv.bounds.height / 2, left: sv.bounds.width / 2,
                                     bottom: sv.bounds.height / 2, right: sv.bounds.width / 2)
            if sv.contentInset != inset { sv.contentInset = inset }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { publishCamera() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { publishCamera() }

        // MARK: Scroll ⇄ camera

        private func publishCamera() {
            guard configuredSize != .zero, let sv = scrollView, baseZoom > 0, sv.zoomScale > 0 else { return }
            let origin = parent.presentation.authoring.bounds.origin
            // Screen-center in scaled-content coords is `contentOffset + bounds/2`,
            // independent of contentInset — so centering never skews the read.
            let centerScaled = CGPoint(x: sv.contentOffset.x + sv.bounds.width / 2,
                                       y: sv.contentOffset.y + sv.bounds.height / 2)
            let unscaled = CGPoint(x: centerScaled.x / sv.zoomScale, y: centerScaled.y / sv.zoomScale)
            let center = CGPoint(x: origin.x + unscaled.x / baseZoom,
                                 y: origin.y + unscaled.y / baseZoom)
            let cam = MapCamera(center: center, zoom: baseZoom * sv.zoomScale)
            if cam != parent.controller.camera { parent.controller.camera = cam }
            if !parent.controller.isReady { parent.controller.isReady = true }
        }

        func apply(camera: MapCamera, animated: Bool) {
            guard let sv = scrollView, baseZoom > 0 else { return }
            let size = sv.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            let origin = parent.presentation.authoring.bounds.origin
            // Direct zoomScale + explicit centered offset — NOT `zoom(to:)`, whose
            // clamp-to-content would pull a near-edge marker off center. With the
            // half-viewport overscroll insets the offset is never clamped, so
            // `camera.center` lands exactly at screen center every time.
            let zs = min(max(camera.zoom / baseZoom, sv.minimumZoomScale), sv.maximumZoomScale)
            let apply = {
                sv.zoomScale = zs
                let centerScaled = CGPoint(x: (camera.center.x - origin.x) * self.baseZoom * zs,
                                           y: (camera.center.y - origin.y) * self.baseZoom * zs)
                sv.contentOffset = CGPoint(x: centerScaled.x - size.width / 2,
                                           y: centerScaled.y - size.height / 2)
            }
            if animated {
                UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut],
                               animations: apply)
            } else {
                apply()
            }
            if !animated { publishCamera() }
        }

        @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            let size = sv.bounds.size
            let tap = gr.location(in: sv)
            let tappedMap = parent.controller.camera.unproject(
                CGPoint(x: tap.x - sv.contentOffset.x, y: tap.y - sv.contentOffset.y), in: size)
            let z = parent.presentation.zoomBounds(viewport: size)
            let target = min(parent.controller.camera.zoom * 2.2, z.max)
            apply(camera: MapCamera(center: tappedMap, zoom: target), animated: true)
        }
    }
}

/// The two framings the full-screen map toggles between (Justin's KAN-20 ruling).
enum MapFraming: Hashable { case chapter, overview }
