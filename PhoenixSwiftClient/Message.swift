//
//  Message.swift
//  PhoenixSwiftClient
//
//  Created by George Lee on 12/6/16.
//  Copyright © 2016 George Lee. All rights reserved.
//

import Foundation

public class Message {
  var topic: String
  var event: String
  var payload: Any?
  var ref: Int?
  
  init(topic: String, event: String, payload: Any?, ref: Int?) {
    self.topic = topic
    self.event = event
    self.payload = payload
    self.ref = ref
  }
  
  public func toJson() -> String {
    let json: [String: Any?] = [
      "topic": topic,
      "event": event,
      "ref": ref == nil ? nil : "\(ref!)",
      "payload": payload ?? nil
    ]
    
    guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: []),
      let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) else {
        print("Failed to convert jsonData to string")
        return ""
    }
    
    return jsonString
  }
}
