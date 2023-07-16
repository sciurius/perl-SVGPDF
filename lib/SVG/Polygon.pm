#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Polygon :isa(SVG::Polyline);

method process () {
    $self->process_polyline(1);
}

1;
