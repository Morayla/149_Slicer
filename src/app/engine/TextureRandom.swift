import Foundation

// MT19937 and 53-bit uniforms keep saved texture seeds reproducible.
struct TextureRandom {
    private var state = Array(repeating: UInt32(0), count: 624)
    private var index = 624
    init(seed: UInt64) {
        var keys = [UInt32(truncatingIfNeeded: seed)]
        if seed >> 32 != 0 { keys.append(UInt32(seed >> 32)) }
        state[0] = 19_650_218
        for i in 1..<624 { state[i] = 1_812_433_253 &* (state[i - 1] ^ (state[i - 1] >> 30)) &+ UInt32(i) }
        var i = 1
        var j = 0
        for _ in 0..<max(624, keys.count) {
            state[i] = (state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) &* 1_664_525)) &+ keys[j] &+ UInt32(j)
            i += 1
            j += 1
            if i >= 624 {
                state[0] = state[623]
                i = 1
            }
            if j >= keys.count { j = 0 }
        }
        for _ in 0..<623 {
            state[i] = (state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) &* 1_566_083_941)) &- UInt32(i)
            i += 1
            if i >= 624 {
                state[0] = state[623]
                i = 1
            }
        }
        state[0] = 0x8000_0000
    }
    mutating func next() -> UInt32 {
        if index >= 624 {
            for i in 0..<624 {
                let y = (state[i] & 0x8000_0000) | (state[(i + 1) % 624] & 0x7fff_ffff)
                state[i] = state[(i + 397) % 624] ^ (y >> 1) ^ ((y & 1) == 0 ? 0 : 0x9908_b0df)
            }
            index = 0
        }
        var y = state[index]
        index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9d2c_5680
        y ^= (y << 15) & 0xefc6_0000
        y ^= y >> 18
        return y
    }
    mutating func uniform() -> Double {
        let a = next() >> 5
        let b = next() >> 6
        return (Double(a) * 67_108_864 + Double(b)) / 9_007_199_254_740_992
    }
}
