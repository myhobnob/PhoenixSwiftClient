//
//  ViewController.swift
//  PhoenixSwiftClientExample
//
//  Created by George Lee on 12/5/16.
//  Copyright © 2016 George Lee. All rights reserved.
//

import UIKit
import PhoenixSwiftClient

class ViewController: UIViewController {
  var conn: Socket?
  var channel: Channel?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    let url = URL(string: "ws://localhost:4000/socket")
    let params = ["join": "params"]
    conn = Socket(endpointUrl: url!, options: ["params": params])
    
    if let connection = self.conn {
      connection.connect()
      channel = connection.channel(topic: "room:lobby", chanParams: ["foo": "bar"])
      
      if let chan = self.channel {
        chan.join(timeout: nil)?.receive(status: "ok", callback: { (_: Any?) -> () in
          print("joined")
          
          chan.push(event: "ping", payload: ["baz": "quux"], timeout: nil)?.receive(status: "ok", callback: { (payload: [String: AnyObject]?) -> () in
            print("payload is", payload!["baz"]!)
          })
        })
      }
    }
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
}
