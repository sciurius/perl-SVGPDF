#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVGPDF::Ellipse :isa(SVGPDF::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my ( $cx, $cy, $rx, $ry ) =
      $self->get_params( $atts, qw( cx:U cy:U rx:U ry:U ) );

    $self->_dbg( $self->name, " cx=$cx cy=$cy rx=$rx ry=$ry" );
    $self->_dbg( "+ xo save" );
    $xo->save;

    $self->set_graphics;
    $xo->ellipse( $cx, -$cy, $rx, $ry );
    $self->_paintsub->();

    $self->_dbg( "- xo restore" );
    $xo->restore;
    $self->css_pop;
}


1;
