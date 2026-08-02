import Darwin
import Foundation
import IOKit
import IOKit.ps
import Network
import os

nonisolated protocol NetworkReader: MetricReader where Snapshot == NetworkSnapshot {}

nonisolated struct NetworkSystemSample: Sendable, Equatable {
    let counter: NetworkCounterSample
    let connectivity: NetworkConnectivity

    init(
        counter: NetworkCounterSample,
        connectivity: NetworkConnectivity
    ) {
        self.counter = counter
        self.connectivity = connectivity
    }
}

nonisolated protocol NetworkSystemAdapter: Sendable {
    func read(at timestamp: MetricTimestamp) -> MetricResult<NetworkSystemSample>
}

actor LiveNetworkReader: NetworkReader {
    private let adapter: any NetworkSystemAdapter
    private let counterMaximum: UInt64?
    private var previousCounter: NetworkCounterSample?
    private let logger = Logger(subsystem: "com.sanepeek.app", category: "NetworkReader")

    init(
        adapter: any NetworkSystemAdapter = DarwinNetworkSystemAdapter(),
        counterMaximum: UInt64? = nil
    ) {
        self.adapter = adapter
        self.counterMaximum = counterMaximum
    }

    func read(at timestamp: MetricTimestamp) async -> MetricResult<NetworkSnapshot> {
        switch adapter.read(at: timestamp) {
        case let .available(sample):
            let throughput = previousCounter.flatMap { previous in
                NetworkThroughputCalculator.calculate(
                    from: previous,
                    to: sample.counter,
                    counterMaximum: counterMaximum
                ).value
            }
            previousCounter = sample.counter

            let interfaceNames = sample.counter.interfaces
                .filter { $0.isValid && !$0.isLoopback && !$0.name.isEmpty }
                .map(\.name)
                .sorted()

            return .available(
                NetworkSnapshot(
                    timestamp: timestamp,
                    downloadBytesPerSecond: throughput?.downloadBytesPerSecond,
                    uploadBytesPerSecond: throughput?.uploadBytesPerSecond,
                    connectivity: sample.connectivity,
                    interfaceNames: interfaceNames
                )
            )
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .failed(failure):
            logger.warning("read failed: \(failure.kind.rawValue, privacy: .public)")
            return .failed(failure)
        }
    }
}

nonisolated protocol NetworkConnectivitySource: Sendable {
    var connectivity: NetworkConnectivity { get }

    func start()
    func cancel()
}

nonisolated struct DarwinNetworkSystemAdapter: NetworkSystemAdapter {
    private let connectivitySource: any NetworkConnectivitySource

    init(
        connectivitySource: any NetworkConnectivitySource = NWPathConnectivitySource()
    ) {
        self.connectivitySource = connectivitySource
        connectivitySource.start()
    }

    func read(at timestamp: MetricTimestamp) -> MetricResult<NetworkSystemSample> {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0 else {
            return .failed(MetricFailure(kind: .systemUnavailable))
        }
        defer {
            if let addressList {
                freeifaddrs(addressList)
            }
        }

        var interfaces: [NetworkInterfaceCounter] = []
        var seenNames = Set<String>()
        var currentAddress = addressList

        while let address = currentAddress {
            let interface = address.pointee
            currentAddress = interface.ifa_next

            guard let namePointer = interface.ifa_name else {
                continue
            }

            let name = String(cString: namePointer)
            guard !name.isEmpty, seenNames.insert(name).inserted else {
                continue
            }

            let flags = UInt32(interface.ifa_flags)
            let isLoopback = flags & UInt32(IFF_LOOPBACK) != 0
            let isValid = flags & UInt32(IFF_UP) != 0 && !isLoopback

            guard let data = interface.ifa_data else {
                continue
            }

            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            interfaces.append(
                NetworkInterfaceCounter(
                    name: name,
                    downloadBytes: UInt64(counters.ifi_ibytes),
                    uploadBytes: UInt64(counters.ifi_obytes),
                    isLoopback: isLoopback,
                    isValid: isValid
                )
            )
        }

        return .available(
            NetworkSystemSample(
                counter: NetworkCounterSample(
                    timestamp: timestamp,
                    interfaces: interfaces
                ),
                connectivity: connectivitySource.connectivity
            )
        )
    }
}

final class NWPathConnectivitySource: NetworkConnectivitySource, @unchecked Sendable {
    private let lock = NSLock()
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var started = false
    private var cancelled = false
    private var currentValue: NetworkConnectivity = .unknown

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(
            label: "com.sanepeek.network-path",
            qos: .utility
        )
    ) {
        self.monitor = monitor
        self.queue = queue
        monitor.pathUpdateHandler = { [weak self] path in
            let connectivity: NetworkConnectivity
            switch path.status {
            case .satisfied:
                connectivity = .connected
            case .unsatisfied, .requiresConnection:
                connectivity = .disconnected
            @unknown default:
                connectivity = .unknown
            }

            self?.update(connectivity)
        }
        start()
    }

    var connectivity: NetworkConnectivity {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }

    func start() {
        lock.lock()
        guard !started, !cancelled else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()
        monitor.start(queue: queue)
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        lock.unlock()
        monitor.cancel()
    }

    deinit {
        cancel()
    }

    private func update(_ connectivity: NetworkConnectivity) {
        lock.lock()
        currentValue = connectivity
        lock.unlock()
    }
}
