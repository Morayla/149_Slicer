import SceneKit

final class ViewportBackgroundTransition {
    private(set) var amount = 0.0
    private var target: Double?
    private var timer: Timer?
    private var apply: ((Double) -> Void)?
    static let duration = 0.25

    func settle(white: Bool) {
        let destination = white ? 1.0 : 0.0
        guard target != destination || timer != nil else { return }
        timer?.invalidate()
        timer = nil
        target = destination
        amount = destination
        apply?(amount)
    }

    func setWhite(_ white: Bool, apply: @escaping (Double) -> Void) {
        self.apply = apply
        let destination = white ? 1.0 : 0.0
        guard target != destination else { return }
        let initial = target == nil
        target = destination
        timer?.invalidate()
        if initial { amount = destination; apply(amount); return }
        apply(amount)
        let start = ProcessInfo.processInfo.systemUptime
        let origin = amount
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / Self.duration)
            self.amount = origin + (destination - origin) * t * t * (3 - 2 * t)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            self.apply?(self.amount)
            SCNTransaction.commit()
            if t == 1 { timer.invalidate(); self.timer = nil }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    static func mix(_ dark: Double, _ light: Double, _ amount: Double) -> Double {
        dark + (light - dark) * amount
    }
    deinit { timer?.invalidate() }
}
