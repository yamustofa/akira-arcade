//
//  PhoneControllerServer.swift
//  Delta
//
//  Akira Arcade, stage 2: phones on the same Wi-Fi become game controllers.
//
//  The iPad runs two small listeners with the Network framework, no outside libraries:
//  - HTTP on port 8765 serves controller.html, the one-page gamepad the phone opens.
//  - WebSocket on port 8766 carries the phone's button mask.
//
//  Protocol (JSON text messages):
//  phone → iPad  { "t": "join", "k": "<token>" }   first message; the token comes from the QR code
//  iPad → phone  { "t": "hello", "slot": 0 }        accepted: slot 0 is P1, 1 is P2
//  iPad → phone  { "t": "full" } / { "t": "denied" } refused, then the iPad closes the socket
//  phone → iPad  { "m": <mask> }                     the buttons held now, sent on every change and
//                                                    every 250 ms while any button is held
//  The token changes every time the server starts, so other devices on the same Wi-Fi can't
//  join without scanning the QR code. If a phone goes quiet for 1 s while holding buttons, or
//  its socket closes, all its buttons are released so nothing stays stuck.
//

import Foundation
import Network
import Security
import DeltaCore
import OSLog

extension Logger
{
    static let phoneController = Logger(subsystem: "com.akira.arcade", category: "PhoneController")
}

final class PhoneControllerServer: ObservableObject
{
    static let shared = PhoneControllerServer()
    
    static let httpPort: NWEndpoint.Port = 8765
    static let webSocketPort: NWEndpoint.Port = 8766
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
        var slot: Int
        var name: String
    }
    
    @Published private(set) var state: State = .stopped
    @Published private(set) var players: [Player] = []
    @Published private(set) var token: String = ""
    
    /// The address phones open, e.g. http://192.168.1.20:8765/?k=…; nil without a local network address.
    var controllerURL: URL? {
        guard self.state == .running, let host = PhoneControllerServer.localIPAddress() else { return nil }
        return URL(string: "http://\(host):\(PhoneControllerServer.httpPort.rawValue)/?k=\(self.token)")
    }
    
    private var httpListener: NWListener?
    private var webSocketListener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var slots: [ObjectIdentifier: Int] = [:]
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

//MARK: - Diagnostics -
private extension PhoneControllerServer
{
    /// Records an event in the log and, in Debug builds, in `events`. Call on the main thread.
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

//MARK: - Starting and Stopping -
extension PhoneControllerServer
{
    /// Starts both listeners with a fresh token. Call on the main thread.
    func start()
    {
        self.start(token: PhoneControllerServer.makeToken())
    }
    
    /// Starts both listeners with the given token. Debug builds use a fixed token for testing.
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
            let httpListener = try NWListener(using: .tcp, on: PhoneControllerServer.httpPort)
            httpListener.newConnectionHandler = { [weak self] connection in
                self?.handleHTTP(connection)
            }
            
            let webSocketOptions = NWProtocolWebSocket.Options()
            webSocketOptions.autoReplyPing = true
            
            let webSocketParameters = NWParameters.tcp
            webSocketParameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
            
            let webSocketListener = try NWListener(using: webSocketParameters, on: PhoneControllerServer.webSocketPort)
            webSocketListener.newConnectionHandler = { [weak self] connection in
                DispatchQueue.main.async {
                    self?.accept(connection)
                }
            }
            
            for listener in [httpListener, webSocketListener]
            {
                listener.stateUpdateHandler = { [weak self] state in
                    DispatchQueue.main.async {
                        self?.listenerStateDidChange(state)
                    }
                }
            }
            
            self.httpListener = httpListener
            self.webSocketListener = webSocketListener
            
            httpListener.start(queue: self.queue)
            webSocketListener.start(queue: self.queue)
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
    
    /// Disconnects every phone and closes both listeners. Call on the main thread.
    func stop()
    {
        for id in Array(self.sessions.keys)
        {
            self.endSession(id)
        }
        
        self.httpListener?.cancel()
        self.webSocketListener?.cancel()
        self.httpListener = nil
        self.webSocketListener = nil
        
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
            guard let httpListener = self.httpListener, let webSocketListener = self.webSocketListener else { return }
            
            var bothReady = false
            if case .ready = httpListener.state, case .ready = webSocketListener.state
            {
                bothReady = true
            }
            
            if bothReady && self.state == .starting
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

//MARK: - HTTP -
private extension PhoneControllerServer
{
    func handleHTTP(_ connection: NWConnection)
    {
        connection.start(queue: self.queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            // "GET /?k=… HTTP/1.1" → "/?k=…"
            let requestLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = requestLine.split(separator: " ")
            let method = parts.first.map(String.init) ?? ""
            let path = parts.count > 1 ? String(parts[1]) : ""
            
            let response: Data
            #if DEBUG
            if method == "GET" && path == "/status"
            {
                let status = DispatchQueue.main.sync { "state=\(self.state) players=\(self.players.count) sessions=\(self.sessions.count)\n" + self.events.joined(separator: "\n") }
                let response = PhoneControllerServer.httpResponse(status: "200 OK", contentType: "text/plain; charset=utf-8", body: Data(status.utf8))
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            #endif
            
            if method == "GET" && (path == "/" || path.hasPrefix("/?") || path == "/index.html")
            {
                response = PhoneControllerServer.httpResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: self.controllerPage)
            }
            else
            {
                response = PhoneControllerServer.httpResponse(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not found".utf8))
            }
            
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    static func httpResponse(status: String, contentType: String, body: Data) -> Data
    {
        let header = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n\r\n"
        
        return Data(header.utf8) + body
    }
}

//MARK: - WebSocket Sessions -
private extension PhoneControllerServer
{
    final class Session
    {
        let connection: NWConnection
        var controller: PhoneGameController?
        var lastMessageDate = Date()
        
        init(connection: NWConnection)
        {
            self.connection = connection
        }
    }
    
    func accept(_ connection: NWConnection)
    {
        self.note("accept \(connection.endpoint); server \(self.state)")
        
        guard self.state == .running else {
            connection.cancel()
            return
        }
        
        let id = ObjectIdentifier(connection)
        self.sessions[id] = Session(connection: connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.note("connection \(id.hashValue % 1000): \(state)")
            }
            
            switch state
            {
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    self?.endSession(id)
                }
                
            default:
                break
            }
        }
        
        connection.start(queue: self.queue)
        self.receiveNextMessage(on: connection, id: id)
    }
    
    func receiveNextMessage(on connection: NWConnection, id: ObjectIdentifier)
    {
        connection.receiveMessage { [weak self] data, context, _, error in
            DispatchQueue.main.async {
                guard let self, self.sessions[id] != nil else { return }
                
                if let error
                {
                    self.note("receive error: \(error)")
                    self.endSession(id)
                    return
                }
                
                if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata, metadata.opcode == .close
                {
                    self.endSession(id)
                    return
                }
                
                if let data, !data.isEmpty
                {
                    self.handleMessage(data, sessionID: id)
                }
                
                guard self.sessions[id] != nil else { return }
                self.receiveNextMessage(on: connection, id: id)
            }
        }
    }
    
    func handleMessage(_ data: Data, sessionID id: ObjectIdentifier)
    {
        guard let session = self.sessions[id],
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        
        session.lastMessageDate = Date()
        
        if let type = message["t"] as? String, type == "join"
        {
            self.join(session, id: id, token: message["k"] as? String)
        }
        else if let mask = message["m"] as? Int, let controller = session.controller
        {
            // Bit 15 is reserved; ignore it and anything above 16 bits.
            controller.update(buttonMask: UInt16(truncatingIfNeeded: mask) & 0x7FFF)
        }
    }
    
    func join(_ session: Session, id: ObjectIdentifier, token: String?)
    {
        guard session.controller == nil else { return }
        
        guard let token, !token.isEmpty, token == self.token else {
            self.refuse(session, id: id, type: "denied")
            return
        }
        
        let usedSlots = Set(self.slots.values)
        guard let slot = (0 ..< PhoneControllerServer.maximumPlayers).first(where: { !usedSlots.contains($0) }) else {
            self.refuse(session, id: id, type: "full")
            return
        }
        
        let controller = PhoneGameController(name: String(format: NSLocalizedString("Phone %@", comment: ""), "P\(slot + 1)"))
        session.controller = controller
        self.slots[id] = slot
        
        ExternalGameControllerManager.shared.connect(controller)
        
        self.send(["t": "hello", "slot": slot], on: session.connection)
        self.updatePlayers()
    }
    
    func refuse(_ session: Session, id: ObjectIdentifier, type: String)
    {
        self.send(["t": type], on: session.connection) { [weak self] in
            DispatchQueue.main.async {
                self?.endSession(id)
            }
        }
    }
    
    func endSession(_ id: ObjectIdentifier)
    {
        guard let session = self.sessions.removeValue(forKey: id) else { return }
        self.slots[id] = nil
        
        if let controller = session.controller
        {
            controller.releaseAllInputs()
            ExternalGameControllerManager.shared.disconnect(controller)
        }
        
        session.connection.stateUpdateHandler = nil
        session.connection.cancel()
        
        self.updatePlayers()
    }
    
    func releaseQuietPhones()
    {
        let now = Date()
        
        for session in self.sessions.values
        {
            guard let controller = session.controller, controller.buttonMask != 0 else { continue }
            guard now.timeIntervalSince(session.lastMessageDate) > PhoneControllerServer.quietTimeout else { continue }
            
            controller.releaseAllInputs()
        }
    }
    
    func send(_ message: [String: Any], on connection: NWConnection, completion: (() -> Void)? = nil)
    {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in
            completion?()
        })
    }
    
    func updatePlayers()
    {
        self.players = self.sessions.compactMap { id, session in
            guard let controller = session.controller, let slot = self.slots[id] else { return nil }
            return Player(id: id, slot: slot, name: controller.name)
        }
        .sorted { $0.slot < $1.slot }
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
