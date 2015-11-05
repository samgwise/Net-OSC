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

  has OSCPath $.path        = '/';
  has Str     $!type-string = Nil;
  has         @!args;

  submethod BUILD(:@!args) {

  }

  # #Add clear triggers for basic array methods
	# for <pop shift> -> $method {
	# 	Net::OSC::Message.^add_method: $method, my method clear-type-string-on-change(Net::OSC::Message:) {
  #     $!type-string = Nil;
	# 		@!args.$method();
	# 	}
	# }
  #
  # for <push unshift> -> $method {
  #   say "Adding method wrapper for $method";
	# 	Net::OSC::Message.^add_method: $method, my method clear-type-string-on-change(Net::OSC::Message: *@args) {
  #     say "Wrapper for $method called";
  #     $!type-string = Nil;
	# 		@!args.$method(|@args);
	# 	}
	# }

  #lazy accessor
  method type-string() {
    return $!type-string if $!type-string;

    $!type-string = [~] gather for self.args() -> $arg {
      #say "Choosing type for $arg of type {$arg.WHAT.perl}";
      if $arg.WHAT.perl ~~ %type-map {
        take %type-map{$arg.WHAT.perl};
      }
      else {
        die "Unable to map $arg of type { $arg.perl } to OSC type!";
      }
    }

    $!type-string;
  }

  method args(*@new-args) {
    if @new-args {
      @!args.push(|@new-args);
      $!type-string = Nil;
    }

    gather for @!args -> $arg {
      take $arg;
    }
  }

  method type-map() {
    %type-map.pairs;
  }
}
