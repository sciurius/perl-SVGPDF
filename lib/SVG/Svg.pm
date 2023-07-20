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
	$width = $self->u($width//$bb[2]);
	$height = $self->u($height//$bb[3]);
    }
    else {
	# Fallback to width/height.
	$width = $self->u($width||595);
	$height = $self->u($height||842);
	@bb = ( 0, 0, $width, $height );
	$vbox = "@bb";
    }

    my $xoforms = $self->root->xoforms;
    my $new_xo = $self->root->pdf->xo_form;
    push( @$xoforms,
	  { xo => $new_xo,
	    vbox => \@bb,
	  } );
    $self->_dbg("XObject #", scalar(@$xoforms) );

    $new_xo->bbox(@bb);
    $self->_dbg( "translate( %.2f %.2f )", 0, $bb[1]+$bb[3] );
    $new_xo->transform( translate => [ -$bb[0], $bb[1]+$bb[3] ] );

    $self->traverse;

    my $w = $bb[2];
    my $h = $bb[3];

    $self->_dbg( "xo object( %.2f %.2f)", $x, $y-$h );
    $xo->object( $new_xo, $x, $y-$h, 1, 1 );

    pop( @$xoforms );

    $self->css_pop;

}


1;
