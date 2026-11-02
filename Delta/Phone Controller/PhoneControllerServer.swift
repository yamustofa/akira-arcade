//
//  PhoneControllerServer.swift
//  Delta
//
//  Akira Arcade, stage 2: phones on the same Wi-Fi become game controllers.
//
//  The iPad listens on one TCP port (8765) with the Network framework, no outside libraries:
//  - GET /    serves controller.html, the one-page gamepad the phone opens.
//  - GET /ws  upgrades to a WebSocket (handshake and framing done here, RFC 6455 subset)
//             that carries the phone's button mask.
//
//  Protocol (JSON text messages):
//  phone → iPad  { "t": "join", "k": "<token>" }     first message; the token comes from the QR code
//  iPad → phone  { "t": "hello", "slot": 0 }          accepted: slot is the player index in the game
//                                                      (0 is Player 1); a keyboard or gamepad that is
//                                                      already connected can take the lower indexes
//  iPad → phone  { "t": "full" } / { "t": "denied" }  refused, then the iPad closes the socket
//  phone → iPad  { "m": <mask> }                       the buttons held now, sent on every change and
//                                                      every 250 ms while any button is held
//  The token changes every time the server starts, so other devices on the same Wi-Fi can't
//  join without scanning the QR code. If a phone goes quiet for 1 s while holding buttons, or
//  its socket closes, all its buttons are released so nothing stays stuck.
//
//  Threads: bytes are read and parsed on `queue`; everything else (state, sessions, the game
//  controllers) lives on the main thread.
//

import Foundation
import Network
import Security
import CryptoKit
import OSLog
import DeltaCore

extension Logger
{
    static let phoneController = Logger(subsystem: "com.akira.arcade", category: "PhoneController")
}

final class PhoneControllerServer: ObservableObject
{
    static let shared = PhoneControllerServer()

    static let port: NWEndpoint.Port = 8765
    static let maximumPlayers = 2

    /// How long a phone may stay silent while holding buttons before they are released.
    static let quietTimeout: TimeInterval = 1.0

    enum State: Equatable
    {
        case stopped
        case starting
        case running
        case failed(String)
    }

    struct Player: Identifiable, Equatable
    {
        var id: ObjectIdentifier
        
        /// Which phone this is, 0 or 1 (at most `maximumPlayers` phones).
        var slot: Int
        
        /// The player this phone controls in the game, 0 for Player 1; nil if not assigned.
        var playerIndex: Int?
        
        var name: String
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var players: [Player] = []
    @Published private(set) var token: String = ""

    /// The address phones open, e.g. http://192.168.1.20:8765/?k=…; nil without a local network address.
    var controllerURL: URL? {
        guard self.state == .running, let host = PhoneControllerServer.localIPAddress() else { return nil }
        return URL(string: "http://\(host):\(PhoneControllerServer.port.rawValue)/?k=\(self.token)")
    }

    private var listener: NWListener?

    /// Phones that finished the WebSocket handshake, by client.
    private var sessions: [ObjectIdentifier: Client] = [:]

    private var watchdogTimer: Timer?

    /// Recent server events, newest last; shown at /status in Debug builds.
    private var events: [String] = []

    private let queue = DispatchQueue(label: "com.akira.arcade.PhoneControllerServer")

    private lazy var controllerPage: Data = {
        guard let fileURL = Bundle.main.url(forResource: "controller", withExtension: "html"),
              let data = try? Data(contentsOf: fileURL)
        else { return Data("controller.html is missing from the app bundle.".utf8) }

        return data
    }()

    private init()
    {
    }
}

//MARK: - Client -
private extension PhoneControllerServer
{
    /// One TCP connection: a page request, or a phone's WebSocket.
    final class Client
    {
        let connection: NWConnection

        // Used on `queue` only.
        var buffer: [UInt8] = []
        var isWebSocket = false
        var isClosed = false

        // Used on the main thread only.
        var controller: PhoneGameController?
        var slot: Int?
        var lastMessageDate = Date()

        init(connection: NWConnection)
        {
            self.connection = connection
        }
    }
}

//MARK: - Starting and Stopping -
extension PhoneControllerServer
{
    /// Starts the listener with a fresh token. Call on the main thread.
    func start()
    {
        self.start(token: PhoneControllerServer.makeToken())
    }

    /// Starts the listener with the given token. Debug builds use a fixed token for testing.
    func start(token: String)
    {
        switch self.state
        {
        case .starting, .running: return
        case .stopped, .failed: break
        }

        self.token = token
        self.state = .starting

        do
        {
            let listener = try NWListener(using: .tcp, on: PhoneControllerServer.port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    self?.listenerStateDidChange(state)
                }
            }

            self.listener = listener
            listener.start(queue: self.queue)
        }
        catch
        {
            self.stop()
            self.state = .failed(error.localizedDescription)
            return
        }

        self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.releaseQuietPhones()
        }
    }

    /// Disconnects every phone and closes the listener. Call on the main thread.
    func stop()
    {
        for id in Array(self.sessions.keys)
        {
            self.endSession(id)
        }

        self.listener?.cancel()
        self.listener = nil

        self.watchdogTimer?.invalidate()
        self.watchdogTimer = nil

        self.token = ""
        self.state = .stopped
    }

    private func listenerStateDidChange(_ listenerState: NWListener.State)
    {
        self.note("listener \(listenerState); server \(self.state)")

        switch listenerState
        {
        case .ready:
            if self.state == .starting
            {
                self.state = .running
            }

        case .failed(let error):
            self.stop()
            self.state = .failed(error.localizedDescription)

        case .waiting(let error):
            // Usually the local network permission is still pending or was denied.
            self.state = .failed(error.localizedDescription)

        default:
            break
        }
    }
}

//MARK: - Connections (on queue) -
private extension PhoneControllerServer
{
    func handleNewConnection(_ connection: NWConnection)
    {
        let client = Client(connection: connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state
            {
            case .failed, .cancelled:
                client.isClosed = true
                DispatchQueue.main.async {
                    self?.endSession(ObjectIdentifier(client))
                }

            default:
                break
            }
        }

        connection.start(queue: self.queue)
        self.receive(on: client)
    }

    func receive(on client: Client)
    {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !client.isClosed else { return }

            if let data, !data.isEmpty
            {
                client.buffer.append(contentsOf: data)
                self.process(client)
            }

            if isComplete || error != nil
            {
                self.close(client)
                return
            }

            if !client.isClosed
            {
                self.receive(on: client)
            }
        }
    }

    func process(_ client: Client)
    {
        if !client.isWebSocket
        {
            self.processHTTPRequest(client)
        }

        guard client.isWebSocket else { return }

        while !client.isClosed, let parsed = PhoneControllerServer.parseFrame(client.buffer)
        {
            let (frame, length) = parsed
            client.buffer.removeFirst(length)

            switch frame
            {
            case .text(let payload):
                DispatchQueue.main.async {
                    self.handleMessage(payload, from: client)
                }

            case .ping(let payload):
                client.connection.send(content: PhoneControllerServer.makeFrame(opcode: 0xA, payload: payload), completion: .contentProcessed { _ in })

            case .close:
                client.connection.send(content: PhoneControllerServer.makeFrame(opcode: 0x8, payload: []), completion: .contentProcessed { [weak self] _ in
                    self?.close(client)
                })
                return

            case .other:
                break
            }
        }
    }

    func processHTTPRequest(_ client: Client)
    {
        let terminator: [UInt8] = [13, 10, 13, 10] // \r\n\r\n

        guard let headerEnd = PhoneControllerServer.firstIndex(of: terminator, in: client.buffer) else {
            if client.buffer.count > 16_384
            {
                self.close(client)
            }
            return
        }

        let headerBytes = Array(client.buffer[0 ..< headerEnd])
        client.buffer.removeFirst(headerEnd + terminator.count)

        guard let headerText = String(bytes: headerBytes, encoding: .utf8) else {
            self.close(client)
            return
        }

        let lines = headerText.components(separatedBy: "\r\n")
        let requestParts = (lines.first ?? "").split(separator: " ")
        let method = requestParts.first.map(String.init) ?? ""
        let target = requestParts.count > 1 ? String(requestParts[1]) : ""
        let path = target.components(separatedBy: "?").first ?? target

        var headers: [String: String] = [:]
        for line in lines.dropFirst()
        {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        if method == "GET" && path == "/ws"
        {
            guard headers["upgrade"]?.lowercased() == "websocket", let key = headers["sec-websocket-key"] else {
                self.respond(to: client, status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Expected a WebSocket upgrade".utf8))
                return
            }

            let acceptValue = PhoneControllerServer.webSocketAcceptValue(for: key)
            let response = "HTTP/1.1 101 Switching Protocols\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Accept: \(acceptValue)\r\n\r\n"

            client.isWebSocket = true
            client.connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })

            DispatchQueue.main.async {
                self.accept(client)
            }
            return
        }

        #if DEBUG
        if method == "GET" && path == "/status"
        {
            let status = DispatchQueue.main.sync { "state=\(self.state) players=\(self.players.count) sessions=\(self.sessions.count)\n" + self.events.joined(separator: "\n") }
            self.respond(to: client, status: "200 OK", contentType: "text/plain; charset=utf-8", body: Data(status.utf8))
            return
        }
        #endif

        if method == "GET" && (path == "/" || path == "/index.html")
        {
            self.respond(to: client, status: "200 OK", contentType: "text/html; charset=utf-8", body: self.controllerPage)
        }
        else
        {
            self.respond(to: client, status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not found".utf8))
        }
    }

    func respond(to client: Client, status: String, contentType: String, body: Data)
    {
        let header = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n\r\n"

        client.connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in
            self?.close(client)
        })
    }

    func close(_ client: Client)
    {
        guard !client.isClosed else { return }
        client.isClosed = true
        client.connection.cancel()
    }
}

//MARK: - Sessions (main thread) -
private extension PhoneControllerServer
{
    func accept(_ client: Client)
    {
        let id = ObjectIdentifier(client)
        self.note("websocket open \(id.hashValue % 1000)")

        guard self.state == .running else {
            self.queue.async { self.close(client) }
            return
        }

        self.sessions[id] = client
    }

    func handleMessage(_ data: Data, from client: Client)
    {
        let id = ObjectIdentifier(client)
        guard self.sessions[id] != nil,
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        client.lastMessageDate = Date()

        if let type = message["t"] as? String, type == "join"
        {
            self.join(client, token: message["k"] as? String)
        }
        else if let mask = message["m"] as? Int, let controller = client.controller
        {
            // Bit 15 is reserved; ignore it and anything above 16 bits.
            controller.update(buttonMask: UInt16(truncatingIfNeeded: mask) & 0x7FFF)
        }
    }

    func join(_ client: Client, token: String?)
    {
        guard client.controller == nil else { return }

        guard let token, !token.isEmpty, token == self.token else {
            self.note("join denied")
            self.refuse(client, type: "denied")
            return
        }

        let usedSlots = Set(self.sessions.values.compactMap { $0.slot })
        guard let slot = (0 ..< PhoneControllerServer.maximumPlayers).first(where: { !usedSlots.contains($0) }) else {
            self.note("join refused: full")
            self.refuse(client, type: "full")
            return
        }

        let controller = PhoneGameController(name: String(format: NSLocalizedString("Phone %@", comment: ""), "\(slot + 1)"))
        client.controller = controller
        client.slot = slot

        ExternalGameControllerManager.shared.connect(controller)

        // The phone shows the player it actually controls, which can differ from its slot
        // when a keyboard or gamepad is connected too.
        let playerIndex = controller.playerIndex ?? slot
        self.note("phone \(slot + 1) joined as Player \(playerIndex + 1)")
        self.send(["t": "hello", "slot": playerIndex], to: client)
        self.updatePlayers()
    }

    func refuse(_ client: Client, type: String)
    {
        self.send(["t": type], to: client)
        
        // Close cleanly: a close frame (1000), then end the session once it has gone out.
        let closeFrame = PhoneControllerServer.makeFrame(opcode: 0x8, payload: [0x03, 0xE8])
        client.connection.send(content: closeFrame, completion: .contentProcessed { [weak self] _ in
            DispatchQueue.main.async {
                self?.endSession(ObjectIdentifier(client))
            }
        })
    }

    func endSession(_ id: ObjectIdentifier)
    {
        guard let client = self.sessions.removeValue(forKey: id) else { return }
        self.note("websocket closed \(id.hashValue % 1000)")

        if let controller = client.controller
        {
            controller.releaseAllInputs()
            ExternalGameControllerManager.shared.disconnect(controller)
        }

        client.controller = nil
        client.slot = nil

        self.queue.async { self.close(client) }
        self.updatePlayers()
    }

    func releaseQuietPhones()
    {
        let now = Date()

        for client in self.sessions.values
        {
            guard let controller = client.controller, controller.buttonMask != 0 else { continue }
            guard now.timeIntervalSince(client.lastMessageDate) > PhoneControllerServer.quietTimeout else { continue }

            controller.releaseAllInputs()
        }
    }

    func send(_ message: [String: Any], to client: Client, completion: (() -> Void)? = nil)
    {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }

        let frame = PhoneControllerServer.makeFrame(opcode: 0x1, payload: Array(data))
        client.connection.send(content: frame, completion: .contentProcessed { _ in
            completion?()
        })
    }

    func updatePlayers()
    {
        self.players = self.sessions.compactMap { id, client in
            guard let controller = client.controller, let slot = client.slot else { return nil }
            return Player(id: id, slot: slot, playerIndex: controller.playerIndex, name: controller.name)
        }
        .sorted { $0.slot < $1.slot }
    }

    /// Records an event in the log and, in Debug builds, in `events`.
    func note(_ message: String)
    {
        Logger.phoneController.info("\(message, privacy: .public)")

        #if DEBUG
        self.events.append(message)
        if self.events.count > 40
        {
            self.events.removeFirst(self.events.count - 40)
        }
        #endif
    }
}

//MARK: - WebSocket Framing -
private extension PhoneControllerServer
{
    enum Frame
    {
        case text(Data)
        case ping([UInt8])
        case close
        case other
    }

    /// Parses one frame from the start of `bytes`; nil until the whole frame has arrived.
    /// Fragmented messages aren't supported (browsers don't fragment small messages).
    static func parseFrame(_ bytes: [UInt8]) -> (Frame, Int)?
    {
        guard bytes.count >= 2 else { return nil }

        let opcode = bytes[0] & 0x0F
        let isMasked = (bytes[1] & 0x80) != 0

        var payloadLength = Int(bytes[1] & 0x7F)
        var offset = 2

        if payloadLength == 126
        {
            guard bytes.count >= 4 else { return nil }
            payloadLength = Int(bytes[2]) << 8 | Int(bytes[3])
            offset = 4
        }
        else if payloadLength == 127
        {
            guard bytes.count >= 10 else { return nil }
            payloadLength = 0
            for index in 2 ..< 10
            {
                payloadLength = payloadLength << 8 | Int(bytes[index])
            }
            offset = 10
        }

        // Phones only send tiny JSON messages; anything huge is treated as a close.
        guard payloadLength <= 65_536 else { return (.close, bytes.count) }

        var mask: [UInt8] = []
        if isMasked
        {
            guard bytes.count >= offset + 4 else { return nil }
            mask = Array(bytes[offset ..< offset + 4])
            offset += 4
        }

        guard bytes.count >= offset + payloadLength else { return nil }

        var payload = Array(bytes[offset ..< offset + payloadLength])
        if isMasked
        {
            for index in payload.indices
            {
                payload[index] ^= mask[index % 4]
            }
        }

        let frame: Frame
        switch opcode
        {
        case 0x1: frame = .text(Data(payload))
        case 0x8: frame = .close
        case 0x9: frame = .ping(payload)
        default: frame = .other
        }

        return (frame, offset + payloadLength)
    }

    /// An unmasked server frame (servers never mask).
    static func makeFrame(opcode: UInt8, payload: [UInt8]) -> Data
    {
        var bytes: [UInt8] = [0x80 | opcode]

        if payload.count < 126
        {
            bytes.append(UInt8(payload.count))
        }
        else
        {
            bytes.append(126)
            bytes.append(UInt8((payload.count >> 8) & 0xFF))
            bytes.append(UInt8(payload.count & 0xFF))
        }

        return Data(bytes + payload)
    }

    static func webSocketAcceptValue(for key: String) -> String
    {
        let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
        return Data(digest).base64EncodedString()
    }

    static func firstIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int?
    {
        guard bytes.count >= pattern.count else { return nil }

        for start in 0 ... (bytes.count - pattern.count)
        {
            if Array(bytes[start ..< start + pattern.count]) == pattern
            {
                return start
            }
        }

        return nil
    }
}

//MARK: - Helpers -
private extension PhoneControllerServer
{
    static func makeToken() -> String
    {
        var bytes = [UInt8](repeating: 0, count: 12)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        if status != errSecSuccess
        {
            bytes = (0 ..< 12).map { _ in UInt8.random(in: .min ... .max) }
        }

        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The device's IPv4 address on Wi-Fi (en0), or on another active "en" interface.
    static func localIPAddress() -> String?
    {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var addresses: [String: String] = [:]

        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next })
        {
            let interface = pointer.pointee

            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard (interface.ifa_flags & UInt32(IFF_UP)) != 0, (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }

            addresses[name] = String(cString: host)
        }

        return addresses["en0"] ?? addresses.sorted { $0.key < $1.key }.first?.value
    }
}
