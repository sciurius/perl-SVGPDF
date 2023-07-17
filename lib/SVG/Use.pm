#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;
use Storable;

class SVG::Use :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my ( $x, $y, $xr ) =
      $self->get_params( $atts, qw( x:U y:U xlink:href:! ) );

    unless ( defined $xr ) {
	warn("SVG: Missing ref in use (skipped)\n");
	$self->css_pop;
	return;
    }
    my $r = $self->root->defs->{$xr};
    unless ( $r ) {
	warn("SVG: Missing def for use \"$xr\" (skipped)\n");
	$self->css_pop;
	return;
    }

    # Update its xo.
    $r->xo = $self->xo;

    $y = -$y;
    $self->_dbg( $self->name, " \"$xr\" (", $r->name, "), x=$x, y=$y" );

    $self->css_push;

    $self->_dbg("+ xo save");
    $xo->save;
    $self->_dbg( "translate( %.2f %.2f )", $x, $y );
    $xo->transform( translate => [ $x, $y ] );
    $self->set_graphics;
    $r->process;
    $self->_dbg("- xo restore");
    $xo->restore;
    $self->css_pop;
}


1;
