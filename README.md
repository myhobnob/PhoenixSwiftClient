Phoenix Swift Client
--------------------

A Swift library for communicating with Phoenix Channels. Based on the latest
version of the Javascript library :rocket:

Installation
------------------

## CocoaPods

Add `PhoenixSwiftClient` to your Podfile. Note that this library only supports
iOS 9.0 and higher.

## Git Submodule

Fetch the library from Git and add `PhoenixSwiftClient.xcodeproj` to your XCode
project. Then, in your project's settings, add `PhoenixSwiftClient.framework`
under General -> Embedded Binaries.

Usage
-----------------------

PhoenixSwiftClient is based on the current Phoenix 1.2.1 JS client, so the
patterns are largely the same. There is also a sample project set up
`PhoenixSwiftClientExample` folder.

First import the library.

```
import PhoenixSwiftClient
```

## Sockets

To create a socket connection, create an URL object with the URL string you
want to connect to.

```
let url = URL(string: "ws://localhost:4000/socket")
conn = Socket(endpointUrl: url!, options: [:])
conn.connect()
```

If your Phoenix channels endpoint requires parameters (i.e. for authentication),
you may pass that in through the `options` parameter.

```
let params = ["join": "params"]
conn = Socket(endpointUrl: url!, options: ["params": params])
```

## Socket Hooks

You may hook into lifecycle events such as `onError` and `onClose` from the
socket.

```
socket.onError(callback: { (error: Error) -> () in
  print("Error")
})
```


## Channels

Once you have a socket, you can start listening on channels. To connect to the
channel, you must provide the topic to subscribe to along with any necessary
parameters.

```
channel = connection.channel(topic: "room:lobby", chanParams: ["foo": "bar"])
channel.join(timeout: nil)
```

Once you have a Channel object, you may start listening or pushing events.

```
channel.on(event: "ping", callback: { (payload: Any?, ref: Int?) -> () in
  print("got ping!")
})

channel.push(event: "pong", payload: ["foo": "bar"], timeout: nil)?.receive(status: "ok", callback: { (payload: [String: AnyObject]?) -> () in
  print("Received reply")
})
```

## Presence

The Presence object provides features for syncing presence information from the
server. Use `syncState` and `syncDiff` to process incoming events.
