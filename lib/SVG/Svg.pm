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
    my ( $x, $y, $vw, $vh, $vbox, $par ) =
      $self->get_params( $atts, qw( x:U y:U width:s height:s viewBox preserveAspectRatio:s ) );
    my $style = $self->style;

    my @bb;			# bbox:    llx lly urx ury
    @bb = $xo->bbox;		# use parent (root?)
    $vw ||= $bb[2]-$bb[0];
    $vh ||= $bb[3]-$bb[1];

    my @vb;			# viewBox: llx lly width height

    # Currently we rely on the <svg> to supply the correct viewBox.
    my $width;			# width of the vbox
    my $height;			# height of the vbox
    if ( $vbox ) {
	@vb     = $self->getargs($vbox);
	$width  = $self->u($vb[2]);
	$height = $self->u($vb[3]);
    }
    else {
	# Fallback to width/height, falling back to A4.
	$width  = $self->u($vw||595);
	$height = $self->u($vh||842);
	@vb     = ( 0, 0, $width, $height );
	$vbox = "@vb";
    }

    # Get llx lly urx ury bounding box rectangle.
    @bb = ( 0, 0, $vb[2], $vb[3] );
    $self->_dbg( "vb $vbox => bb %.2f %.2f %.2f %.2f", @bb );

    my $xoforms = $self->root->xoforms;
    my $new_xo = $self->root->pdf->xo_form;
    push( @$xoforms,
	  { xo => $new_xo,
	    bbox    => [ @bb ],
	    vwidth  => $vw ? $self->u($vw) : $vb[2],
	    vheight => $vh ? $self->u($vh) : $vb[3],
	    vbox    => [ @vb ],
	    width   => $vb[2],
	    height  => $vb[3] } );
    $self->_dbg("XObject #", scalar(@$xoforms) );

    if ( $vbox ) {
	$new_xo->bbox(@bb);
	$self->_dbg( "translate( %.2f %.2f )", -$vb[0], $vb[1]+$vb[3] );
	warn(sprintf("translate( %.2f %.2f )", -$vb[0], $vb[1]+$vb[3] ),"\n");;
	$new_xo->transform( translate => [ -$vb[0], $vb[1]+$vb[3] ] );
    }
    else {
	$new_xo->bbox(-32767,-32767,32767,32767);
    }
    $self->traverse;

    my $scalex = 1;
    my $scaley = 1;
    my $dx = 0;
    my $dy = 0;
    if ( $vbox ) {
	my @pbb = $xo->bbox;
	if ( $vw ) {
	    $scalex = $vw / $vb[2];
	}
	if ( $vh ) {
	    $scaley = $vh / $vb[3];
	}
	if ( $par =~ /xMax/i ) {
	    $scalex = $scaley = min( $scalex, $scaley );
	    $dx = $pbb[2] - $bb[2];
	    $dx *= $scalex;
	}
	elsif ( $par =~ /xMid/i ) {
	    $dx = (($pbb[2]-$pbb[0])/2) - (($bb[2]-$bb[0])/2);
	    $scalex = $scaley = min( $scalex, $scaley );
	    $dx *= $scalex;
	}
	elsif ( $par =~ /xMin/i ) {
	    $dx = $pbb[0] - $bb[0];
	    $scalex = $scaley = min( $scalex, $scaley );
	}
	if ( $par =~ /yMax/i ) {
	    $dy = $pbb[3] - $bb[3];
	    $scalex = $scaley = min( $scalex, $scaley );
	    $dy *= $scaley;
	}
	elsif ( $par =~ /yMid/i ) {
	    $dy = (($pbb[3]-$pbb[1])/2) - $scaley*(($bb[3]-$bb[1])/2);
	    $scalex = $scaley = min( $scalex, $scaley );
	    #	    $dy *= $scaley;
	    $dy = -$dy;
	}
	elsif ( $par =~ /yMin/i ) {
	    $dy = $pbb[1] - $bb[1];
	    $scalex = $scaley = min( $scalex, $scaley );
	    $dy *= $scaley;
	}
	$y -= $vb[3]*$scaley;
    }
    $self->_dbg( "xo object( %.2f%+.2f %.2f%+.2f %.3f %.3f )",
		 $x, $dx, $y, $dy, $scalex, $scaley );
    warn(sprintf("xo object( %.2f%+.2f %.2f%+.2f %.3f %.3f )\n",
		 $x, $dx, $y, $dy, $scalex, $scaley ));
    $xo->object( $new_xo, $x+$dx, $y+$dy, $scalex, $scaley );

    pop( @$xoforms );

    $self->css_pop;

}

sub min ( $x, $y ) { $x < $y ? $x : $y }

1;
