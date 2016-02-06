use v6;
use experimental :pack;

class Net::OSC::Message {
  subset OSCPath of Str where { $_.substr-eq('/', 0) }

  my %type-map =
    Int.^name,    'i',
    IntStr.^name, 'i',
    Num.^name,    'd',
    Rat.^name,    'd',
    RatStr.^name, 'd',
    FatRat.^name, 'd',
    Str.^name,    's',
    Blob.^name,   'b',
  ;
  #Initial pack mappings sourced from the Protocol::OSC perl5 module
  # expanded with info from http://opensoundcontrol.org/spec-1_0
  my %pack-map =
    i => 'i',           #int32
    f => 'f',           #float32
    s => 's',           #OSC-string
    S => 's',           #OSC-string alternative
    b => 'N/C* x!4',    #OSC-blob
    h => 'h',           #64 bit big-endian twos compliment integer
    t => 'N2',          #OSC-timetag
    d => 'f',           #64 bit ("double") IEEE 754 floating point number
  ;
  my      $message-prefix-packing  = '(A*x!4)2A*';
  my Int  $max-float-sp-fraction   = 2**23 - 1;      #0b11111111111111111111111 or 2**23 - 1 = 8388607
  my Int  $max-float-sp            = 2**32 - 1;

  has OSCPath $.path        = '/';
  has Str     @!type-list   = Nil;
  has         @!args;

  submethod BUILD(:@!args) {
     self!update-type-list(@!args);
  }

  method type-string() {
    @!type-list.join: '';
  }

  method pick-osc-type($arg) {
    #say "Choosing type for $arg of type {$arg.WHAT.perl}";
    if $arg.WHAT.perl ~~ %type-map {
      return %type-map{$arg.WHAT.perl};
    }
    else {
      die "Unable to map $arg of type { $arg.perl } to OSC type!";
    }
  }

  method !update-type-list(*@args){
    for @args -> $arg {
      @!type-list.push: self.pick-osc-type($arg);
    }
  }

  method args(*@new-args) {
    if @new-args {
      @!args.push(|@new-args);
      self!update-type-list(|@new-args);
    }

    gather for @!args -> $arg {
      take $arg;
    }
  }

  method set-args(*@new-args) {
    @!args = ();
    @!type-list = ();
    self.args(@new-args) if @new-args;
  }

  method type-map() {
    %type-map.pairs;
  }

  method package() returns Buf {
    pack($message-prefix-packing,
      $.path,
      ',',
    ) ~ "{ self.type-string() }\0".encode('ISO-8859-1') ~ self!pack-args();
  }

  method !pack-args() returns Buf {
    [~] gather for @!args Z @!type-list -> ($arg, $type) {
      #say "Packing '$arg' of OSC type '$type' with pattern '%pack-map{$type}'";

      given %pack-map{$type} {
        when 'f' {
          take self.pack-float32($arg);
        }
        when 'i' {
          take self.pack-int32($arg);
        }
        when 's' {
          #take pack('A*', $arg);      #null terminated string
          #take Buf.new($arg.encode('ISO-8859-1').subbuf(0, $arg.chars), 0);
          take ($arg ~ "\0").encode('ISO-8859-1')
        }
        default {
          take pack(%pack-map{$type}, $arg);
        }
      }

    }
  }

  #returns a new Message object
  method unpackage(Buf $packed-osc) {
    say "Unpacking message of {$packed-osc.elems} byte(s):";
    say $packed-osc.map( { sprintf('%4s', $_.base(16)) } ).rotor(8, :partial).join("\n");
    my $path = '';
    my @types;
    my @args;
    my $read-pointer = 0;
    my $buffer-width = 1;
    my $message-part = 0; # 0 = path, 1 = type string, 2 = args
    while $read-pointer < $packed-osc.elems {
      say '-' x 42;
      say "Read pointer: $read-pointer/{ $packed-osc.elems - 1 }";
      if $message-part == 0 {
        my $char = $packed-osc.subbuf($read-pointer, $buffer-width).decode('ISO-8859-1');
        if $char eq "\0" {
          $message-part++;
        }
        else {
          $path ~= $char if $char;
        }
        $read-pointer += $buffer-width;
      }
      elsif $message-part == 1 {
        my $char = $packed-osc.subbuf($read-pointer, $buffer-width).decode('ISO-8859-1');
        if $char eq "\0" {
          $message-part++;
        }
        else {
          @types.push: $char if $char and $char ne ','; #why is the comma a part of this spec?
        }
        $read-pointer += $buffer-width;
      }
      else {
        given @types.shift -> $type {
          when $type eq 'f'|'d' {
            $buffer-width = 4;
            my $buf = $packed-osc.subbuf($read-pointer, $buffer-width);
            @args.push: self.unpack-float32( $buf );
            $read-pointer += $buffer-width;
          }
          when $type eq 'i' {
            $buffer-width = 4;
            my $buf = $packed-osc.subbuf($read-pointer, $buffer-width);

            @args.push: self.unpack-int32( $buf );
            $read-pointer += $buffer-width;
          }
          when $type eq 's' {
            say "Unpacking string";
            $buffer-width = 1;
            my $arg = '';
            my $char;
            repeat {
              $char = $packed-osc.subbuf($read-pointer, $buffer-width);
              $read-pointer += $buffer-width;
              last if $char[0] == 0;
              $char .= decode('ISO-8859-1');
              $arg ~= $char;
            } while $char.chars == $buffer-width and $read-pointer < $packed-osc.elems;
            say "'$arg'";
            @args.push: $arg;
          }
          default {
            die "Unhandled type '$type'";
          }
        }
      }
    }

    self.bless(
      :$path,
      :@args
    );
  }

  method pack-float32(Numeric(Cool) $number) returns Buf {
    say "packing $number as float32";
    #binary = ($number / 2**$number.truncate.msb)
    # my @bits = (
    #     ($number.sign == -1 ?? 1 !! 0)                                            #sign         bit 31
    #   ~ ($number.truncate.msb + 127).base(2)                                      #exponent     bit 30 - 23
    #   ~ ( ($number / 2**$number.truncate.msb).base(2) ~ (0 x 23) ).substr(2, 23)  #fraction     bit 22 - 0
    # ).comb;

    my $fraction = ($number - $number.truncate).substr( $number.sign == -1 ?? 3 !! 2 ).Int;
    say "fraction: $fraction, msb: { $number.truncate.msb }.{ $fraction.msb }";
    my @bits = (
        ($number.sign == -1 ?? 1 !! 0)                                            #sign         bit 31
      ~ (($number.truncate.msb + 127).base(2) ~ (0 x 8)).substr(0, 8)                                      #exponent     bit 30 - 23
      ~ ( ($number / 2**$number.truncate.msb).base(2) ~ (0 x 23) ).substr( ($number.sign == -1 ?? 3 !! 2), 23 )  #fraction     bit 22 - 0
    ).comb;

    say @bits;

    self.bits2buf(@bits);
  }

  method pack-int32(Int(Cool) $number) returns Buf {
    self.pack-int($number, 32);
  }

  method pack-int(Int $value, Int $bit-width = 32, Bool :$signed = True) returns Buf {
    say "Packing $value to a { $signed ?? "signed" !! "unsigned" } {$bit-width}bit int";
    my @bits = (
      ($signed ?? ($value.sign == -1 ?? 1 !! 0) !! '')
      ~
      sprintf( "\%0{ $signed ?? $bit-width - 1 !! $bit-width }d", $value.abs.base(2) )
    ).comb;

    say "$value → { @bits.rotor(8)».join: '' }";

    self.bits2buf(@bits);
  }

  method unpack-float32(Buf $bits) {
    my $bin = self.buf2bin($bits);
    say "unpacking float32: { $bin.rotor(8)».join: '' }";

    my $total = (
      (-1) ** $bin[0]                                       #sign       bit 31
      *
      (1 + self.unpack-int($bin[9..$bin.end], :signed(False)) * 2**-23)     #significand (fraction) 22-0
      *
      2 ** ( self.unpack-int($bin[1..8], :signed(False)) - 127 )             #exponent     bit 30 - 23
    ) + ($bin[0].sign == 1 ?? 128 !! 0);
    say $total;
    $total
  }

  method unpack-int32(Buf $bits) returns Int {
    self.unpack-int: self.buf2bin($bits);
  }

  method unpack-int(@bits, Bool :$signed = True) returns Int {
    say "Unpacking { $signed ?? "signed" !! "unsigned" } int { @bits.perl } { @bits.elems }";
    my Int $total = 0;
    for ($signed ?? 1 !! 0)..@bits.end -> $i {
      if !$signed or @bits[0] == 0 {
        $total += Int(@bits[$i] * (2 ** (@bits.end - $i)));
      }
      else {
        $total -= Int(@bits[$i] * (2 ** (@bits.end - $i)));
      }
    }
    say $total;
    $total;
  }

  method buf2bin(Buf $bits) returns Array {
    my @bin;
    for 0 .. ($bits.elems - 1) {
      @bin.push: |sprintf( '%08d', $bits[$_].base(2) ).comb;
    }
    @bin
  }

  method bits2buf(@bits) returns Buf {
    Buf.new: @bits.rotor(8).map: { self.unpack-int($_, :signed(False)) };
  }

}
