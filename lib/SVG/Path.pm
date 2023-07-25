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

    if ( defined $atts->{id} ) {
	$self->root->defs->{ "#" . $atts->{id} } = $self;
	# MathJax tweak....
	if ( $atts->{id} =~ /^MJX-/ ) {
	    $atts->{stroke} = 'none';
	}
    }

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
		my @c = ( $cx, $cy,
			  $x + $d[0], $y - $d[1] );
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
		my $ey    = $y - shift(@d);
		$self->_dbg( "xo arc(%.2f,%.2f %.2f %d,%d %.2f,%.2f)",
			     $rx, $ry, $rot, $large, $sweep, $ex, $ey );

		# for circular arcs.
		if ( $rx == $ry ) {
		    $self->_dbg( "circular_arc(%.2f,%.2f %.2f,%.2f %.2f %d %d %d)",
				 $cx, $cy, $ex, $ey, $rx, 0, $large, 1-$sweep );
		    $self->circular_arc( $cx, $cy, $ex, $ey,
					 $rx, 0, $large, 1-$sweep );
		}
		else {
		    $self->_dbg( "elliptic_arc(%.2f,%.2f %.2f,%.2f %.2f,%.2f %d %d %d)",
				 $cx, $cy, $ex, $ey, $rx, $ry, 0, $large, 1-$sweep );
		    $self->elliptic_arc( $cx, $cy, $ex, $ey,
					 $rx, $ry, 0, $large, 1-$sweep );
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
    $self->css_pop;
}

################ Low level ################

use Math::Trig;

method curve ( @points ) {
    $self->_dbg( "+ xo curve( %.2f,%.2f %.2f,%.2f %.2f,%.2f )", @points );
    $self->xo->curve(@points);
    $self->_dbg( "-" );
}

# Circular arc ('bogen'), by PDF::API2 and anhanced by PDF::Builder.
method circular_arc ( $x1,$y1, $x2,$y2, $r, $move, $larc, $spf ) {

    my ($p0_x,$p0_y, $p1_x,$p1_y, $p2_x,$p2_y, $p3_x,$p3_y);
    my ($dx,$dy, $x,$y, $alpha,$beta, $alpha_rad, $d,$z, $dir, @points);

    if ($x1 == $x2 && $y1 == $y2) {
        die "bogen requires two distinct points";
    }
    if ($r <= 0.0) {
        die "bogen requires a positive radius";
    }
    $move = 0 if !defined $move;
    $larc = 0 if !defined $larc;
    $spf  = 0 if !defined $spf;

    $dx = $x2 - $x1;
    $dy = $y2 - $y1;
    $z = sqrt($dx**2 + $dy**2);
    $alpha_rad = asin($dy/$z); # |dy/z| guaranteed <= 1.0
    $alpha_rad = pi - $alpha_rad if $dx < 0;

    # alpha is direction of vector P1 to P2
    $alpha = rad2deg($alpha_rad);
    # use the complementary angle for flipped arc (arc center on other side)
    # effectively clockwise draw from P2 to P1
    $alpha -= 180 if $spf;

    $d = 2*$r;
    # z/d must be no greater than 1.0 (arcsine arg)
    if ($z > $d) { 
        $d = $z;  # SILENT error and fixup
        $r = $d/2;
    }

    $beta = rad2deg(2*asin($z/$d));
    # beta is the sweep P1 to P2: ~0 (r very large) to 180 degrees (min r)
    $beta = 360-$beta if $larc;  # large arc is remainder of small arc
    # for large arc, beta could approach 360 degrees if r is very large

    # always draw CW (dir=1)
    # note that start and end could be well out of +/-360 degree range
    @points = arctocurve($r,$r, 90+$alpha+$beta/2,90+$alpha-$beta/2, 1);

    if ($spf) {  # flip order of points for reverse arc
        my @pts = @points;
        @points = ();
        while (@pts) {
            $y = pop @pts;
            $x = pop @pts;
            push(@points, $x,$y);
        }
    }

    $p0_x = shift @points;
    $p0_y = shift @points;
    $x = $x1 - $p0_x;
    $y = $y1 - $p0_y;

    $self->move($x1,$y1) if $move;

    while (scalar @points > 0) {
        $p1_x = $x + shift @points;
        $p1_y = $y + shift @points;
        $p2_x = $x + shift @points;
        $p2_y = $y + shift @points;
        # if we run out of data points, use the end point instead
        if (scalar @points == 0) {
            $p3_x = $x2;
            $p3_y = $y2;
        } else {
            $p3_x = $x + shift @points;
            $p3_y = $y + shift @points;
        }
        $self->curve($p1_x,$p1_y, $p2_x,$p2_y, $p3_x,$p3_y);
        shift @points;
        shift @points;
    }

    return $self;
}

# Elliptic arc ('bogen_ellip'), by PDF::Builder.
method elliptic_arc ( $x1,$y1, $x2,$y2, $rx,$ry, $move, $larc, $spf) {
     my $context = $self; 	# temp

     my ($p0_x,$p0_y, $p1_x,$p1_y, $p2_x,$p2_y, $p3_x,$p3_y);
     my ($dx,$dy, $x,$y, $alpha,$beta, $alpha_rad, $d,$z, $dir, @points);

     if ($x1 == $x2 && $y1 == $y2) {
         die "bogen_ellip requires two distinct points";
     }
     if ($rx <= 0.0) {
         die "bogen_ellip requires a positive x radius";
     }
     if ($ry <= 0.0) {
         die "bogen_ellip requires a positive y radius";
     }
     $move = 0 if !defined $move;
     $larc = 0 if !defined $larc; # default 0 = take smaller arc
     $spf  = 0 if !defined $spf;  # default 0 = do NOT mirror (flip) arc

     $dx = $x2 - $x1;
     $dy = $y2 - $y1;
     $z = sqrt($dx**2 + $dy**2);
     $alpha_rad = asin($dy/$z); # |dy/z| guaranteed <= 1.0
     $alpha_rad = pi - $alpha_rad if $dx < 0;

     # alpha is direction of vector P1 to P2
     $alpha = rad2deg($alpha_rad);
     # use the complementary angle for flipped arc (arc center on other side)
     # effectively clockwise draw from P2 to P1
     $alpha -= 180 if $spf;

#   $d = 2*$r;
     if ($rx > $ry) {  # pick larger radius
         $d = 2*$rx;
     } else {
         $d = 2*$ry;
     }
     # z/d must be no greater than 1.0 (arcsine arg)
     if ($z > $d) {
#       $d = $z;  # SILENT error and fixup
#       $r = $d/2;
     }

     $beta = rad2deg(2*asin($z/$d));
print "z=$z, d=$d, alpha=$alpha, beta=$beta\n";
     # beta is the sweep P1 to P2: ~0 (r very large) to 180 degrees (min dr)
     $beta = 360-$beta if $larc;  # large arc is remainder of small arc
     # for large arc, beta could approach 360 degrees if r is very large

     # always draw CW (dir=1)
     # note that start and end could be well out of +/-360 degree range
     @points = arctocurve($rx,$ry, 90+$alpha+$beta/2,90+$alpha-$beta/2, 1);

     if ($spf) {  # flip order of points for reverse arc
         my @pts = @points;
         @points = ();
         while (@pts) {
             $y = pop @pts;
             $x = pop @pts;
             push(@points, $x,$y);
         }
     }

     $p0_x = shift @points;
     $p0_y = shift @points;
     $x = $x1 - $p0_x;
     $y = $y1 - $p0_y;

#   $self->move($x1,$y1) if $move;
     $context->move($x1,$y1) if $move;

     while (scalar @points > 0) {
         $p1_x = $x + shift @points;
         $p1_y = $y + shift @points;
         $p2_x = $x + shift @points;
         $p2_y = $y + shift @points;
         # if we run out of data points, use the end point instead
         if (scalar @points == 0) {
             $p3_x = $x2;
             $p3_y = $y2;
         } else {
             $p3_x = $x + shift @points;
             $p3_y = $y + shift @points;
         }
#       $self->curve($p1_x,$p1_y, $p2_x,$p2_y, $p3_x,$p3_y);
         $context->curve($p1_x,$p1_y, $p2_x,$p2_y, $p3_x,$p3_y);
         shift @points;
         shift @points;
     }

#   return $self;
     return $context;
}

# Arc to curve, by PDF::API2 and enhanced by PDF::Builder.
# input: x and y axis radii
#        sweep start and end angles
#        sweep direction (0=CCW (default), or 1=CW)
# output: two endpoints and two control points for
#           the Bezier curve describing the arc
# maximum 30 degrees of sweep: is broken up into smaller
#   arc segments if necessary
# if crosses 0 degree angle in either sweep direction, split there at 0
# if alpha=beta (0 degree sweep) or either radius <= 0, fatal error
sub arctocurve {
     my ($rx,$ry, $alpha,$beta, $dir) = @_;

     if (!defined $dir) { $dir = 0; }  # default is CCW sweep
     # check for non-positive radius
     if ($rx <= 0 || $ry <= 0) {
     die "curve request with radius not > 0 ($rx, $ry)";
     }
     # check for zero degrees of sweep
     if ($alpha == $beta) {
     die "curve request with zero degrees of sweep ($alpha to $beta)";
     }

     # constrain alpha and beta to 0..360 range so 0 crossing check works
     while ($alpha < 0.0)   { $alpha += 360.0; }
     while ( $beta < 0.0)   {  $beta += 360.0; }
     while ($alpha > 360.0) { $alpha -= 360.0; }
     while ( $beta > 360.0) {  $beta -= 360.0; }

     # Note that there is a problem with the original code, when the 0 degree
     # angle is crossed. It especially shows up in arc() and pie(). Therefore,
     # split the original sweep at 0 degrees, if it crosses that angle.
     if (!$dir && $alpha > $beta) { # CCW pass over 0 degrees
       if      ($alpha == 360.0 && $beta == 0.0) { # oddball case
         return (arctocurve($rx,$ry, 0.0,360.0, 0));
       } elsif ($alpha == 360.0) { # alpha to 360 would be null
         return (arctocurve($rx,$ry, 0.0,$beta, 0));
       } elsif ($beta == 0.0) { # 0 to beta would be null
         return (arctocurve($rx,$ry, $alpha,360.0, 0));
       } else {
         return (
             arctocurve($rx,$ry, $alpha,360.0, 0),
             arctocurve($rx,$ry, 0.0,$beta, 0)
         );
       }
     }
     if ($dir && $alpha < $beta) { # CW pass over 0 degrees
       if      ($alpha == 0.0 && $beta == 360.0) { # oddball case
         return (arctocurve($rx,$ry, 360.0,0.0, 1));
       } elsif ($alpha == 0.0) { # alpha to 0 would be null
         return (arctocurve($rx,$ry, 360.0,$beta, 1));
       } elsif ($beta == 360.0) { # 360 to beta would be null
         return (arctocurve($rx,$ry, $alpha,0.0, 1));
       } else {
         return (
             arctocurve($rx,$ry, $alpha,0.0, 1),
             arctocurve($rx,$ry, 360.0,$beta, 1)
         );
       }
     }

     # limit arc length to 30 degrees, for reasonable smoothness
     # none of the long arcs or short resulting arcs cross 0 degrees
     if (abs($beta-$alpha) > 30) {
         return (
             arctocurve($rx,$ry, $alpha,($beta+$alpha)/2, $dir),
             arctocurve($rx,$ry, ($beta+$alpha)/2,$beta, $dir)
         );
     } else {
        # Note that we can't use deg2rad(), because closed arcs (circle() and
        # ellipse()) are 0-360 degrees, which deg2rad treats as 0-0 radians!
         $alpha = ($alpha * pi / 180);
         $beta  = ($beta * pi / 180);

         my $bcp = (4.0/3 * (1 - cos(($beta - $alpha)/2)) / sin(($beta - $alpha)/2));
         my $sin_alpha = sin($alpha);
         my $sin_beta  = sin($beta);
         my $cos_alpha = cos($alpha);
         my $cos_beta  = cos($beta);

         my $p0_x = $rx * $cos_alpha;
         my $p0_y = $ry * $sin_alpha;
         my $p1_x = $rx * ($cos_alpha - $bcp * $sin_alpha);
         my $p1_y = $ry * ($sin_alpha + $bcp * $cos_alpha);
         my $p2_x = $rx * ($cos_beta  + $bcp * $sin_beta);
         my $p2_y = $ry * ($sin_beta  - $bcp * $cos_beta);
         my $p3_x = $rx * $cos_beta;
         my $p3_y = $ry * $sin_beta;

         return ($p0_x,$p0_y, $p1_x,$p1_y, $p2_x,$p2_y, $p3_x,$p3_y);
     }
}

1;
