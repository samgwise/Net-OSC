use v6;

unit module Net::OSC::Types;

=begin pod

=head1 Net::OSC::Types

Provides helper classes and subsets for dealing with OSC communications.

Type wrappers are provided for OSC 1.0 standard types.

=end pod

#
# OSC Type wrappers
#
# The following types provide user directives as to what type the value should be encoded to when packed into an OSC message.

our role OSCType[::RakuType]
#= Base role for all OSC Type description wrappers.
{

    has RakuType $.content is required handles <Str Rat Int Blob>;

    method type-code( --> Str) { ... }

    method type() { RakuType }
}

our sub type-constructor-factory(OSCType $type-class --> Callable)
#= Create a closure on the given type class with a constructor.
{
    -> $value { $type-class.new( :content($value) ) }
}

our sub osc-type-map-generator(*@osc-type-classes --> Map)
#= Creates a type map of type wrapper name to OSC type code relationships.
{
    %(
        |@osc-type-classes.map( { .^name => .type-code } )
    )
}

our class OSCString does OSCType[Str:D]
#= Tag Str values as OSC type 's'.
#= Can be created via the osc-str function.
{
    method type-code( --> Str) { 's' }
}

our class OSCBlob does OSCType[Blob:D]
#= Tag Blob values as OSC type 'b'.
#= Can be created via the osc-blob function.
{

    method type-code( --> Str) { 'b' }
}

our class OSCInt32 does OSCType[Int:D]
#= Tag Int values as OSC type 'i'.
#= Can be created via the osc-int32 function.
{
    method type-code( --> Str) { 'i' }
}

our class OSCInt64 does OSCType[Int:D]
#= Tag Int values as OSC type 'h'.
#= Can be created via the osc-int64 function.
{
    method type-code( --> Str) { 'h' }
}

our class OSCFloat32 does OSCType[Rat:D]
#= Tag Rat values as OSC type 'f'.
#= Can be created via the osc-float function.
{
    method type-code( --> Str) { 'f' }
}

our class OSCFloat64 does OSCType[Rat:D]
#= Tag Rat values as OSC type 'd'.
#= Can be created via the osc-double function.
{
    method type-code( --> Str) { 'd' }
}

# OSC Type map
our %osc-wrapper-type-map = osc-type-map-generator(OSCString, OSCBlob, OSCInt32, OSCInt64, OSCFloat32, OSCFloat64);

#
# Package exports
#
our subset OSCPath of Str is export where *.substr-eq('/', 0);

our subset ActionTuple of List is export where -> $t { $t[0] ~~ Regex and $t[1] ~~ Callable }

# OSC type wrapper factories
our &osc-str is export = type-constructor-factory(OSCString);
our &osc-blob is export = type-constructor-factory(OSCBlob);
our &osc-int32 is export = type-constructor-factory(OSCInt32);
our &osc-int64 is export = type-constructor-factory(OSCInt64);
our &osc-float is export = type-constructor-factory(OSCFloat32);
our &osc-double is export = type-constructor-factory(OSCFloat64);