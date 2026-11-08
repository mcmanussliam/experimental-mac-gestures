import Foundation

/// User files hold only overrides, deep-merged over defaults, so partial configs are valid.
public enum JSONMerge {
    /// Deep-merges `overlay` onto `base`. Objects merge recursively; everything else replaces.
    public static func merge(_ base: Any, _ overlay: Any) -> Any {
        guard let b = base as? [String: Any], let o = overlay as? [String: Any] else { return overlay }
        var out = b
        for (k, v) in o { out[k] = out[k].map { merge($0, v) } ?? v }
        return out
    }

    /// The parts of `value` that differ from `base` (objects compared recursively), or nil if
    /// equal. `merge(base, diff(base, value)!)` reproduces `value`.
    public static func diff(_ base: Any, _ value: Any) -> Any? {
        if let b = base as? [String: Any], let v = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, vv) in v {
                if let bv = b[k] { if let d = diff(bv, vv) { out[k] = d } } else { out[k] = vv }
            }
            return out.isEmpty ? nil : out
        }
        return (base as AnyObject).isEqual(value) ? nil : value
    }

    /// JSON of the fields of `value` that differ from `defaults`.
    public static func overrides<T: Codable>(_ value: T, defaults: T) throws -> [String: Any] {
        let enc = JSONEncoder()
        let b = try JSONSerialization.jsonObject(with: enc.encode(defaults))
        let v = try JSONSerialization.jsonObject(with: enc.encode(value))
        return diff(b, v) as? [String: Any] ?? [:]
    }

    public static func decode<T: Codable>(_ type: T.Type, defaults: T, overlay data: Data?) throws -> T {
        let baseData = try JSONEncoder().encode(defaults)
        guard let data, !data.isEmpty else { return defaults }
        let base = try JSONSerialization.jsonObject(with: baseData)
        let over = try JSONSerialization.jsonObject(with: data)
        let merged = try JSONSerialization.data(withJSONObject: merge(base, over))
        return try JSONDecoder().decode(T.self, from: merged)
    }
}

extension EngineConfig {
    /// Engine settings from a user config file (`{"engine": {...}}`), merged over defaults.
    public static func fromUserConfig(_ data: Data?) -> EngineConfig {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let engine = root["engine"], let overlay = try? JSONSerialization.data(withJSONObject: engine)
        else { return EngineConfig() }
        return (try? JSONMerge.decode(EngineConfig.self, defaults: EngineConfig(), overlay: overlay)) ?? EngineConfig()
    }
}
