use v6;
use Test;
use lib 'lib';
use Net::OSC::Message;

plan 6;

#diag Net::OSC::Message.^methods.map({ $_.perl }).join: "\n";

my Net::OSC::Message $message;
lives-ok {
  $message .= new(
    :args<Hey 123 45.67>
  );
}, "Instantiate message";

diag "OSC type map:\n" ~ $message.type-map.map({ $_.join(' => ') ~ "\n"});

is $message.args, <Hey 123 45.67>, "get args";

is $message.type-string, 'sid', "build type-string";

ok $message.args('xyz', 987, 65.43), "Add args to message";

is $message.args, <Hey 123 45.67 xyz 987 65.43>, "get args post addition";

is $message.type-string, 'sidsid', "build type-string post addition";
