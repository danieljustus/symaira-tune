import Foundation

/// Single source of truth for the tool version. Keep in sync with CHANGELOG.md
/// and the git tag on release (`v<version>`).
public enum TuneVersion: Sendable {
    public static let current = "0.1.1"
}
