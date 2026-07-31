import XCTest
@testable import SymTuneCore

/// The exact document `PreferencesManager` writes must parse back into the
/// same choices — a save that cannot be reloaded is a silent data loss.
final class ConfigWriteReadRoundTripTests: XCTestCase {
    func testWrittenConfigParsesBackIntoTheSameChoices() {
        let written = """
        [brightness]
        dim_min = 0.15

        [metrics]
        refresh_interval_seconds = 3.0
        enabled = ["cpu", "memory"]
        visible = ["cpu"]
        order = ["cpu", "memory", "disk", "network"]
        network_unit = "bytes_per_second"
        temperature_unit = "celsius"
        cpu_label = "icon"
        cpu_scale = "absolute"
        cpu_unit = "full"

        [popover]
        cards = ["display_controls", "system_status"]
        """
        let table = TOMLParser().parse(written)

        let styles = TuneConfig.parseMetricStyles(table: table, section: "metrics")
        XCTAssertEqual(styles[.cpu], MetricStyle(label: .icon, scale: .absolute, unit: .full))
        XCTAssertNil(styles[.memory])

        XCTAssertEqual(
            TuneConfig.parseCardSet(table: table),
            [.displayControls, .systemStatus]
        )

        // The unrelated section a user may have hand-written is still readable.
        XCTAssertEqual(table["brightness", "dim_min"]?.doubleValue, 0.15)
    }
}
