//
//  Message.swift
//  PhoenixSwiftClient
//
//  Created by George Lee on 12/6/16.
//  Copyright © 2016 George Lee. All rights reserved.
//

import Foundation

public class Response {
  var status: String
  var response: [String: AnyObject]?
  
  init(payload: [String: Any]) {
    status = payload["status"] as? String ?? "error"
    response = payload["response"] as? [String: AnyObject]
  }
}
