#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVGPDF::Path :isa(SVGPDF::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    if ( defined $atts->{id} ) {
	$self->root->defs->{ "#" . $atts->{id} } = $self;
	# MathJax uses curves to draw glyphs. These glyphs are filles
	# *and* stroked with a very small stroke-width. According to
	# the PDF specs, this should yield a 1-pixel (device pixel)
	# stroke, which results in fat glyphs on screen.
	# To avoid this, disable stroke when drawing MathJax glyphs.
	if ( $atts->{id} =~ /^MJX-/ ) {
	    $atts->{stroke} = 'none';
	}
    }

    my ( $d, $tf ) = $self->get_params( $atts, "d:!", "transform:s" );

    ( my $t = $d ) =~ s/\s+/ /g;
    $t = substr($t,0,20) . "..." if length($t) > 20;
    $self->_dbg( $self->name, " d=\"$t\"", $tf ? " tf=\"$tf\"" : "" );
    $self->_dbg( "+ xo save" );
    $xo->save;

    my $x = 0;
    my $y = 0;

    $self->set_transform($tf);
    $self->set_graphics;

    # Starting point of this path.
    my $x0 = $x;
    my $y0 = $y;

    # Path items may be separated by whitespace and commas, but
    # separators may be left out if not strictly necessary.
    # I.e. M0-1-1V10 is M 0 -1 -1 V 10 ...
    $d =~ s/([-+])/ $1/g;
    $d =~ s/([a-z])/ $1 /gi;
    # Worse: 10.11.12 is 10.11 12 ...
    $d =~ s/(\d)\.(\d*)\./$1.$2 /g;
    $d =~ s/(\d)\.(\d*)\./$1.$2 /g;
    $d =~ s/,/ /g;
    # Cleanup a bit and split.
    $d =~ s/^\s+//g;
    $d =~ s/\s+$//g;
    $d =~ s/\s+/ /g;
    my @d = split( ' ', $d );

    my $open;			# path is open

    my $paint = $self->_paintsub;

    # Initial x,y for path. See 'z'.
    my $ix;
    my $iy;

    # Current point.
    my ( $cx, $cy ) = ( $x0, $y0 );
    my @cp;

    while ( @d ) {
	my $op = shift(@d);

	# Use abs coor if op is uppercase.
	my $abs;
	if ( $abs = $op eq uc($op) ) {
	    $op = lc($op);
	    $x = $x0;
	    $y = $y0;
	}
	else {
	    $x = $cx;
	    $y = $cy;
	}

	# MoveTo
	if ( $op eq "m" ) {
	    $x += shift(@d); $y += shift(@d);
	    $self->_dbg( "xo move(%.2f,%.2f)", $x, $y );
	    $ix = $cx, $iy = $cy unless $open;
	    $xo->move( $x, $y );
	    if ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		# Subsequent coordinate pair(s) imply lineto.
		unshift( @d, $abs ? 'L' : 'l' );
	    }
	    ( $cx, $cy ) = ( $x, $y );
	    next;
	}

	# Horizontal LineTo.
	if ( $op eq "h" ) {
	    $ix = $cx, $iy = $cy unless $open++;
	    $self->_dbg( "xo hline(%.2f)", $d[0] );
	    $x += shift(@d);
	    $xo->hline($x);
	    ( $cx, $cy ) = ( $x, $cy );
	    next;
	}

	# Vertical LineTo.
	if ( $op eq "v" ) {
	    $ix = $cx, $iy = $cy unless $open++;
	    $self->_dbg( "xo vline(%.2f)", $d[0] );
	    $y += shift(@d);
	    $xo->vline($y);
	    ( $cx, $cy ) = ( $cx, $y );
	    next;
	}

	# Generic LineTo.
	if ( $op eq "l" ) {
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $x, $iy = $y unless $open++;
		$x += shift(@d); $y += shift(@d);
		$self->_dbg( "xo line(%.2f,%.2f)", $x, $y );
		$xo->line( $x, $y );
	    }
	    ( $cx, $cy ) = ( $x, $y );
	    next;
	}

	# Cubic Bézier curves.
	if ( $op eq "c" ) {
	    my ( $ox, $oy ) = ( $x, $y );
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		( $x, $y ) = ( $ox, $oy ) if $abs;
		$ix = $x, $iy = $y unless $open++;
		my @c = ( $x + $d[0], $y + $d[1], # control point 1
			  $x + $d[2], $y + $d[3], # control point 2
			  $x + $d[4], $y + $d[5]  # end point
			);
		$self->_dbg( "xo curve(%.2f,%.2f %.2f,%.2f %.2f,%.2f)", @c );
		$xo->curve(@c);
		push( @cp, [ $cx, $cy, $c[0], $c[1] ] );
		push( @cp, [ $c[4], $c[5], $c[2], $c[3] ] );
		$x = $c[4]; $y = $c[5]; # current point
		( $cx, $cy ) = ( $x, $y );

		# Check if followed by S-curve.
		if ( @d > 7 && lc( my $op = $d[6] ) eq "s" ) {
		    # Turn S-curve into C-curve.
		    # New cp1 becomes reflection of cp2.
		    my $rx = 2*$d[4] - $d[2];
		    my $ry = 2*$d[5] - $d[3];
		    splice( @d, 0, 7 );
		    unshift( @d, $op eq 's' ? 'c' : 'C', $rx, $ry );
		}
		else {
		    splice( @d, 0, 6 );
		}
	    }
	    next;
	}

	# Standalone shorthand Bézier curve.
	# (When following an S-curve these will have been modified into S.)
	if ( $op eq "s" ) {
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $cx, $iy = $cy unless $open++;
		my @c = ( $x + $d[0], $y + $d[1],
			  $x + $d[2], $y + $d[3] );
		$self->nfi("standalone s-paths");
		unshift( @c, $x, -$y );
		$self->_dbg( "xo curve(%.2f,%.2f %.2f,%.2f %.2f,%.2f)", @c );
		$xo->curve(@c);
		splice( @d, 0, 4 );
		$x = $c[4]; $y = $c[5];
		( $cx, $cy ) = ( $x, $y );
	    }
	    next;
	}

	# Quadratic Bézier curves.
	if ( $op eq "q" ) {
	    my ( $ox, $oy ) = ( $x, $y );
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		( $x, $y ) = ( $ox, $oy ) if $abs;
		$ix = $cx, $iy = $cy unless $open++;
		my @c = ( $x + $d[0], $y + $d[1], # control point 1
			  $x + $d[2], $y + $d[3]  # end point
			);
		$self->_dbg( "xo spline(%.2f,%.2f %.2f,%.2f)", @c );
		$xo->spline(@c);
		push( @cp, [ $cx, $cy, $c[0], $c[1] ] );
		push( @cp, [ $c[2], $c[3], $c[0], $c[1] ] );
		$x = $c[2]; $y = $c[3]; # current point
		( $cx, $cy ) = ( $x, $y );

		# Check if followed by T-curve.
		if ( @d > 5 && lc( my $op = $d[4] ) eq "t" ) {
		    # Turn T-curve into Q-curve.
		    # New cp becomes reflection of current cp.
		    my $rx = 2*$d[2] - $d[0];
		    my $ry = 2*$d[3] - $d[1];
		    splice( @d, 0, 5 );
		    unshift( @d, $op eq 't' ? 'q' : 'Q', $rx, $ry );
		}
		else {
		    splice( @d, 0, 4 );
		}
	    }
	    next;
	}

	# Standalone shorthand quadratic Bézier curve.
	# (When following an S-curve these will have been modified into S.)
	if ( $op eq "t" ) {
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $cx, $iy = $cy unless $open++;
		my @c = ( $cx, $cy,
			  $x + $d[0], $y + $d[1] );
		$self->_dbg( "xo spline(%.2f,%.2f %.2f,%.2f)", @c );
		$xo->spline(@c);
		$x = $c[0]; $y = $c[1];
		( $cx, $cy ) = ( $x, $y );

		# Check if followed by another T-curve.
		if ( @d > 3 && lc( my $op = $d[2] ) eq "t" ) {
		    # Turn T-curve into Q-curve.
		    # New cp becomes reflection of current cp.
		    my $rx = 2*$d[3] - $d[0];
		    my $ry = 2*$d[4] - $d[1];
		    splice( @d, 0, 3 );
		    unshift( @d, $op eq 't' ? 'q' : 'Q', $rx, $ry );
		}
		else {
		    splice( @d, 0, 2 );
		}
	    }
	    next;
	}


	# Arcs.
	if ( $op eq "a" ) {
	    while ( @d > 6 && $d[0] =~ /^-?[.\d]+$/ ) {
		my $rx    = shift(@d);		# radius 1
		my $ry    = shift(@d);		# radius 2
		my $rot   = shift(@d);		# rotation
		my $large = shift(@d);		# select larger arc
		my $sweep = shift(@d);		# clockwise
		my $ex    = $x + shift(@d);	# end point
		my $ey    = $y + shift(@d);
		$self->_dbg( "xo arc(%.2f,%.2f %.2f %d,%d %.2f,%.2f)",
			     $rx, $ry, $rot, $large, $sweep, $ex, $ey );

		# for circular arcs.
		if ( $rx == $ry ) {
		    $self->_dbg( "circular_arc(%.2f,%.2f %.2f,%.2f %.2f ".
				 "move=%d large=%d dir=%d)",
				 $cx, $cy, $ex, $ey, $rx, 0, $large, $sweep );
		    $self->circular_arc( $cx, $cy, $ex, $ey, $rx,
					 move  => 0,
					 large => $large,
					 dir   => $sweep );
		}
		else {
		    $self->_dbg( "elliptic_arc(%.2f,%.2f %.2f,%.2f %.2f,%.2f ".
				 "move=%d large=%d dir=%d)",
				 $cx, $cy, $ex, $ey, $rx, $ry, 0, $large, $sweep );
		    $self->elliptic_arc( $cx, $cy, $ex, $ey,
					 $rx, $ry,
					 move  => 0,
					 large => $large,
					 dir   => $sweep );
		}
		$ix = $cx, $iy = $cy unless $open++;
		( $cx, $cy ) = ( $ex, $ey );
	    }
	    next;
	}

	# Close path and paint.
	if ( lc($op) eq "z" ) {
	    $self->_dbg( "xo $op" );
	    if ( $open ) {
		$xo->close;
		# currentpoint becomes the initial point.
		$x = $ix;
		$y = $iy;
		$open = 0;
	    }
	    if ( @d > 2 && lc($d[0]) eq 'm' ) {
	    }
	    else {
		$paint->();
	    }
	    next;
	}

	die("path[$op] @d");
    }

    $paint->() if $open;
    $self->_dbg( "- xo restore" );
    $xo->restore;

    # Show collected control points.
    if ( 0 && $self->root->debug && @cp ) {
	$xo->save;
	$xo->stroke_color('lime');
	$xo->line_width(1);
	for ( @cp ) {
	    $self->_dbg( "xo line(%.2f %.2f %.2f %.2f)", @$_ );
	    $xo->move( $_->[0], $_->[1] );
	    $xo->line( $_->[2], $_->[3] );
	}
	$xo->stroke;
	$xo->restore;
    }

    $self->css_pop;
}

method curve ( @points ) {
    $self->_dbg( "+ xo curve( %.2f,%.2f %.2f,%.2f %.2f,%.2f )", @points );
    $self->xo->curve(@points);
    $self->_dbg( "-" );
}

method elliptic_arc( $x1,$y1, $x2,$y2, $rx,$ry, %opts) {
    require SVGPDF::Contrib::Bogen;

    SVGPDF::Contrib::Bogen::bogen_ellip
	( $self, $x1,$y1, $x2,$y2, $rx,$ry, %opts );
}

method circular_arc( $x1,$y1, $x2,$y2, $r, %opts) {
    require SVGPDF::Contrib::Bogen;

    SVGPDF::Contrib::Bogen::bogen
	( $self, $x1,$y1, $x2,$y2, $r,
	  $opts{move}, $opts{large}, $opts{dir} );
}

1;
