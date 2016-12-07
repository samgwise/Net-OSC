use v6;
use Net::OSC::Server;

unit class Net::OSC::Server::UDP does Net::OSC::Server;
use Net::OSC::Message;
use Net::OSC::Types;

has IO::Socket::Async $!udp-listener;
has Tap               $!listener;
has IO::Socket::Async $!udp-sender;
has Str               $.listening-address;
has Int               $.listening-port;
has Str               $.send-to-address is rw;
has Int               $.send-to-port is rw;

submethod BUILD(:$!listening-address, :$!listening-port, :$!send-to-address, :$!send-to-port, :@actions) {
  self.add-actions(@actions);
  self!listen;
}

#= Send a UDP message to a specific host and port
method send(OSCPath $path, *%args) {
  if %args<address>:exists or %args<port>:exists {
    self.transmit-message(
      Net::OSC::Message.new(
        :$path
        :args( (%args<args>:exists and %args<args>.defined) ?? %args<args> !! () )
      ),
      (%args<address>:exists ?? %args<address> !! $!send-to-address),
      (%args<port>:exists    ?? %args<port>    !! $!send-to-port)
    )
  }
  else {
    self.transmit-message(
      Net::OSC::Message.new(
        :$path
        :args( (%args<args>:exists and %args<args>.defined) ?? %args<args> !! () )
      )
    )
  }
}

#= Start listening for OSC messages
method !listen() {
  $!udp-listener  .= bind-udp($!listening-address, $!listening-port);
  $!udp-sender    .= udp;

  $!listener = $!udp-listener.Supply(:bin).grep( *.elems > 0 ).tap: -> $buf {
    self!on-message-recieved: Net::OSC::Message.unpackage($buf)
  }
}

#= Clean up listener and sender objects
method !on-close {
  $!listener.close;
}

#= Transmit an OSC message
multi method transmit-message(Net::OSC::Message:D $message) {
  await $!udp-sender.write-to($!send-to-address, $!send-to-port, $message.package);
}
multi method transmit-message(Net::OSC::Message:D $message, Str $address, Int $port) {
  await $!udp-sender.write-to($address, $port, $message.package);
}
