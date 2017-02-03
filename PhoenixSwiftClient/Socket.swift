//
//  Socket.swift
//  PhoenixSwiftClient
//
//  Created by George Lee on 12/5/16.
//  Copyright © 2016 George Lee. All rights reserved.
//

import Foundation
import Starscream

var DEFAULT_TIMEOUT = 10000
var DEFAULT_HEARTBEAT_INTERVAL = 30000

public class Socket: WebSocketDelegate {
  var conn: WebSocket?
  var openCallbacks: [() -> ()] = []
  var closeCallbacks: [() -> ()] = []
  var errorCallbacks: [(_: NSError?) -> ()] = []
  var messageCallbacks: [(_: Any?) -> ()] = []
  var channels: [Channel] = []
  var sendBuffer: [() -> ()] = []
  var ref = 0
  var timeout: Int
  var heartbeatIntervalMs: Int
  var params: [String: AnyObject]
  var endpoint: URL
  var heartbeatTimer = Timer()
  var reconnectTimer: ConnectionTimer?

  public init(endpointUrl: URL, options: [String: Any?]) {
    NSLog("socket init!!!!!!!!!")
    timeout = options["timeout"] as? Int ?? DEFAULT_TIMEOUT
    heartbeatIntervalMs = options["heartbeatIntervalMs"] as? Int ?? DEFAULT_HEARTBEAT_INTERVAL
    // TODO: Allow  reconnectAfterMs as parameter? Think it'd just be better to take options as a Swift object.

    params = options["params"] as? [String: AnyObject] ?? [:]
    let queryParams = params.map({ (key: String, value: AnyObject) in
      return URLQueryItem(name: key, value: value as? String)
    })

    var urlComponents = URLComponents.init(
      url: endpointUrl.appendingPathComponent("websocket"),
      resolvingAgainstBaseURL: true
    )

    urlComponents?.queryItems = queryParams

    endpoint = urlComponents!.url!
    
    reconnectTimer = ConnectionTimer(callback: {[unowned self] in
      NSLog("Reconnect timer running!!!!!!!!!!!!!!!!")
      self.disconnect(callback: {[unowned self] in
        self.connect()
        }, code: 0)
    }, timerCalc: self.reconnectAfterMs)
  }


  internal func reconnectAfterMs(tries: Int) -> Int {
    print("Socket reconnectAfterMs running on tries \(tries)")
    if tries < 4 {
        return [1000, 2000, 5000, 10000][tries]
    } else {
        return 10000
    }
  }

  @objc public func disconnect (callback: (() -> ())?, code: NSInteger) {
    if let conn = self.conn {
      conn.disconnect(forceTimeout: nil, closeCode: UInt16(code))
      self.conn = nil
    }
    self.heartbeatTimer.invalidate()

    callback?()
  }
  
  @objc public func close() {
    self.disconnect(callback: nil, code: 0)
    self.reconnectTimer?.reset()
    self.reconnectTimer = nil
  }

  @objc public func connect () {
    if self.conn != nil {
      return
    }

    NSLog("Socket Connecting to websocket")
    // Set the reconnect timers. If we don't finish connecting before then, then we will reconnect
    setReconnectTimers()
    conn = WebSocket(url: endpoint.absoluteURL)
    if let connection = self.conn {
      connection.delegate = self
      connection.connect()
    }
  }

  // TODO: Implement overridable logger. Maybe as a delegate method?

  public func onOpen(callback: @escaping () -> ()) {
    openCallbacks.append(callback)
  }

  public func onClose(callback: @escaping () -> ()) {
    closeCallbacks.append(callback)
  }

  public func onError(callback: @escaping (_: NSError?) -> ()) {
    errorCallbacks.append(callback)
  }

  public func onMessage(callback: @escaping (_: Any?) -> ()) {
    messageCallbacks.append(callback)
  }

  public func websocketDidConnect(socket: WebSocket) {
    NSLog("Socket websocketDidConnect!!!!!!!!!!!!")
    flushSendBuffer()
    reconnectTimer?.reset()

    heartbeatTimer.invalidate()
    heartbeatTimer = Timer.scheduledTimer(timeInterval: Double(heartbeatIntervalMs / 1000), target: self, selector: #selector(sendHeartbeat), userInfo: nil, repeats: true)

    DispatchQueue.main.asyncAfter(deadline: .now()) {
      self.openCallbacks.forEach { $0() }
    }
  }

  // Unlike the JS library, there is no callback if the socket fails to connect
  public func setReconnectTimers () {
    heartbeatTimer.invalidate()

    reconnectTimer!.scheduleTimeout()
  }

  public func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
    print("Disconnected!")
    triggerChanError(error)
    setReconnectTimers()

    if error != nil {
      print("Websocket Disconnected with error: \(error?.localizedDescription)")
      DispatchQueue.main.asyncAfter(deadline: .now()) {
        self.errorCallbacks.forEach { $0(error) }
      }
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now()) {
        self.closeCallbacks.forEach { $0() }
      }
    }
  }

  public func websocketDidReceiveMessage(socket: WebSocket, text: String) {
    guard let data = text.data(using: String.Encoding.utf8),
      let json = try? JSONSerialization.jsonObject(with: data, options: []),
      let jsonObject = json as? [String: AnyObject] else {
        print("Unable to parse JSON: \(text)")
        return
    }

    guard let topic = jsonObject["topic"] as? String, let event = jsonObject["event"] as? String,
      let msg = jsonObject["payload"] as? [String: AnyObject] else {
        print("No Phoenix message: \(text)")
        return
    }

    let refString = jsonObject["ref"] as? String
    let incomingRef = refString == nil ? nil : Int(refString!)

    let message = Message(topic: topic, event: event, payload: msg, ref: incomingRef)
    print("Received message for topic: \(topic)")
    print("Raw payload: \(text)")
//    print("Parsed payload: \(message.toJson())")

    // Notify channels about message
    self.channels.filter({ $0.isMember(topic: topic) }).forEach({ $0.trigger(message: message) })
  }

  public func websocketDidReceiveData(socket: WebSocket, data: Data) {
    // Apparently not sent by Phoenix
    print("Received data instead of string", data)
  }

  internal func triggerChanError(_ error: NSError?) {
    channels.forEach({
      $0.trigger(message: Message(topic: $0.topic, event: "phx_error", payload: error, ref: nil))
    })
  }

  public func isConnected() -> Bool {
    return conn != nil && conn!.isConnected
  }

  public func remove(channel: Channel) {
    channels = channels.filter({ $0.joinRef() != channel.joinRef() })
  }

  public func channel(topic: String, chanParams: [String: Any] = [:]) -> Channel {
    let chan = Channel(topic: topic, params: chanParams, socket: self)
    channels.append(chan)
    return chan
  }

  public func push(message: Message) {
    let callback = {[weak self, weak message] in
      if let m = message {
        self?.conn!.write(string: m.toJson())
      }
    }

    // TODO: Implement logger
    if isConnected() {
      callback()
    } else {
      sendBuffer.append(callback)
    }
  }

  internal func makeRef() -> Int {
    let newRef = ref + 1
    if (newRef == ref) {
      ref = 0
    } else {
      ref = newRef
    }

    return ref
  }

  @objc private func sendHeartbeat (_: Timer) {
    if self.isConnected() {
      self.push(message: Message(topic: "phoenix", event: "heartbeat", payload: [:], ref: makeRef()))
    }
  }

  private func flushSendBuffer() {
    if isConnected() && !sendBuffer.isEmpty {
      sendBuffer.forEach({ $0() })
      sendBuffer.removeAll()
    }
  }
}
