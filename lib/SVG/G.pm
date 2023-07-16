#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::G :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my $t  = delete($atts->{transform}) || "";

    $self->css_push;

    $self->_dbg( $self->name, " ====" );

    my $x;
    my $y;
    my $scalex;
    my $scaley;
    my @m;
    my %o;

    if ( $t ) {
	if ( $t =~ m/translate \( \s*
		     ([-.\d]+) [,\s] \s*
		     ([-.\d]+)
		     \s* \)/x ) {
	    $x = $1;
	    $y = $2;
	    $self->_dbg( "xo translate( %.2f, %.2f )", $x, $y );
	}
	if ( $t =~ m/scale \( \s*
		     ([-.\d]+)
		     \s*(?: [,\s] \s* ([-.\d]+))?
		     \s* \)/x ) {
	    $scalex = $1;
	    $scaley = $2 // $scalex;
	    $self->_dbg( "xo scale( %.2f %.2f )", $scalex, $scaley );
	}
	if ( @m = $t =~ m/matrix\( \s*
		     ([-.\d]+) [,\s] \s*
		     ([-.\d]+) [,\s] \s*
		     ([-.\d]+) [,\s] \s*
		     ([-.\d]+) [,\s] \s*
		     ([-.\d]+) [,\s] \s*
		     ([-.\d]+)
		     \s* \)/x ) {
	    # Translation [ 1     0     0     1      tx ty ]
	    # Scale       [ sx    0     0     sy     0  0 ].
	    # Rotation    [ cos θ sin θ −sin θ cos θ 0  0 ]
	    # Skew        [ 1     tan α tan β 1      0 0 ]
	    $self->_dbg( "xo matrix( %.2f %.2f %.2f %.2f %.2f %.2f)", @m );
	    @m = () if "@m" eq "1 0 0 1 0 0";
	}
    }

    if ( @m ) {
	nfi("matrix transformations");
	# We probably have to flip some elements...
	$xo->matrix(@m);
    }
    else {
	if ( defined($x) || defined($y) ) {
	    $o{translate} = [ $x, -$y ];
	}
	if ( defined($scalex) ) {
	    $o{scale} = [ $scalex, $scaley ];
	}
	if ( %o ) {
	    $self->_dbg( "+ xo save" );
	    $xo->save;
	    $xo->transform( %o );
	}
    }

    $self->traverse;

    if ( @m || %o ) {
	$xo->restore;
	$self->_dbg( "- xo restore" );
    }

    $self->css_pop;
}


1;
