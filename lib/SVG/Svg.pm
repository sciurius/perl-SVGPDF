#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Svg :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    $self->nfi("recursive svg elements");
    return;

}


1;
