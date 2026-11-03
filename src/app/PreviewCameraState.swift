import SceneKit

final class PreviewCameraState {
    var valid = false
    var action = -1
    var target = SIMD3<Float>.zero
    var yaw: Float = 0.59, pitch: Float = 0.53, distance: Float = 1000
    var scale = 100.0, magnification = 1.0
}

extension ZoomSceneView {
    func connectCamera(_ state: PreviewCameraState?, action: Int) {
        guard let state else { return }
        if state.valid && state.action == action {
            let changed = target != state.target || yaw != state.yaw || pitch != state.pitch || distance != state.distance || fittedScale != state.scale || magnification != state.magnification
            target = state.target; yaw = state.yaw; pitch = state.pitch; distance = state.distance
            fittedScale = state.scale; magnification = state.magnification
            if changed { positionCamera(); applyScale() }
        }
        cameraState = state
        state.action = action
        saveCamera()
    }
    func saveCamera() {
        guard let state = cameraState, bounds.width >= 100, bounds.height >= 100 else { return }
        state.target = target; state.yaw = yaw; state.pitch = pitch; state.distance = distance
        state.scale = fittedScale; state.magnification = magnification; state.valid = true
    }
}
