#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Polyline :isa(SVG::Element);

method process () {
    $self->process_polyline(0);
}

method process_polyline ( $close ) {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my ( $points ) = $self->get_params( $atts, "points:s" );

    my @d = $self-> getargs($points);

    my $t = $points;
    $t = substr($t,0,20) . "..." if length($t) > 20;
    $self->_dbg( $self->name, " points=\"$t\"" );
    $self->_dbg( "+ xo save" );
    $xo->save;

    $self->set_graphics;

    if ( @d ) {
	# Flip y coordinates.
	for ( my $i = 1; $i < @d; $i += 2 ) {
	    $d[$i] = - $d[$i];
	}
	$xo->move( $d[0], $d[1] );
	$xo->polyline( @d[2 .. $#d] );
	$xo->close if $close;
	$self->_paintsub->();
    }

    $self->_dbg( "- xo restore" );
    $xo->restore;
    $self->css_pop;
}


1;
