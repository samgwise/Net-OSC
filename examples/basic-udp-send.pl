#! /usr/bin/env perl6
use v6;
use Net::OSC::Message;

my $udp-sender = IO::Socket::Async.udp;

my Net::OSC::Message $message .= new( :args<Hey 123 45.67> );
my $sending = $udp-sender.write-to('localhost', 7654, $message.package);
await $sending;
