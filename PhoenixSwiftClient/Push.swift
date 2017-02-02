//
//  Push.swift
//  PhoenixSwiftClient
//
//  Created by George Lee on 12/5/16.
//  Copyright © 2016 George Lee. All rights reserved.
//

import Foundation

typealias RecHook = (status: String, callback: ([String: AnyObject]?) -> ())

public class Push {
  weak var channel: Channel?
  var bindings: [String] = []
  var event: String
  var payload: Any?
  var timeout: Int
  var timeoutTimer: Timer? = Timer()
  var recHooks: [RecHook] = []
  var sent = false
  var ref: Int?
  var refEvent: String?
  var receivedResp: Response?

  init(channel: Channel, event: String, payload: Any?, timeout: Int) {
    self.channel = channel
    self.event = event
    self.payload = payload
    self.timeout = timeout
  }

  deinit {
    timeoutTimer?.invalidate()
    timeoutTimer = nil
    receivedResp = nil
    channel = nil
  }

  internal func resend(timeout: Int) {
    self.timeout = timeout
    cancelRefEvent()
    ref = nil
    self.refEvent = nil
    self.receivedResp = nil
    sent = false
    send()
  }

  public func send() {
    if (hasReceived(status: "timeout")) {
      return
    }

    if let chan = channel {
      startTimeout()
      sent = true
      let message = Message(topic: chan.topic, event: event, payload: payload, ref: ref)
      print("-------- PHOENIX WEBSOCKET REQUEST ---------")
      print("Sending messsage to topic: \(chan.topic)")
      print("Payload: \(message.toJson())")
      chan.socket?.push(message: message)
    }
  }

  public func receive(status: String, callback: @escaping ([String: AnyObject]?) -> ()) -> Push {
    if hasReceived(status: status) {
      callback(receivedResp!.response)
    }

    recHooks.append(RecHook(status: status, callback: callback))
    return self
  }

  private func matchReceive(status: String, response: [String: AnyObject]?) {
    recHooks.filter({ $0.status == status }).forEach { $0.callback(response) }
  }

  private func cancelRefEvent() {
    if let event = refEvent, let chan = channel {
      chan.off(event: event)
    }
  }

  internal func cancelTimeout () {
    if let timer = timeoutTimer {
      timer.invalidate()
    }
  }

  internal func startTimeout () {
    if timeoutTimer != nil && timeoutTimer!.isValid {
      return
    }

    let handlePayload = {[weak self] (incomingPayload: Any?, _: Int?) in
      if let push = self {
        push.cancelRefEvent()
        push.cancelTimeout()

        let response = Response(payload: incomingPayload as! [String: AnyObject])
        push.receivedResp = response
        push.matchReceive(status: response.status, response: response.response)
      }
    }

    if let chan = channel, let socket = chan.socket {
      ref = socket.makeRef()
      refEvent = chan.replyEventName(ref: ref)
      chan.on(event: refEvent!, callback: handlePayload)

      timeoutTimer = Timer.scheduledTimer(timeInterval: Double(timeout) / 1000, target: self, selector: #selector(handleTimeout), userInfo: nil, repeats: false)
    }
  }

  private func hasReceived(status: String) -> Bool {
    return receivedResp != nil && receivedResp!.status == status
  }

  @objc func handleTimeout(_:Timer) {
    trigger(status: "timeout", response: [:])
  }

  internal func trigger(status: String, response: Any?) {
    if let chan = channel, let event = refEvent {
      let payload = ["status": status, "response": response]
      let message = Message(topic: chan.topic, event: event, payload: payload, ref: nil)
      chan.trigger(message: message)
    }
  }
}
