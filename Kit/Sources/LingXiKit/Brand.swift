import Foundation

/// Public-facing brand names. Internal identifiers, bundle IDs and the StoreKit product ID stay
/// on the original LingXiStyle names so upgrades and purchases survive the rename.
public enum Brand {
    /// 纹粒 in Simplified Chinese, Texel everywhere else.
    public static var name: String {
        String(localized: "brand.name", defaultValue: "纹粒")
    }

    /// 纹粒 Pro in Simplified Chinese, Texel Pro everywhere else.
    public static var proName: String {
        String(localized: "brand.proName", defaultValue: "纹粒 Pro")
    }

    public static var signature: String {
        String(localized: "brand.signature", defaultValue: "纹粒 — by LingXiFox")
    }
}
