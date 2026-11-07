import Foundation

/// Builds the text the user can copy or share with the developer. Photo identifiers, file names
/// and absolute paths never leave the device.
public enum DiagnosticsFormatter {
    public static func report(appVersion: String,
                              build: String,
                              systemVersion: String,
                              deviceModel: String,
                              inspection: HEICInspection?,
                              verdict: CompatibilityVerdict?,
                              integrity: IntegrityReport?,
                              failure: String? = nil) -> String {
        var lines: [String] = []
        lines.append("\(Brand.name) \(appVersion) (\(build))")
        lines.append("system: \(systemVersion) · \(deviceModel)")
        if let inspection {
            lines.append("container: \(inspection.container.rawValue) · \(inspection.fileByteCount) bytes")
            lines.append("geometry: \(inspection.pixelSizeDescription) · rot \(inspection.rotationQuarterTurns)")
            lines.append("items: \(inspection.itemCount) · grid \(inspection.hasPrimaryGrid) · tiles \(inspection.primaryTileCount) · hdrTiles \(inspection.hdrTileCount)")
            lines.append("flags: style \(inspection.hasStyleMetadata) · texture \(inspection.hasTextureStyle) · exif \(inspection.hasExif) · thumb \(inspection.hasThumbnail) · gain \(inspection.hasHDRGainMap) · linear \(inspection.hasLinearThumbnail)")
            lines.append("iloc: \(inspection.ilocDescription) · graftable \(inspection.supportsGraftLayout)")
            if !inspection.warnings.isEmpty {
                lines.append("warnings: \(inspection.warnings.joined(separator: "; "))")
            }
        }
        if let verdict {
            lines.append("verdict: \(verdict.status.rawValue) \(verdict.issues.map(\.rawValue).joined(separator: ","))")
        }
        if let integrity {
            lines.append("integrity: \(integrity.passed ? "pass" : "fail") · \(integrity.checks.filter(\.passed).count)/\(integrity.checks.count)")
            for check in integrity.checks where !check.passed {
                lines.append("  ✗ \(check.id): \(check.title) — \(check.detail)")
            }
        }
        if let failure {
            lines.append("failure: \(redact(failure))")
        }
        return lines.joined(separator: "\n")
    }

    /// Strips home directories and file URLs so copy-paste never leaks a path.
    static func redact(_ text: String) -> String {
        var output = text
        if let range = output.range(of: "/Users/[^ \n:]*", options: .regularExpression) {
            output.replaceSubrange(range, with: "<path>")
        }
        if let range = output.range(of: "/private/var/[^ \n:]*", options: .regularExpression) {
            output.replaceSubrange(range, with: "<path>")
        }
        return output
    }
}