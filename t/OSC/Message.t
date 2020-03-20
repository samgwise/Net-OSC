#! /usr/bin/env per6
use v6;
use Test;

plan 25;

use-ok 'Net::OSC::Message';
use Net::OSC::Message;
use Net::OSC::Types;


#diag Net::OSC::Message.^methods.map({ $_.perl }).join: "\n";

my Net::OSC::Message $message;
lives-ok {
  $message .= new(
    :args<Hey 123 45.67>
  );
}, "Instantiate message";

# diag "OSC type map:\n" ~ $message.type-map.map({ $_.join(' => ') ~ "\n"});

is $message.args, <Hey 123 45.67>, "get args";

is $message.type-string, 'sid', "build type-string";

ok $message.args('xyz', -987, -65.43), "Add args to message";

is $message.args, <Hey 123 45.67 xyz -987 -65.43>, "get args post addition";

is $message.type-string, 'sidsid', "build type-string post addition";


# diag "package tests:";

my Buf $packed-message;
lives-ok  { $packed-message = $message.package; },                          "package message";

my Net::OSC::Message $post-pack-message;
lives-ok  { $post-pack-message .= unpackage($packed-message); },           "unpackage message";

is        $post-pack-message.path,         $message.path,         "post pack path";

for $post-pack-message.args.kv -> $k, $v {
  given $v -> $value {
    when $value ~~ Rat {
      ok        ($value > $message.args[$k]-0.1 and $value < $message.args[$k]+0.1),     "post pack Rat arg\[$k], $value ~=~ { $message.args[$k] }";
    }
    default {
      is        $value,                    $message.args[$k],     "post pack arg\[$k]";
    }
  }
}

is        $post-pack-message.type-string,  $message.type-string,  "post pack type-string";

#test 32bit mode
my Net::OSC::Message $message32;
lives-ok {
  $message32 .= new(
    :args<Hey 123 45.67>
    :is64bit(False)
  );
}, "Instantiate 32bit message";

is $message32.type-string, 'sif', "Rat is type f in 32bit message";

#
# Type wrapper tests
#

is osc-message(osc-str('Foo')).package.&osc-decode.args.head, 'Foo', "Round trip for OSCType OSCString";

is osc-message(osc-blob('Foo'.encode)).package.&osc-decode.args.head.decode, 'Foo', "Round trip for OSCType OSCBlob";

is osc-message(osc-int32(0xfffffff)).package.&osc-decode.args.head, 0xfffffff, "Round trip for OSCType OSCInt32";
is osc-message(osc-int64(0xffffffff_fffffff)).package.&osc-decode.args.head, 0xffffffff_fffffff, "Round trip for OSCType OSCInt64";

is osc-message(osc-float(22.2)).package.&osc-decode.args.head, 22.2, "Round trip for OSCType OSCFloat32";
is osc-message(osc-double(88888888.8)).package.&osc-decode.args.head, 88888888.8, "Round trip for OSCType OSCFloat64";