use v6;
use Test;
use lib 'lib';
use Net::OSC;

plan 1;

lives-ok {  }, "use Net::OSC";
