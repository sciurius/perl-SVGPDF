#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Rect :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my $x  = $self->u(delete($atts->{x})     ) || 0;
    my $y  = $self->u(delete($atts->{y})     ) || 0;
    my $w  = $self->u(delete($atts->{width}) ) || 0;
    my $h  = $self->u(delete($atts->{height})) || 0;

    $self->css_push;

    $self->_dbg( $self->name, " x=$x y=$y w=$w h=$h" );
    $self->_dbg( "+ xo save" );
    $xo->save;

    $self->set_graphics;

    $xo->rectangle( $x, -$y, $x+$w, -$y-$h );
    $self->_paintsub->();

    $self->_dbg( "- xo restore" );
    $xo->restore;
    $self->css_pop;
}


1;
