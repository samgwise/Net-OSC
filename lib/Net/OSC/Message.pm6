use v6;

unit class Net::OSC::Message;
use Net::OSC::Types;

=begin pod

=head1 NAME

Net::OSC::Message - Implements OSC message packing and unpacking

=head1 METHODS

=begin code
method new(:$path = '/', :@args, :$!is64bit = True)
=end code
Set :is64bit to false to force messages to be packed to 32bit types
 this option may be required to talk to some versions of Max and other old OSC implementations.

=end pod

use Numeric::Pack :ALL;

constant width32 = 4;
constant width64 = 8;

my %type-map32 =
  Int.^name,    'i',
  IntStr.^name, 'i',
  Num.^name,    'f',
  Rat.^name,    'f',
  RatStr.^name, 'f',
  FatRat.^name, 'f',
  Str.^name,    's',
  Blob.^name,   'b',
  Buf.^name,    'b',
  |%Net::OSC::Types::osc-wrapper-type-map,
;
my %type-map64 =
  Int.^name,    'i',
  IntStr.^name, 'i',
  Num.^name,    'd',
  Rat.^name,    'd',
  RatStr.^name, 'd',
  FatRat.^name, 'd',
  Str.^name,    's',
  Blob.^name,   'b',
  Buf.^name,    'b',
  |%Net::OSC::Types::osc-wrapper-type-map,
;

has OSCPath $.path        = '/';
has Str     @!type-list;
has         @!args;
has Bool    $.is64bit    = True;

submethod BUILD(:@!args, :$!path = '/', :$!is64bit = True) {
   self!update-type-list(@!args);
}

#
# Constructor functions
#
sub osc-message(*@args --> Net::OSC::Message) is export {
    #= Function for creating a new OSC Message.
    #= The list of arguments is infered according to the 32bit type map, since it is the most widely accepted.
    #= To define specific types (such as Doubles and Longs) use OSCType wrappers from Net::OSC::Types.
    Net::OSC::Message.new(:@args)
}

sub osc-decode(Blob:D $buffer --> Net::OSC::Message) is export {
    #= Function for unpacking an OSC message.
    #= Accepts a defined buffer and returns an Net::OSC::Message.
    #= Decoding errors are thrown as exceptions.
    Net::OSC::Message.unpackage($buffer)
}

method type-string() returns Str
#= Returns the current type string of this messages content.
#= See OSC types for possible values.
{
  return @!type-list.join: '' if @!type-list.elems > 0;
  ''
}

method pick-osc-type($arg) returns Str
#= Returns the character representing the OSC type $arg would be packed as
#=  by this Message object.
#= If the argument is held in a wrapper from Net::OSC::Types then the wrapper's type will be used.
#= Otherwise the type picker will try and infer a type according to the 32bit or 64 bit type map.
{
  #say "Choosing type for $arg of type {$arg.WHAT.perl}";
  my $type-map = $!is64bit ?? %type-map64 !! %type-map32;
  if $arg.WHAT.perl ~~ $type-map {
    return $type-map{$arg.WHAT.perl};
  }
  else {
    die "Unable to map { try { $arg.Str } // $arg.gist } of type { $arg.WHAT.perl } to OSC type!";
  }
}

method !update-type-list(*@args){
  for @args -> $arg {
    @!type-list.push: self.pick-osc-type($arg);
  }
}

method args(*@new-args) returns Seq
#= Adds any arguments as args to the object and returns the current message arguments.
#= The OSC type of the argument will be determined according the the current OSC types map.
{
  if @new-args {
    @!args.push(|@new-args);
    self!update-type-list(|@new-args);
  }

  gather for @!args -> $arg {
    take $arg;
  }
}

method set-args(*@new-args)
#= Clears the message args lists and sets it to the arguments provided.
#= The OSC type of the argument will be determined according the the current OSC types map.
{
  @!args = ();
  @!type-list = ();
  self.args(@new-args) if @new-args;
}

method type-map() returns Seq
#= Returns the current OSC type map of the message.
#= This will change depending on the is64bit flag.
{
  ($!is64bit ?? %type-map64 !! %type-map32).pairs;
}

method package() returns Blob
#= Returns a Buf of the packed OSC message.
#= See unpackage to turn a Buf into a Message object.
{
    self.pack-string($!path)
    ~ self.pack-string(",{ self.type-string() }")
    ~ self!pack-args();
}

method !pack-args() returns Buf
#= Map OSC arg types to a packing routine
{
  return Buf.new unless @!args.elems > 0;

  Buf.new( (gather for @!args Z @!type-list -> ($arg, $type) {
    #say "Packing '$arg' of OSC type '$type' with pattern '%pack-map{$type}'";

    given $type {
      when 'f' {
        take pack-float($arg.Rat, :byte-order(big-endian));
      }
      when 'd' {
        take pack-double($arg.Rat, :byte-order(big-endian));
      }
      when 'i' {
        take pack-int32($arg.Int, :byte-order(big-endian));
      }
      when 'h' {
        take pack-int64($arg.Int, :byte-order(big-endian));
      }
      when 's' {
        take self.pack-string($arg.Str);
      }
      when 'b' {
        # Remove the wrapper or just pass along the argument
        take self.pack-blob: ($arg ~~ Net::OSC::Types::OSCType) ?? $arg.content !! $arg;
      }
      default {
        die "No type map defined for '$_' unable to add { $arg.gist } to OSC message.";
      }
    }

  }).map( { |$_[0..*] } ) )
}

#returns a new Message object
method unpackage(Buf $packed-osc) returns Net::OSC::Message
#= Returns a Net::OSC::Message from a Buf where the content of the Buf is an OSC message.
#= Will die on unhandled OSC type and behaviour is currently undefined on non OSC message Bufs.
{
  #say "Unpacking message of {$packed-osc.elems} byte(s):";
  #say $packed-osc.map( { sprintf('%4s', $_.base(16)) } ).rotor(8, :partial).join("\n");
  my $path = '';
  my @types;
  my @args;
  my $read-pointer = 0;
  my $buffer-width = 1;
  my $message-part = 0; # 0 = path, 1 = type string, 2 = args

  #Closure for string parsing, operates on this scope of variables
  my $extract-string = sub {
    #say "Unpacking string";
    $buffer-width = width32;
    my $arg = '';
    my $chars;
    repeat {
      $chars = $packed-osc.subbuf($read-pointer, $buffer-width);
      $read-pointer += $buffer-width;
      for $chars.decode('ISO-8859-1').comb -> $char {
        if $char eq "\0" {
          $buffer-width = 0; #signal end of string
          last;
        }
        $arg ~= $char;
      }
    } while $buffer-width == width32 and $read-pointer < $packed-osc.elems;
    #say "'$arg'";
    $arg;
  }

  #start parse
  $path = $extract-string.();
  @types = $extract-string.().comb: /\w/; #extract type chars and ignore the ','

  while $read-pointer < $packed-osc.elems {
    given @types.shift -> $type {
      when $type eq 'f' {
        my $buf = $packed-osc.subbuf($read-pointer, width32);
        @args.push: unpack-float $buf, :byte-order(big-endian);
        $read-pointer += width32;
      }
      when $type eq 'i' {
        my $buf = $packed-osc.subbuf($read-pointer, width32);

        @args.push: unpack-int32 $buf, :byte-order(big-endian);
        $read-pointer += width32;
      }
      when $type eq 'd' {
        my $buf = $packed-osc.subbuf($read-pointer, width64);
        @args.push: unpack-double $buf, :byte-order(big-endian);
        $read-pointer += width64;
      }
      when $type eq 'h' {
        my $buf = $packed-osc.subbuf($read-pointer, width64);

        @args.push: unpack-int64 $buf, :byte-order(big-endian);
        $read-pointer += width64;
      }
      when $type eq 's' {
        @args.push: $extract-string.();
      }
      when $type eq 'b' {
        # Read the size portion of the buffer
        my $length = unpack-int32 $packed-osc.subbuf($read-pointer, width32), :byte-order(big-endian);
        $read-pointer += width32;

        @args.push: $packed-osc.subbuf($read-pointer, $length);
        $read-pointer += $length;
      }
      default {
        die "Unhandled type '$type'";
      }
    }
  }

  Net::OSC::Message.new(
    :$path,
    :@args
  );
}

method buf2bin(Buf $bits) returns Array
#= Returns a binary array of the content of a Buf. Useful for debugging.
{
  my @bin;
  for 0 .. ($bits.elems - 1) {
    @bin.push: |sprintf( '%08d', $bits[$_].base(2) ).comb;
  }
  @bin
}

method bits2buf(@bits) returns Buf
#= Returns a Buf from a binary array. Not super useful.
{
  Buf.new: @bits.rotor(8).map: { self.unpack-int($_, :signed(False)) };
}

method pack-string(Str $string) returns Blob
#= Returns a Blob of a string packed for OSC transmission.
{
  ( $string ~ ( "\0" x 4 - ( $string.chars % 4) ) ).encode('ISO-8859-1')
}

method pack-blob(Blob $buffer --> Blob)
#= Formats a Blob into an OSC format blob.
{
    Blob.new(|pack-int32($buffer.elems, :byte-order(big-endian))[], |$buffer[])
}
