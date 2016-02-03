use v6;

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
    ) ~ "{ self.type-string() },".encode('ISO-8859-1') ~ self!pack-args();
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
          take pack('A*', $arg);      #null terminated string
        }
        default {
          take pack(%pack-map{$type}, $arg);
        }
      }

    }
  }

  #returns a new Message object
  method unpackage(Buf $packed-osc) {
    my $path = '';
    my @types;
    my @args;
    my $read-pointer = 0;
    my $buffer-width = 1;
    my $comma-count = 0;
    while $read-pointer < $packed-osc.elems {
      if $comma-count == 0 {
        my $char = $packed-osc.subbuf($read-pointer, $buffer-width).decode('ISO-8859-1');
        if $char eq ',' {
          $comma-count++;
        }
        else {
          $path ~= $char if $char;
        }
        $read-pointer += $buffer-width;
      }
      elsif $comma-count == 1 {
        my $char = $packed-osc.subbuf($read-pointer, $buffer-width).decode('ISO-8859-1');
        if $char eq ',' {
          $comma-count++;
        }
        else {
          @types.push: $char if $char;
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
            $buffer-width = 1;
            my $arg = '';
            my $char;
            repeat {
              $char = $packed-osc.subbuf($read-pointer, $buffer-width);
              last if $char[0] == 0;
              $char .= decode('ISO-8859-1');
              $arg ~= $char;
              $read-pointer += $buffer-width;
            } while $char.chars == $buffer-width and $read-pointer < $packed-osc.elems;
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
    #binary = ($number / 2**$number.truncate.msb)
    my @bits = (
        ($number.sign == -1 ?? 1 !! 0)                                            #sign         bit 31
      ~ ($number.truncate.msb + 127).base(2)                                      #exponent     bit 30 - 23
      ~ ( ($number / 2**$number.truncate.msb).base(2) ~ (0 x 23) ).substr(2, 23)  #fraction     bit 22 - 0
    ).comb(/\d**8/);

    Buf.new( @bits.map: { EVAL "0b$_" } )
  }

  method pack-int32(Int(Cool) $number) returns Buf {
    my @bits = (
      sprintf( '%032d', $number.base(2) )
    ).comb(/\d**8/);

    Buf.new( @bits.map: { EVAL "0b$_" } )
  }

  method unpack-float32(Buf $bits) {
    my $bin = self.buf2bin($bits);

    (-1) ** $bin[0]                                       #sign       bit 31
    *
    (1 + self.unpack-int($bin[9..$bin.end]) * 2**-23)     #significand (fraction) 22-0
    *
    2 ** ( self.unpack-int($bin[1..8]) - 127 );           #exponent     bit 30 - 23
  }

  method unpack-int32(Buf $bits) returns Int {
    self.unpack-int: self.buf2bin($bits);
  }

  method unpack-int(@bits) returns Int {
    my Int $total = 0;
    for 0..@bits.end -> $i {
      $total += Int(@bits[$i] * (2 ** (@bits.end - $i)));
    }
    $total;
  }

  method buf2bin(Buf $bits) returns Array {
    my @bin;
    for 0 .. ($bits.elems - 1) {
      @bin.push: |sprintf( '%08d', $bits[$_].base(2) ).comb;
    }
    @bin
  }

}
