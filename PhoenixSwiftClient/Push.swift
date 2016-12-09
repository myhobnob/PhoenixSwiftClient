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
  var bindings: [String] = []
  var channel: Channel
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
    
    startTimeout()
    sent = true
    let message = Message(topic: channel.topic, event: event, payload: payload, ref: ref!)
    channel.socket.push(message: message)
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
    if let event = self.refEvent {
      channel.off(event: event)
    }
  }
  
  internal func cancelTimeout () {
    if let timer = timeoutTimer {
      timer.invalidate()
      timeoutTimer = nil
    }
  }
  
  internal func startTimeout () {
    if timeoutTimer != nil {
      return
    }
    
    func handlePayload(incomingPayload: Any?, _: Int?) {
      cancelRefEvent()
      cancelTimeout()
      
      let response = Response(payload: incomingPayload as! [String: AnyObject])
      receivedResp = response
      matchReceive(status: response.status, response: response.response)
    }
    
    ref = channel.socket.makeRef()
    refEvent = channel.replyEventName(ref: ref)
    channel.on(event: refEvent!, callback: handlePayload)
    
    timeoutTimer = Timer.scheduledTimer(timeInterval: Double(timeout) / 1000, target: self, selector: #selector(handleTimeout), userInfo: nil, repeats: false)
  }
  
  private func hasReceived(status: String) -> Bool {
    return receivedResp != nil && receivedResp!.status == status
  }
  
  @objc func handleTimeout(_:Timer) {
    trigger(status: "timeout", response: [:])
  }
  
  internal func trigger(status: String, response: Any?) {
    let payload = ["status": status, "response": response]
    let message = Message(topic: channel.topic, event: refEvent!, payload: payload, ref: nil)
    channel.trigger(message: message)
  }
}
