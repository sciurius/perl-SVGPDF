#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Path :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my ( $d, $tf ) = $self->get_params( $atts, "d:!", "transform:s" );

    my $t = $d;
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

    # Cleanup a bit and split.
    $d =~ s/([a-z])([a-z])/$1 $2/gi;
    $d =~ s/([a-z])([-\d])/$1 $2/gi;
    $d =~ s/([-\d])([a-z])/$1 $2/gi;
    $d =~ s/,/ /g;
    my @d = split( ' ', $d );

    my $open;			# path is open

    my $paint = $self->_paintsub;

    # Initial x,y for path. See 'z'.
    my $ix;
    my $iy;

    # Current point.
    my ( $cx, $cy ) = ( $x0, $y0 );

    while ( @d ) {
	my $op = shift(@d);

	# Use abs coor if op is uppercase.
	my $abs;
	if ( $abs = $op eq uc($op) ) {
	    $x = $x0;
	    $y = $y0;
	    $op = lc($op);
	}

	# MoveTo
	if ( $op eq "m" ) {
	    $x += shift(@d); $y -= shift(@d);
	    $self->_dbg( "xo move(%.2f,%.2f)", $x, $y );
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
	    $y -= shift(@d);
	    $xo->vline($y);
	    ( $cx, $cy ) = ( $cx, $y );
	    next;
	}

	# Generic LineTo.
	if ( $op eq "l" ) {
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $x, $iy = $y unless $open++;
		$x += shift(@d); $y -= shift(@d);
		$self->_dbg( "xo line(%.2f,%.2f)", $x, $y );
		$xo->line( $x, $y );
	    }
	    ( $cx, $cy ) = ( $x, $y );
	    next;
	}

	# Cubic Bézier curves.
	if ( $op eq "c" ) {
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $x, $iy = $y unless $open++;
		my @c = ( $x + $d[0], $y - $d[1], # control point 1
			  $x + $d[2], $y - $d[3], # control point 2
			  $x + $d[4], $y - $d[5]  # end point
			);
		$self->_dbg( "xo curve(%.2f,%.2f %.2f,%.2f %.2f,%.2f)", @c );
		$xo->curve(@c);
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
		my @c = ( $x + $d[0], $y - $d[1],
			  $x + $d[2], $y - $d[3] );
		nfi("standalone s-paths");
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
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $cx, $iy = $cy unless $open++;
		my @c = ( $x + $d[0], $y - $d[1], # control point 1
			  $x + $d[2], $y - $d[3]  # end point
			);
		$self->_dbg( "xo spline(%.2f,%.2f %.2f,%.2f)", @c );
		$xo->spline(@c);
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
		my @c = ( $x, $y,
			  $x + $d[0], $y - $d[1] );
		nfi("standalone t-paths");
		unshift( @c, $x, -$y );
		$self->_dbg( "xo spline(%.2f,%.2f %.2f,%.2f)", @c );
		$xo->spline(@c);
		splice( @d, 0, 2 );
		$x = $c[2]; $y = $c[3];
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
		my $ey    = $y - shift(@d);
		$self->_dbg( "xo arc(%.2f,%.2f %.2f %d,%d %.2f,%.2f)",
		      $rx, $ry, $rot, $large, $sweep, $ex, $ey );

		# Hard... For the time being use the (obsolete) 'bogen'
		# for circular arcs.
		if ( $rx == $ry ) {
		    $self->_dbg( "xo bogen(%.2f,%.2f %.2f,%.2f %.2f %d %d %d)",
				 $cx, $cy, $ex, $ey, $rx, 0, $large, 1-$sweep );
		    $xo->bogen( $cx, $cy, $ex, $ey,
				$rx, 0, $large, 1-$sweep );
		}
		else {
		    nfi("elliptic arc paths");
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
	    $paint->();
	    next;
	}

	die("path[$op] @d");
    }

    $paint->() if $open;

    $self->_dbg( "- xo restore" );
    $xo->restore;
    $self->css_pop;
}


1;
