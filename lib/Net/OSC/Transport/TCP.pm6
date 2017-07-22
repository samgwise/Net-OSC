use v6;
unit module Net::OSC::Transport::TCP;
use Net::OSC::Message;

#
# When doing OSC over TCP, we have to do some sort of framing so that we can tell
# where one OSC packet ends and the next begins. There's many ways to do this
# framing, but the two methods below are commonly used.
#
# See http://forum.renoise.com/index.php/topic/43159-osc-via-tcp-has-no-framing
#

# Length-prefixed message framing
#
# This is used by SuperCollider.
#
sub send-lp(IO::Socket::INET $socket, Net::OSC::Message $message) is export {
  my Int $i = $message.package.elems;
  $socket.write(Buf.new(($i+>24) +& 0xFF, ($i+>16) +& 0xFF, ($i+>8) +& 0xFF, $i +& 0xFF));
  $socket.write($message.package);
}

sub recv-lp(IO::Socket::INET $socket --> Net::OSC::Message) is export {
  my Buf $p = $socket.read(4);
  my Buf $b = $socket.read(($p[0]+<24) +| ($p[1]+<16) +| ($p[2]+<8) +| $p[3]);
  Net::OSC::Message.unpackage($b)
}


# SLIP message framing
#
# see https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
#
# This is used by PureData.
#

sub send-slip(IO::Socket::INET $socket, Net::OSC::Message $message) is export {
  my @list = [];
  for $message.package.list {
    when 0xC0 { @list.append: 0xDB, 0xDC; }
    when 0xDB { @list.append: 0xDB, 0xDD; }
    default   { @list.append: $_; }
  }
  @list.append: 0xC0;
  $socket.write(Buf.new(@list));
}

sub recv-slip(IO::Socket::INET $socket --> Net::OSC::Message) is export {
  my @list = [];
  loop {
    given $socket.read(1)[0] {
      when 0xC0 { last; }
      when 0xDB {
        given $socket.read(1)[0] {
          when 0xDC { @list.append: 0xC0; }
          when 0xDD { @list.append: 0xDB; }
          default { die 'this should never happen'; }
        }
      }
      default { @list.append: $_; }
    }
  }
  Net::OSC::Message.unpackage(Buf.new(@list));
}
