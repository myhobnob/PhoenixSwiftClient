//
//  Channel.swift
//  PhoenixSwiftClient
//
//  Created by George Lee on 12/5/16.
//  Copyright © 2016 George Lee. All rights reserved.
//

import Foundation

let CHANNEL_EVENTS = [
  "close": "phx_close",
  "error": "phx_error",
  "join": "phx_join",
  "reply": "phx_reply",
  "leave": "phx_leave"
]

let IGNORED_EVENTS = [
  "phx_close",
  "phx_error",
  "phx_leave",
  "phx_join"
]

enum ChannelState {
  case closed
  case errored
  case joined
  case joining
  case leaving
}

public class Channel {
  weak var socket: Socket?
  var state: ChannelState = ChannelState.closed
  var topic: String
  var params: Any?
  var bindings: [(event: String, callback: (_: Any, _: NSInteger?) -> ())] = []
  var timeout: NSInteger
  var joinedOnce = false
  var pushBuffer: [Push] = []
  var joinPush: Push? = nil
  var rejoinTimer: ConnectionTimer?
  
  init(topic: String, params: Any?, socket: Socket) {
    self.topic = topic
    self.params = params
    self.socket = socket
    timeout = socket.timeout
    
    // Set up join message and timers.
    joinPush = Push(channel: self, event: CHANNEL_EVENTS["join"]!, payload: params, timeout: timeout)
    joinPush!.receive(status: "ok", callback: { (_: Any?) -> () in
      self.state = ChannelState.joined
      self.rejoinTimer?.reset()
      self.pushBuffer.forEach { $0.send() }
      self.pushBuffer.removeAll()
    })
    
    joinPush!.receive(status: "timeout", callback: { (_: Any?) -> () in
      //      self.socket.log("channel", "timeout \(topic)", joinPush.timeout)
      self.state = ChannelState.errored
      self.rejoinTimer = self.scheduleRejoinTimer()
    })

    // Set up channel state callbacks and replies
    on(event: CHANNEL_EVENTS["reply"]!, callback: { (payload: Any?, ref: Int?) in
      let message = Message(topic: self.topic, event: self.replyEventName(ref: ref), payload: payload, ref: ref)
      self.trigger(message: message)
    })

    onClose(callback: { (_: Any?, _: Int?) -> () in
      self.rejoinTimer?.reset()
      //      self.socket.log("channel", "close \(topic) \(joinRef())")
      self.state = ChannelState.closed
      self.socket?.remove(channel: self)
    })
    
    onError(callback: { (reason: Any?, _: NSInteger?) -> () in
      self.rejoinTimer?.reset()
      //      self.socket.log("channel", "error \(topic)", reason)
      self.state = ChannelState.errored
      self.rejoinTimer = self.scheduleRejoinTimer()
    })
  }
  
  deinit {
    rejoinTimer?.reset()
  }

  private func scheduleRejoinTimer() -> ConnectionTimer? {
    if socket == nil {
      return nil
    }

    let timer = ConnectionTimer(callback: self.rejoinUntilConnected, timerCalc: socket!.reconnectAfterMs)
    timer.scheduleTimeout()
    return timer
  }
  
  @objc private func rejoinUntilConnected () {
    rejoinTimer?.reset()
    rejoinTimer = scheduleRejoinTimer()
    
    if (socket != nil && socket!.isConnected()) {
      rejoin(timeout: nil)
    }
  }
  
  public func join(timeout: NSInteger?) -> Push? {
    if (joinedOnce) {
      // TODO: Throw error
      return nil
    }
    
    joinedOnce = true
    rejoin(timeout: timeout ?? self.timeout)
    
    return joinPush
  }
  
  public func onClose(callback: @escaping (_: Any?, _: NSInteger?) -> ()) {
    on(event: CHANNEL_EVENTS["close"]!, callback: callback)
  }
  
  public func onError(callback: @escaping (_: Any?, _: Int?) -> ()) {
    on(event: CHANNEL_EVENTS["error"]!, callback: callback)
  }
  
  public func on(event: String, callback: @escaping (_: Any?, _: NSInteger?) -> ()) {
    bindings.append((event: event, callback: callback))
  }
  
  public func off(event: String) {
    bindings = bindings.filter { $0.event != event }
  }
  
  private func canPush() -> Bool {
    return socket != nil && socket!.isConnected() && isJoined()
  }
  
  public func push(event: String, payload: Any?, timeout: NSInteger? = nil) -> Push? {
    if(!joinedOnce) {
      // Throw error
      return nil
    }
    
    let pushEvent = Push(channel: self, event: event, payload: payload, timeout: timeout ?? self.timeout)
    
    if canPush() {
      pushEvent.send()
    } else {
      pushEvent.startTimeout()
      pushBuffer.append(pushEvent)
    }
    
    return pushEvent
  }
  
  public func leave(timeout: NSInteger? = nil) -> Push {
    func closeCallback (_: Any?) {
//      self.socket.log("channel", "leave \(topic)")
      let message = Message(topic: topic, event: CHANNEL_EVENTS["close"]!, payload: "leave", ref: joinRef()!)
      self.trigger(message: message)
    }

    state = ChannelState.leaving
    let leavePush = Push(channel: self, event: CHANNEL_EVENTS["leave"]!, payload: [:], timeout: timeout ?? self.timeout)
    leavePush.receive(status: "ok", callback: closeCallback).receive(status: "timeout", callback: closeCallback)
    leavePush.send()
    
    if !canPush() {
      leavePush.trigger(status: "ok", response: [:])
    }
    
    return leavePush
  }

  // TODO: JS library allows this to be overridden somehow.
  public func onMessage(event: String, payload: Any? = nil, ref: NSInteger? = nil) -> Any? {
    return payload
  }
  
  public func isMember(topic: String) -> Bool{
    return self.topic == topic
  }
  
  public func joinRef() -> NSInteger? {
    return joinPush?.ref
  }
  
  private func sendJoin(timeout: NSInteger) {
    state = ChannelState.joining
    joinPush!.resend(timeout: timeout)
  }
  
  private func rejoin(timeout: NSInteger?) {
    if isLeaving() {
      return
    }
    
    sendJoin(timeout: timeout ?? self.timeout)
  }
  
  public func trigger(message: Message) {
    let ref = message.ref
    let event = message.event
    if ref != nil && IGNORED_EVENTS.contains(event) && ref! != joinRef()! {
      return
    }
    
    let handledPayload = onMessage(event: event, payload: message.payload, ref: ref)
    if message.payload != nil && handledPayload == nil {
      // TODO: Throw error
      // Would happen if onMessage were overridden
      return
    }
    
    bindings.filter({ $0.event == event }).forEach { $0.callback(handledPayload ?? [:], ref) }
  }
  
  public func replyEventName(ref: NSInteger?) -> String {
    if ref == nil {
      return ""
    }
    
    return "chan_reply_\(ref!)"
  }
  
  public func isClosed() -> Bool {
    return state == ChannelState.closed
  }
  
  public func isErrored() -> Bool {
    return state == ChannelState.errored
  }
  
  public func isJoined() -> Bool {
    return state == ChannelState.joined
  }
  
  public func isJoining() -> Bool {
    return state == ChannelState.joining
  }
  
  public func isLeaving() -> Bool {
    return state == ChannelState.leaving
  }
}



































