use v6;

unit role Net::OSC::Server;
use Net::OSC::Message;
use Net::OSC::Types;

has ActionTuple @!dispatcher;

#= Interface for examining actions for managing messages
multi method actions( --> Seq) {
  @!dispatcher.values
}

#= Add an action for managing messages
method add-action(Regex $path, Callable $action) {
  @!dispatcher.push: $($path, $action);
}

#= Add multiple actions for managing messsages
method add-actions(*@actions) {
  for @actions -> $action {
    die "Actions must be provided as a tuple of format: (Regex, Callable), recieved ({ $action.WHAT.perl })!" unless $action ~~ ActionTuple;
    @!dispatcher.push: $action;
  }
}

#= Send and OSC message
method send(OSCPath $path, *%args) {
  self.transmit-message(Net::OSC::Message.new(
    :$path
    :args( (%args<args>:exists and %args<args>.defined) ?? %args<args> !! () )
  ))
}

#= Dispatch a message to actions with an accepting path constraint
method !on-message-recieved(Net::OSC::Message $message) {
  for @!dispatcher -> $action {
    given $message.path {
      when $action[0] {
        $action[1]($message, $/)
      }
      default {
        next;
      }
    }
  }
}

#= Call the server's on-close method
method close() {
  self!on-close();
}

#= Start listening for OSC messages
method !listen() { ... }

#= Clean up listener and sender objects
method !on-close { ... }

#= Transmit an OSC message
multi method transmit-message(Net::OSC::Message:D $message) { ... }
