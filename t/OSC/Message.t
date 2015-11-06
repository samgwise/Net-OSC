use v6;
use Test;
use lib 'lib';
use Net::OSC::Message;

plan 11;

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


diag "package tests:";

is $message.pack-float32(12.375).perl, Buf.new(65, 70, 0, 0).perl, "pack 12.375";

my $packed-message;
lives-ok  { $packed-message = $message.package; },                          "package message";

my Net::OSC::Message $post-pack-message;
lives-ok  { $post-pack-message .= unpackage($message.package); },           "unpackage message";

is        $post-pack-message.path,         $post-pack-message.path,         "post pack path";

is        $post-pack-message.args,         $post-pack-message.args,         "post pack args";

is        $post-pack-message.type-string,  $post-pack-message.type-string,  "post pack path";
