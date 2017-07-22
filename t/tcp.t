#!/usr/bin/env perl6
use v6.c;
use Test;

plan 3;

use-ok 'Net::OSC::Transport::TCP';
use Net::OSC::Transport::TCP;

#use-ok 'Net::OSC::Message';
use Net::OSC::Message;

my Net::OSC::Message $t .= new(
  :path</a>
  :args(0, 2.3456789, 'abc')
  :is64bit(False)
);

{
  # promise that sends a message
  my $slip-sender = start {
    my $tcp-client = IO::Socket::INET.new(:host<127.0.0.1>, :port(55556));
    diag 'waiting to send....';
    sleep 0.5;
    send-slip($tcp-client, $t);
  };

  diag 'creating TCP listener...';
  my $tcp-server = IO::Socket::INET.new(:localhost<127.0.0.1>, :localport(55556), :listen(True));
  my $connection = $tcp-server.accept();
  my $m = recv-slip($connection);
  await $slip-sender;

  is $t.args[0], $m.args[0], "Slip TCP message matches presend message";
}

#sleep 0.5;

{
  # promise that sends a message
  my $lp-sender = start {
    my $tcp-client = IO::Socket::INET.new(:host<127.0.0.1>, :port(55555));
    diag 'waiting to send....';
    sleep 0.5;
    send-lp($tcp-client, $t);
  };

  diag 'creating TCP listener...';
  my $tcp-server = IO::Socket::INET.new(:localhost<127.0.0.1>, :localport(55555), :listen(True));
  my $connection = $tcp-server.accept();
  my $m = recv-lp($connection);
  await $lp-sender;

  is $t.args[0], $m.args[0], "Length-prefixed TCP message matches presend message";
}
