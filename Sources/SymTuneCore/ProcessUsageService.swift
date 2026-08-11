import Darwin
import Foundation

/// Reads the process table through `libproc`.
///
/// No shelling out to `ps`/`top`: a sweep over ~750 processes costs a few
/// milliseconds here, and `ps`'s `%cpu` is an average over the process's whole
/// lifetime, which is not what "what is using my CPU *now*" means.
public struct LibprocProcessSampleSource: ProcessSampleSource {
    public init() {}

    public func sample() -> ProcessSampleSet {
        let pids = Self.allPIDs()
        var samples: [ProcessSample] = []
        samples.reserveCapacity(pids.count)
        var unreadable = 0

        for pid in pids {
            guard let info = Self.taskInfo(pid) else {
                unreadable += 1
                continue
            }
            samples.append(ProcessSample(
                pid: pid,
                name: Self.name(of: pid),
                cpuTimeNanoseconds: info.pti_total_user &+ info.pti_total_system,
                memoryBytes: info.pti_resident_size,
                threadCount: Int(info.pti_threadnum)
            ))
        }

        return ProcessSampleSet(
            timestamp: Date.timeIntervalSinceReferenceDate,
            samples: samples,
            unreadableCount: unreadable
        )
    }

    // MARK: - libproc

    private static func allPIDs() -> [Int32] {
        let probe = proc_listallpids(nil, 0)
        guard probe > 0 else { return [] }
        // Head-room for processes spawned between the probe and the read.
        var pids = [Int32](repeating: 0, count: Int(probe) + 64)
        let byteCount = Int32(pids.count * MemoryLayout<Int32>.size)
        let written = proc_listallpids(&pids, byteCount)
        guard written > 0 else { return [] }
        return pids.prefix(Int(written)).filter { $0 > 0 }
    }

    private static func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        // Fails with EPERM for processes owned by another user — expected, and
        // reported as `unreadableProcessCount` rather than silently dropped.
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return info
    }

    /// `PROC_PIDPATHINFO_MAXSIZE` (4 × `MAXPATHLEN`) is a C macro and does not
    /// import into Swift.
    private static let pathBufferSize = 4 * 1024

    private static func name(of pid: Int32) -> String {
        var path = [CChar](repeating: 0, count: pathBufferSize)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let full = String(cString: path)
            if let last = full.split(separator: "/").last, !last.isEmpty {
                return String(last)
            }
        }
        // Short name is truncated to 15 characters but always available.
        var short = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &short, UInt32(short.count)) > 0 {
            let name = String(cString: short)
            if !name.isEmpty { return name }
        }
        return "pid \(pid)"
    }
}

/// Stateful wrapper that keeps the previous sweep so CPU percentages can be
/// differenced. Thread-safe: the menu-bar app samples off the main thread.
public final class ProcessUsageService: @unchecked Sendable {
    /// Default number of processes reported.
    public static let defaultLimit = 6
    /// Hard cap, so an agent asking for "all" cannot produce an unbounded reply.
    public static let maximumLimit = 50

    private let source: any ProcessSampleSource
    private let lock = NSLock()
    private var previous: ProcessSampleSet?

    public init(source: any ProcessSampleSource = LibprocProcessSampleSource()) {
        self.source = source
    }

    /// Take a sweep and rank it against the previous one.
    public func report(
        sortedBy: ProcessSortKey = .cpu,
        limit: Int = ProcessUsageService.defaultLimit
    ) -> ProcessUsageReport {
        let current = source.sample()
        lock.lock()
        let last = previous
        previous = current
        lock.unlock()

        return ProcessUsageRanking.report(
            current: current,
            previous: last,
            sortedBy: sortedBy,
            limit: min(max(limit, 1), Self.maximumLimit)
        )
    }

    /// Forget the previous sweep, so the next report starts a fresh baseline.
    /// Used when the UI stops sampling: a stale baseline would make the first
    /// reading after a long pause average over the whole gap.
    public func resetBaseline() {
        lock.lock()
        previous = nil
        lock.unlock()
    }
}
