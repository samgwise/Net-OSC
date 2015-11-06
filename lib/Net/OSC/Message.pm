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
    i => 'N',           #int32
    f => 'f',           #float32
    s => 'A* x!4',      #OSC-string
    S => 'A* x!4',      #OSC-string alternative
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
      ',', self.type-string()
    ) ~ self!pack-args();
  }

  method !pack-args() returns Buf {
    [~] gather for @!args Z @!type-list -> ($arg, $type) {
      say "Packing '$arg' of OSC type '$type' with pattern '%pack-map{$type}'";

      given %pack-map{$type} {
        when 'f' {
          take self.pack-float32($arg);
        }
        default {
          take pack(%pack-map{$type}, $arg);
        }
      }

    }
  }

  #returns a new Message object
  method unpackage(Buf $packed-osc) {
    my ($path, $type-string, $args-buf) = $packed-osc.unpack: $message-prefix-packing;

    self.bless(
      :$path,
      :args(
        $args-buf.unpack: $type-string.substr(1).split('').map( {
          %pack-map{$_}:e ?? %pack-map{$_} !! die "No pack-mapping defined for type '$_'"
        } ).join('')
      )
    );
  }

  method pack-float32(Numeric(Cool) $number) returns Buf {
    #binary = ($number / 2**$number.truncate.msb)
    my @bits = (
        ($number.sign == -1 ?? 1 !! 0)                                            #sign         bit 31
      ~ ($number.truncate.msb + 127).base(2)                                      #exponent     bit 30 - 23
      ~ ( ($number / 2**$number.truncate.msb).base(2) ~ (0 x 23) ).substr(2, 23)  #fraction     bit 22 - 0
    ).comb(/\d**8/);
      say "$number => @bits[] ({ @bits.join('').chars })";

    Buf.new( @bits.map: { EVAL "0b$_" } )
  }

}
