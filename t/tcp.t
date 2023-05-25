#!/usr/bin/env perl6
use v6.c;
use Test;

plan 11;

use-ok 'Net::OSC::Transport::TCP';
use Net::OSC::Transport::TCP;

#use-ok 'Net::OSC::Message';
use Net::OSC::Message;

my Net::OSC::Message $t .= new(
  :path</a>
  :args(0, 2.5, 'abc')
  :is64bit(False)
);

use Test::Util::ServerPort;

my $slip-test = start {
  my $port = get-unused-port();
  my $server = IO::Socket::INET.new(:localhost<127.0.0.1>, :localport($port), :listen(True));
  ok $server, 'Created server';
  my $client = IO::Socket::INET.new(:host<127.0.0.1>, :port($port));
  ok $client, 'Created client';
  send-slip($client, $t); # maybe we should catch an exception here?
  my $connection = $server.accept();
  ok $connection, 'Server accepted connection';
  my $m = recv-slip($connection);

  is $t.args, $m.args, 'Received message matches sent message';

  CATCH { warn .Str }
};
await Promise.anyof($slip-test, Promise.in(1).then({ flunk "FAILURE: Timed out!"; }));
ok $slip-test, 'Passing an OSC message with SLIP+TCP worked.';

my $lp-test = start {
  my $port = get-unused-port();
  my $server = IO::Socket::INET.new(:localhost<127.0.0.1>, :localport($port), :listen(True));
  ok $server, 'Created server';
  my $client = IO::Socket::INET.new(:host<127.0.0.1>, :port($port));
  ok $client, 'Created client';
  send-lp($client, $t); # maybe we should catch an exception here?
  my $connection = $server.accept();
  ok $connection, 'Server accepted connection';
  my $m = recv-lp($connection);

  is $t.args, $m.args, 'Received message matches sent message';

  CATCH { warn .Str }
};
await Promise.anyof($lp-test, Promise.in(1).then({ flunk "FAILURE: Timed out!"; }));
ok $lp-test, 'Passing an OSC message with LP+TCP worked.';
