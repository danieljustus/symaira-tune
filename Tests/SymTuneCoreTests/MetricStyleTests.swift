import XCTest
@testable import SymTuneCore

final class MetricStyleTests: XCTestCase {

    // MARK: - Fixtures

    /// 8 GB used of 16 GB, 50% CPU, 256 GB used of 512 GB, 2 MB/s down + 512 KB/s up.
    private func report(
        cpu: Double? = 0.5,
        memoryUsed: UInt64? = 8_589_934_592,
        memoryFree: UInt64? = 8_589_934_592,
        disk: DiskReport? = DiskReport(
            capacityBytes: 549_755_813_888,
            usedBytes: 274_877_906_944,
            freeBytes: 274_877_906_944
        ),
        down: Double? = 2_097_152,
        up: Double? = 524_288
    ) -> SystemMetricsReport {
        SystemMetricsReport(
            cpu: CPUReport(totalUtilization: cpu, perCoreUtilization: []),
            memory: MemoryReport(
                usedBytes: memoryUsed,
                freeBytes: memoryFree,
                wiredBytes: nil,
                compressedBytes: nil,
                pressure: nil
            ),
            disk: disk,
            network: NetworkReport(
                interfaces: [],
                aggregateBytesIn: 0,
                aggregateBytesOut: 0,
                aggregateBytesInPerSecond: down,
                aggregateBytesOutPerSecond: up
            )
        )
    }

    private func text(
        _ identifiers: [MetricIdentifier],
        _ styles: [MetricIdentifier: MetricStyle] = [:],
        report: SystemMetricsReport? = nil
    ) -> String {
        let segments = MetricStyleFormatting.statusItemSegments(
            report: report ?? self.report(),
            identifiers: identifiers,
            styles: styles
        )
        return MetricStyleFormatting.plainText(segments)
    }

    // MARK: - Defaults

    func testDefaultStyleMatchesThePreviousStatusItemFormat() {
        XCTAssertEqual(text([.cpu, .memory]), "CPU 50%  RAM 8.0G")
    }

    func testMetricsWithoutStylesFallBackToTheDefault() {
        XCTAssertEqual(text([.cpu], [:]), text([.cpu], [.cpu: .default]))
    }

    // MARK: - Label style

    func testTextLabelPrefixesTheShortName() {
        XCTAssertEqual(text([.disk], [.disk: MetricStyle(label: .text)]), "Disk 256.0G")
    }

    func testHiddenLabelDropsThePrefixEntirely() {
        XCTAssertEqual(text([.disk], [.disk: MetricStyle(label: .hidden)]), "256.0G")
    }

    func testIconLabelEmitsASymbolSegmentInsteadOfTextPrefix() {
        let segments = MetricStyleFormatting.statusItemSegments(
            report: report(),
            identifiers: [.cpu],
            styles: [.cpu: MetricStyle(label: .icon)]
        )
        XCTAssertEqual(segments.first, .symbol(MetricIdentifier.cpu.statusItemSymbol))
        XCTAssertEqual(segments.last, .text(" 50%"))
    }

    // MARK: - Scale

    func testRelativeMemoryIsAShareOfUsedPlusFree() {
        // 8 GB used of 16 GB total.
        XCTAssertEqual(text([.memory], [.memory: MetricStyle(scale: .relative)]), "RAM 50%")
    }

    func testRelativeDiskIsAShareOfCapacity() {
        XCTAssertEqual(text([.disk], [.disk: MetricStyle(scale: .relative)]), "Disk 50%")
    }

    func testAbsoluteMemoryIsAByteAmount() {
        XCTAssertEqual(text([.memory], [.memory: MetricStyle(scale: .absolute)]), "RAM 8.0G")
    }

    /// CPU is already a percentage and network has no total, so the scale
    /// control is inert for them — and the UI disables it on that basis.
    func testScaleIsInertForMetricsThatHaveNoTotal() {
        XCTAssertEqual(
            text([.cpu], [.cpu: MetricStyle(scale: .relative)]),
            text([.cpu], [.cpu: MetricStyle(scale: .absolute)])
        )
        XCTAssertFalse(MetricIdentifier.cpu.supportsRelativeScale)
        XCTAssertFalse(MetricIdentifier.network.supportsRelativeScale)
        XCTAssertTrue(MetricIdentifier.memory.supportsRelativeScale)
        XCTAssertTrue(MetricIdentifier.disk.supportsRelativeScale)
    }

    // MARK: - Units

    func testFullUnitsSpellOutTheSuffix() {
        XCTAssertEqual(text([.memory], [.memory: MetricStyle(unit: .full)]), "RAM 8.0 GB")
    }

    func testHiddenUnitsLeaveABareNumber() {
        XCTAssertEqual(text([.memory], [.memory: MetricStyle(unit: .hidden)]), "RAM 8.0")
        XCTAssertEqual(
            text([.cpu], [.cpu: MetricStyle(unit: .hidden)]),
            "CPU 50"
        )
    }

    func testNetworkUnitsApplyToBothDirections() {
        XCTAssertEqual(
            text([.network], [.network: MetricStyle(unit: .full)]),
            "Net \u{2193}2.0 MB/s \u{2191}512 KB/s"
        )
        XCTAssertEqual(
            text([.network], [.network: MetricStyle(unit: .abbreviated)]),
            "Net \u{2193}2.0M \u{2191}512K"
        )
    }

    // MARK: - Missing data

    func testMetricsWithoutDataAreOmittedRatherThanShownEmpty() {
        let partial = report(cpu: nil, disk: nil)
        XCTAssertEqual(text([.cpu, .memory, .disk], report: partial), "RAM 8.0G")
    }

    func testRelativeMemoryFallsBackToNothingWhenTotalIsUnknown() {
        let partial = report(memoryFree: nil)
        XCTAssertEqual(
            text([.memory], [.memory: MetricStyle(scale: .relative)], report: partial),
            ""
        )
    }

    func testSeparatorAppearsOnlyBetweenMetrics() {
        XCTAssertEqual(text([.cpu]), "CPU 50%")
        XCTAssertFalse(text([.cpu]).hasPrefix(" "))
    }

    // MARK: - Config round-trip

    func testStylesParseFromTheMetricsSection() {
        let toml = """
        [metrics]
        cpu_label = "icon"
        memory_scale = "relative"
        memory_unit = "full"
        """
        let table = TOMLParser().parse(toml)
        let styles = TuneConfig.parseMetricStyles(table: table, section: "metrics")

        XCTAssertEqual(styles[.cpu]?.label, .icon)
        XCTAssertEqual(styles[.cpu]?.unit, MetricStyle.default.unit, "unspecified axes keep the default")
        XCTAssertEqual(styles[.memory]?.scale, .relative)
        XCTAssertEqual(styles[.memory]?.unit, .full)
        XCTAssertNil(styles[.disk], "a metric with no style keys stays absent")
    }

    func testUnknownStyleValuesFallBackToTheDefaultAxis() {
        let table = TOMLParser().parse("""
        [metrics]
        cpu_label = "hologram"
        """)
        let styles = TuneConfig.parseMetricStyles(table: table, section: "metrics")
        XCTAssertNil(styles[.cpu], "no recognised axis means no style entry at all")
    }
}
