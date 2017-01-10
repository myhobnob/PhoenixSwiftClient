//
//  ConnectionTimer.swift
//  PhoenixSwiftClient
//
//  Created by George Lee on 12/7/16.
//  Copyright © 2016 George Lee. All rights reserved.
//

import Foundation

public class ConnectionTimer {
  typealias TimerFunction = (_: Int) -> Int
  var callback: () -> ()
  var timerCalc: TimerFunction
  var timer = Timer()
  var tries = 0
  
  init(callback: @escaping () -> (), timerCalc: @escaping TimerFunction) {
    self.callback = callback
    self.timerCalc = timerCalc
  }
  
  public func reset() {
    tries = 0
    timer.invalidate()
  }
  
  public func scheduleTimeout() {
    timer.invalidate()
    timer = Timer.scheduledTimer(timeInterval: Double(timerCalc(tries) / 1000), target: self, selector: #selector(handleTimeout), userInfo: nil, repeats: false)
  }
  
  @objc public func handleTimeout(_: Timer) {
    self.tries += 1
    callback()
  }
}
