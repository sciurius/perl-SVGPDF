#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Svg :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    return if $atts->{omit};	# for testing/debugging.

    my $xo = $self->xo;

    delete $atts->{$_} for qw( xmlns:xlink xmlns:svg xmlns version );
    my ( $x, $y, $width, $height, $vbox ) =
      $self->get_params( $atts, qw( x:U y:U width:s height:s viewBox ) );
    my $style = $self->style;

    my @bb;
    # Currently we rely on the <svg> to supply the correct viewBox.
    if ( $vbox ) {
	@bb = $self->getargs($vbox);
	warn(sprintf("vbox( %.2f,%.2f %.2f,%.2f )\n", @bb ));
    }

    my $xoforms = $self->root->xoforms;
    my $new_xo = $self->root->pdf->xo_form;
    push( @$xoforms,
	  { xo => $new_xo,
	    vbox => \@bb,
	  } );
    $self->_dbg("XObject #", scalar(@$xoforms) );

    if ( $vbox ) {
	$new_xo->bbox(@bb);
	$self->_dbg( "translate( %.2f %.2f )", -$bb[0], $bb[1]+$bb[3] );
	warn(sprintf("translate( %.2f %.2f )", -$bb[0], $bb[1]+$bb[3] ),"\n");;
	$new_xo->transform( translate => [ -$bb[0], $bb[1]+$bb[3] ] );
    }
    else {
	$new_xo->bbox(-32767,-32767,65535,65535);
    }
    $self->traverse;

    my $scalex = 1;
    my $scaley = 1;
    if ( $vbox ) {
	if ( $width ) {
	    $scalex = $width / $bb[2];
	}
	if ( $height ) {
	    $scaley = $height / $bb[3];
	}
	$y -= $bb[3]*$scaley;
    }
    $self->_dbg( "xo object( %.2f %.2f )", $x, $y );
    warn(sprintf("xo object( %.2f %.2f %.3f %.3f )\n", $x, $y, $scalex, $scaley ));
    $xo->object( $new_xo, $x, $y, $scalex, $scaley );

    pop( @$xoforms );

    $self->css_pop;

}


1;
