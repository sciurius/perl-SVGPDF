#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVGPDF::Rect :isa(SVGPDF::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my ( $x, $y, $w, $h ) =
      $self->get_params( $atts, qw( x:U y:U width:U height:U ) );

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
