#! perl

#### TODO
#
# generalized units handler
# generic split (w/s, comma, ...)

use v5.26;
use Object::Pad;
use feature 'signatures';
no warnings 'experimental::signatures';
use Carp;
use utf8;

package PDF::SVG;

our $VERSION = 0.02;

my $debug = 0;
my $grid = 0;
my $debug_styles = 0;
my $trace = 0;

our $indent = "";

use PDF::SVG::CSS;
use PDF::SVG::PAST;
use DDumper;

################ General methods ################

sub new ( $pkg, $ps, %atts ) {
    my $self = bless { ps => $ps, %atts } => $pkg;
    $debug = $atts{debug};
    $grid= $atts{grid};
    $debug_styles = $atts{debug_styles} || $debug > 1;
    $trace = $atts{trace};
    $indent = "";
    $self;
}

sub xdbg ( $fmt, @args ) {
    if ( $fmt =~ /\%/ ) {
	warn( $indent, sprintf( $fmt, @args), "\n" );
    }
    else {
	warn( $indent, join( "", $fmt, @args ), "\n" );
    }
}

sub _dbg ( $fmt, @args ) {
    return unless $trace;
    xdbg( $fmt, @args );
}

# This is (currently) ugly --
#
# <svg ...>
#  <style>...</style>
#  <def>....</def>
#  ...
#  </svg>
# <svg ...>
#  ... the styles and defs persist!
#  </svg>

my $css;

sub process_file ( $self, $file ) {

    # Load the SVG file.
    open( my $fd, '<:utf8', $file )
      or die(" $file: $!\n" );
    my $svg = SVG::Parser->new->parsefile($fd);
    close($fd);
    return unless $svg;

    # CSS persists over svgs, but not over files.
    $css = PDF::SVG::CSS->new;

    # Search for svg elements and process them.
    my $ret = $self->search($svg);

    # Return (hopefully a stack of XObjects).
    return $ret;
}

sub search ( $self, $e ) {
    local $indent = $indent . "  ";

    # In general, we'll have an XHTML tree with one or more <sgv>
    # elements.

    my $en = $e->getElementName;
    if ( $en eq "svg" ) {
	$indent = "";
	$self->handle_svg($e);
	# Adds results to $self->{xoforms}.
    }
    else {
	# Skip recursively.
	_dbg( "$en (ignored)" );
	for ( $e->getChildren ) {
	    next if $_->{type} eq 't';
	    $self->search($_);
	}
    }

    # Hopefully we collected some <svg> nodes.
    return $self->{xoforms};
}

sub handle_svg ( $self, $e ) {
    _dbg( $e->getElementName, " ====" );
    local $indent = $indent . "  ";

    my $xo =
      $debug
      ? PDF::SVG::PAST->new( pdf => $self->{ps}->{pr}->{pdf} )
      : $self->{ps}->{pr}->{pdf}->xo_form;

    # Turn the <svg> element into an SVG:Element.
    $e = SVG::Element->new( $e, $self, undef, $css );

    # If there are <style> elements, these must be processed first.
    my $cdata = "";
    for ( $e->getChildren ) {
	next unless $_->{type} eq 'e' && $_->{name} eq 'style';
	for my $t ( @{ $_->{content} } ) {
	    $cdata .= $t->{content};
	}
    }
    if ( $cdata =~ /\S/ ) {
	$css->read_string($cdata);
    }
    $e->{css} = $self->{css} = $css;

    my $atts = $e->getAttributes;
    my $width  = delete( $atts->{width} ) || 595;
    my $height = delete( $atts->{height}) || 842;
    s/p[tx]$// for $width, $height;
    s;([\d.]+)mm;sprintf("%.2f",$1*72/25.4);ge for $width, $height;
    s;([\d.]+)cm;sprintf("%.2f",$1*72/2.54);ge for $width, $height;
    s;([\d.]+)ex;sprintf("%.2f",$1*5);ge for $width, $height; # HACK
    my $vbox   = delete( $atts->{viewBox} ) || "0 0 $width $height";

    delete $atts->{$_} for qw( xmlns:xlink xmlns:svg xmlns version );
    my $style = $e->css_push($atts);

    $vbox =~ s/\s*,\s*/ /g;
    my @bb = split( ' ', $vbox );
    _dbg( "bb %.2f %.2f %.2f %.2f", @bb );
    $xo->bbox(@bb);
    # <svg> coordinates are topleft down, so translate.
    $xo->transform( translate => [ $bb[0], $bb[3] ] );

    # Set up result forms.
    # Currently we rely on the <svg> to supply the correct viewBox.
    push( @{ $self->{xoforms} },
	  { xo      => $xo,
	    vwidth  => $width,
	    vheight => $height,
	    width   => $bb[2] - $bb[0],
	    height  => $bb[3] - $bb[1] } );

    # Establish currentColor.
    for ( $css->find("fill") ) {
	$xo->fill_color($_)
	  unless $_   eq 'none'
	  or     $_   eq 'currentColor';
    }
    for ( $css->find("stroke") ) {
	$xo->stroke_color($_)
	  unless $_ eq 'none'
	  or     $_ eq 'currentColor';
    }
    grid( $self->{xoforms}->[-1] ) if $grid;
    for ( $e->getChildren ) {
	$_->traverse;
    }

    $e->css_pop;
}

################ SVG ################

package SVG::Text;

our @ISA = qw ( SVG::Element );

package SVG::Element;

use DDumper;

our @ISA = qw ( XML::Tiny::_Element );

*_dbg = \&PDF::SVG::_dbg;

sub new ( $pkg, $e, $parent = undef, $svg = undef, $css = undef ) {
    $parent //= $pkg;
    $pkg = ref($pkg) || $pkg;
    $svg //= $parent->{svg} // $parent;
    $css //= $parent->{css} // Carp::confess("Missing CSS in SVG::Element::new");
    my $self = { %$e,
		 parent => $parent,
		 svg => $svg,
		 css => $css };
    bless $self => $pkg;
}

sub traverse ( $self ) {

    local $indent = $indent . "  ";
    my $en = $self->getElementName;

    if ( my $p = $self->can("process_$en") ) {
	_dbg("handling $en");
	$self->$p;
    }
    elsif ( ref($self->{content}) eq 'ARRAY' ) {
	_dbg( "traverse $en" );
	warn("SVG: Not implemented: $en\n") unless $en eq "style";
	for ( $self->getChildren ) {
	    next if $_->{type} eq 't';
	    $self->new($_)->traverse;
	}
    }
    else {
	_dbg( "skip '$en'" );
    }
}

sub getChildren ( $self ) {
    my @res;
    unless ( ref($self->{content}) eq 'ARRAY' ) {
	Carp::confess("ARRAY");
    }
    for ( @{ $self->{content} } ) {
	if ( $_->{type} eq 'e' ) {
	    push( @res, $self->new($_) );
	}
	elsif ( $_->{type} eq 't' ) {
	    push( @res, SVG::Text->new( $_, $self ) );
	}
	else {
	    die("Unhandled node type ", $_->{type});
	}
    }
    return @res;
}

sub getAttributes ( $self ) {
    \%{ $self->{attrib} // {} };
}

sub css_push ( $self, $atts ) {
    Carp::confess unless $self->{css};
    my $ret = $self->{css}->push($atts);
    if ( $debug_styles ) {
	warn( "CSS[", $self->{css}->level, "]: ",
	      $self->can("getElementName")
	      ? ( $self->getElementName . " " )
	      : (),
	      DDumper($ret) );
    }
    $ret;
}

sub css_pop ( $self ) {
    $self->{css}->pop;
}

sub getCDATA ( $self ) {
    my $res = "";
    for ( @{ $self->{content} } ) {
	$res .= "\n" . $_->{content} if $_->{type} eq 't';
    }
    $res;
}

################ Texts and Paths ################

sub process_text ( $self ) {
    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my %atts = %$atts;		# debug
    my $x  = delete($atts->{x}) || 0;
    my $y  = delete($atts->{y}) || 0;
    my $dx = delete($atts->{dx}) || 0;
    my $dy = delete($atts->{dy}) || 0;
    my $tf = delete($atts->{transform}) || "";

    my $style = $self->css_push($atts);
    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";

    my $text = "";

    my $color = $style->{color};
    my $anchor = $style->{'text-anchor'} || "left";
    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};

    _dbg( $self->getElementName, " ",
	  defined($atts{x}) ? ( " x=$x" ) : (),
	  defined($atts{y}) ? ( " y=$y" ) : (),
	  defined($atts{dx}) ? ( " dx=$dx" ) : (),
	  defined($atts{dy}) ? ( " dy=$dy" ) : (),
	  defined($style->{"text-anchor"})
	  ? ( " anchor=\"$anchor\"" ) : (),
	  defined($style->{"transform"})
	  ? ( " transform=\"$tf\"" ) : (),
	  "\n" );

    # We assume that if there is an x/y list, there is one single text
    # argument.

    my @c = $self->getChildren;

    if ( $x =~ /,/ ) {
	if ( @c > 1 || ref($c[0]) !~ /::Text$/ ) {
	    die("text: Cannot combine coordinate list with multiple elements\n");
	}
	$x = [ split( /,/, $x ) ];
	$y = [ split( /,/, $y ) ];
	$text = [ split( //, $c[0]->{content} ) ];
	die( "\"", $self->getCDATA, "\" ", 0+@$x, " ", 0+@$y, " ", 0+@$text )
	  unless @$x == @$y && @$y == @$text;
    }
    else {
	$x = [ $x ];
	$y = [ $y ];
    }

    _dbg( "xo save" );
    $xo->save;
    my $ix = $x->[0];
    my $iy = $y->[0];
    my ( $ex, $ey );

#    my ( $dx, $dy, $scale ) = ( 0, 0, 1 );
    my $scale = 1;
    if ( $tf ) {
	( $dx, $dy ) = ( $1, $2 )
	  if $tf =~ /translate\((-?[.\d]+),(-?[.\d]+)\)/;
	$scale = $1
	  if $tf =~ /scale\((-?[.\d]+)\)/;
	warn("TF: $dx, $dy, $scale") if $trace;
    }
    # NOTE: rotate applies to the individual characters, not the text
    # as a whole.

    if ( $color ) {
	$xo->fill_color($color);
    }

    if ( @$x > 1 ) {
      for ( @$x ) {
	if ( $tf ) {
	    _dbg( "X %.2f = %.2f + %.2f",
		  $dx + $_, $dx, $_ );
	    _dbg( "Y %.2f = - %.2f - %.2f",
		  - $dy - $y->[0], $dy, $y->[0] );
	}
	my $x = $dx + $_;
	my $y = - $dy - shift(@$y);
	_dbg( "txt* translate( %.2f, %.2f )%s %x",
	      $x, $y,
	      $scale != 1 ? sprintf(" scale( %.1f )", $scale) : "",
	      ord($text->[0]));
	#	$xo-> translate( $x, $y );
	$xo->save;
	$xo->transform( translate => [ $x, $y ],
			$scale != 1 ? ( scale => [ $scale, $scale ] ) : (),
		      );
	my %o = ();
	$o{align} = $anchor eq "end"
	  ? "right"
	  : $anchor eq "middle" ? "center" : "left";
	$xo->textstart;
	$xo->font( $self->makefont($style));
	$xo->text( shift(@$text), %o );
	$xo->textend;
	$xo->restore;
      }
    }
    else {
	$_ = $x->[0];
	if ( $tf ) {
	    _dbg( "X %.2f = %.2f + %.2f",
		  $dx + $_, $dx, $_ );
	    _dbg( "Y %.2f = - %.2f - %.2f",
		  - $dy - $y->[0], $dy, $y->[0] );
	}
	my $x = $dx + $_;
	my $y = - $dy - shift(@$y);
	_dbg( "txt translate( %.2f, %.2f )%s",
	      $x, $y,
	      $scale != 1 ? sprintf(" scale( %.1f )", $scale) : "" );
	#	$xo-> translate( $x, $y );
	my %o = ();
	$o{align} = $anchor eq "end"
	  ? "right"
	  : $anchor eq "middle" ? "center" : "left";
	for my $c ( @c ) {
	    if ( $c->{type} eq 't' ) {
		_dbg( "xo save" );
		$xo->save;
		$xo->transform( translate => [ $x, $y ],
				$scale != 1 ? ( scale => [ $scale, $scale ] ) : (),
			      );
		$scale = 1;		# no more scaling.

		$xo->textstart;
		$xo->font( $self->makefont($style));

		$x += $xo->text( $c->{content}, %o );
		$xo->textend;
		if ( $style->{'outline-style'} ) {
		    my ($fn,$sz) = @{[$self->makefont($style)]};
		    $xo->line_width( $style->{'outline-width'} || 1 );
		    $xo->stroke_color( $style->{'outline-color'} || 'black' );
		    my $d = $style->{'outline-offset'} || 1;
		    $xo->rectangle( -$d,
				    -$d+$sz*$fn->descender/1000,
				    $x-$ix+2*$d,
				    2*$d+$sz*$fn->ascender/1000 );
		    $xo->stroke;
		}
		_dbg( "xo restore" );
		$xo->restore;
		$ex = $x; $ey = $y;
	    }
	    elsif ( $c->{type} eq 'e' && $c->{name} eq 'tspan' ) {
		_dbg( "xo save" );
		$xo->save;
		if ( defined($c->{attrib}->{x}) ) {
		    $x = 0;
		}
		if ( defined($c->{attrib}->{y}) ) {
		    $y = 0;
		}
		$xo->transform( translate => [ $x, $y ],
				$scale != 1 ? ( scale => [ $scale, $scale ] ) : (),
			      );
		$scale = 1;		# no more scaling.
		my ( $x0, $y0 ) = $c->process_tspan;
		$x += $x0; $y += $y0;
		_dbg("tspan moved to $x, $y");
		_dbg( "xo restore" );
		$xo->restore;
		$ex = $x; $ey = $y;
	    }
	}
    }
    _dbg( "xo restore" );
    $xo->restore;

    $self->css_pop;
}

sub process_tspan ( $self ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my %atts = %$atts;		# debug
    my $x  = delete($atts->{x}) || 0;
    my $y  = delete($atts->{y}) || 0;
    my $dx = delete($atts->{dx}) || 0;
    my $dy = delete($atts->{dy}) || 0;

    my $style = $self->css_push($atts);
    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";

    my $text = "";

    $style->{'font-size'} =~ s/px$//;
    $dx = $1 * $style->{'font-size'} if $dx =~ /^([.\d]+)em$/;
    $dy = $1 * $style->{'font-size'} if $dy =~ /^([.\d]+)em$/;

    my $color = $style->{color};
    my $anchor = $style->{'text-anchor'} || "left";
    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};

    _dbg( $self->getElementName, " ",
	  defined($atts{x})  ? ( " x=$x" ) : (),
	  defined($atts{y})  ? ( " y=$y" ) : (),
	  defined($atts{dx}) ? ( " dx=$dx" ) : (),
	  defined($atts{dy}) ? ( " dy=$dy" ) : (),
	  defined($style->{"text-anchor"})
	  ? ( " anchor=\"$anchor\"" ) : (),
	  "\n" );

    my @c = $self->getChildren;

    if ( $color ) {
	$xo->fill_color($color);
    }

    {
	my $x = $dx + $x;
	my $y = - $dy - $y;

	my %o = ();
	$o{align} = $anchor eq "end"
	  ? "right"
	  : $anchor eq "middle" ? "center" : "left";

	if ( 0 && $x && !$y && $o{align} eq "left" ) {
	    $o{indent} = $x;
	    _dbg( "txt indent %.2f", $x );
	}
	elsif ( $x || $y ) {
	    _dbg( "txt translate( %.2f, %.2f )", $x, $y );
	}

	for my $c ( @c ) {
	    $xo->save;
	    $xo->transform( translate => [ $x, $y ] );
	    if ( $c->{type} eq 't' ) {
		$xo->textstart;
		$xo->font( $self->makefont($style));
		$x += $xo->text( $c->{content}, %o );
		$xo->textend;
	    }
	    elsif ( $c->{type} eq 'e' && $c->{name} eq 'tspan' ) {
		my ( $x0, $y0 ) = $c->process_tspan;
		$x += $x0; $y += $y0;
		_dbg("tspan moved to $x, $y");
	    }
	    $xo->restore;
	}
	$self->css_pop;
	return wantarray ? ( $x, $y ) : $x;
    }
}

sub _paintsub ( $xo, $style ) {
    sub {
	if ( $style->{stroke}
	     && $style->{stroke} ne 'none'
	     && $style->{stroke} ne 'transparent'
	   ) {
	    if ( $style->{fill}
		 && $style->{fill} ne 'none'
		 && $style->{fill} ne 'transparent'
	       ) {
		$xo->paint;
	    }
	    else {
		$xo->stroke;
	    }
	}
	elsif ( $style->{fill}
		&& $style->{fill} ne 'none'
		&& $style->{fill} ne 'transparent'
	      ) {
	    $xo->fill;
	}
    }
}

sub process_path ( $self ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my $d  = delete($atts->{d});
    return unless $d;		# noop

    my $style = $self->css_push($atts);
    $atts->{d} = $d;
    my $x = 0;
    my $y = 0;
    _dbg( $self->getElementName, " x=$x y=$y" );
    local $indent = $indent . "  ";

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( "xo save" );
    $xo->save;

    $self->set_graphics($style);

    # Starting point of this path.
    my $x0 = $x;
    my $y0 = $y;

    $d =~ s/([a-z])([a-z])/$1 $2/gi;
    $d =~ s/([a-z])([-\d])/$1 $2/gi;
    $d =~ s/([-\d])([a-z])/$1 $2/gi;
    $d =~ s/,/ /g;
    my @d = split( ' ', $d );

    my $open;

    my $paint = _paintsub( $xo, $style );

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
	    _dbg( "xo move(%.2f,%.2f)", $x, $y );
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
	    $ix = $x, $iy = $y unless $open++;
	    _dbg( "xo hline(%.2f)", $d[0] );
	    $x += shift(@d);
	    $xo->hline($x);
	    ( $cx, $cy ) = ( $x, $y );
	    next;
	}

	# Vertical LineTo.
	if ( $op eq "v" ) {
	    $ix = $x, $iy = $y unless $open++;
	    _dbg( "xo vline(%.2f)", $d[0] );
	    $y -= shift(@d);
	    $xo->vline($y);
	    ( $cx, $cy ) = ( $x, $y );
	    next;
	}

	# Generic LineTo.
	if ( $op eq "l" ) {
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $x, $iy = $y unless $open++;
		$x += shift(@d); $y -= shift(@d);
		_dbg( "xo line(%.2f,%.2f)", $x, $y );
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
		_dbg( "xo curve(%.2f,%.2f %.2f,%.2f %.2f,%.2f)", @c );
		$xo->curve(@c);
		$x = $c[4]; $y = $c[5]; # current point
		( $cx, $cy ) = ( $x, $y );

		# Check if followed by S-curve.
		if ( @d > 7 && lc( my $op = $d[6] ) eq "s" ) {
		    # Turn S-curve into C-curve.
		    # New cp1 becomes reflection of cp2.
		    my $rx = $x + $d[4] - $d[2];
		    my $ry = $y - ($d[5] - $d[3]);
		    splice( @d, 0, 7 );
		    unshift( @d, $op eq 's' ? 'c' : 'C', $rx, -$ry );
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
		$ix = $x, $iy = $y unless $open++;
		my @c = ( $x + $d[0], $y - $d[1],
			  $x + $d[2], $y - $d[3] );
		nfi("standalone s-paths");
		unshift( @c, $x, -$y );
		_dbg( "xo curve(%.2f,%.2f %.2f,%.2f %.2f,%.2f)", @c );
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
		$ix = $x, $iy = $y unless $open++;
		my @c = ( $x + $d[0], $y - $d[1], # control point 1
			  $x + $d[2], $y - $d[3]  # end point
			);
		_dbg( "xo spline(%.2f,%.2f %.2f,%.2f)", @c );
		$xo->spline(@c);
		$x = $c[2]; $y = $c[3]; # current point
		( $cx, $cy ) = ( $x, $y );

		# Check if followed by T-curve.
		if ( @d > 5 && lc( my $op = $d[4] ) eq "t" ) {
		    # Turn T-curve into Q-curve.
		    # New cp becomes reflection of current cp.
		    my $rx = -$x + $d[1] - $d[0];
		    my $ry = $y - ($d[3] - $d[1]);
		    splice( @d, 0, 5 );
		    unshift( @d, $op eq 't' ? 'q' : 'Q', -$rx, -$ry );
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
		$ix = $x, $iy = $y unless $open++;
		my @c = ( $x, $y,
			  $x + $d[0], $y - $d[1] );
		nfi("standalone t-paths");
		unshift( @c, $x, -$y );
		_dbg( "xo spline(%.2f,%.2f %.2f,%.2f)", @c );
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
		_dbg( "xo arc(%.2f,%.2f %.2f %d,%d %.2f,%.2f)",
		      $rx, $ry, $rot, $large, $sweep, $ex, $ey );

		# Hard... For the time being use the (obsolete) 'bogen'
		# for circular arcs.
		if ( $rx == $ry ) {
		    $xo->bogen( $cx, $cy, $ex, $ey,
				$rx, 0, $large, 1-$sweep );
		}
		else {
		    nfi("elliptic arc paths");
		}
		$ix = $x, $iy = $y unless $open++;
		( $cx, $cy ) = ( $ex, $ey );
	    }
	    next;
	}

	# Close path and paint.
	if ( lc($op) eq "z" ) {
	    _dbg( "xo $op" );
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
    _dbg( "xo restore" );
    $xo->restore;
    $self->css_pop;
}

sub process_rect ( $self ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my $x  = delete($atts->{x}) || 0;
    my $y  = delete($atts->{y}) || 0;
    my $w  = delete($atts->{width}) || 0;
    my $h  = delete($atts->{height}) || 0;

    s/p[tx]$// for $x, $y, $w, $h;

    my $style = $self->css_push($atts);

    _dbg( $self->getElementName, " x=$x y=$y w=$w h=$h" );
    local $indent = $indent . "  ";

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( "xo save" );
    $xo->save;

    $self->set_graphics($style);

    my $paint = _paintsub( $xo, $style );

    $xo->rectangle( $x, -$y, $x+$w, -$y-$h );
    $paint->();

    _dbg( "xo restore" );
    $xo->restore;
    $self->css_pop;
}

sub process_line ( $self ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my $x1  = delete($atts->{x1}) || 0;
    my $y1  = delete($atts->{y1}) || 0;
    my $x2  = delete($atts->{x2}) || 0;
    my $y2  = delete($atts->{y2}) || 0;

    s/p[tx]$// for $x1, $y1, $x1, $y2;

    my $style = $self->css_push($atts);

    _dbg( $self->getElementName, " x1=$x1 y1=$y1 x2=$x2 y2=$y2" );
    local $indent = $indent . "  ";

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( "xo save" );
    $xo->save;

    $self->set_graphics($style);

    my $paint = _paintsub( $xo, $style );

    $xo->move( $x1, -$y1 );
    $xo->line( $x2, -$y2 );
    $paint->();

    _dbg( "xo restore" );
    $xo->restore;
    $self->css_pop;
}

sub process_polygon ( $self) {
    $self->process_polyline("close");
}

sub process_polyline ( $self, $close = 0 ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my $points  = delete($atts->{points}) || "";

    my @d;
    for ( split( ' ', $points ) ) {
	my ( $x, $y ) = split( ',', $_ );
	s/p[tx]$// for $x, $y;
	push( @d, $x, -$y );
    }

    my $style = $self->css_push($atts);

    _dbg( $self->getElementName, " points=$points" );
    local $indent = $indent . "  ";

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( "xo save" );
    $xo->save;

    $self->set_graphics($style);

    my $paint = _paintsub( $xo, $style );

    my $op = "move";
    if ( @d ) {
	$xo->move( $d[0], $d[1] );
	$xo->polyline( @d[2 .. $#d] );
	$xo->close if $close;
	$paint->();
    }

    _dbg( "xo restore" );
    $xo->restore;
    $self->css_pop;
}

sub process_circle ( $self ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my $cx  = delete($atts->{cx}) || 0;
    my $cy  = delete($atts->{cy}) || 0;
    my $r  = delete($atts->{r}) || 0;

    s/p[tx]$// for $cx, $cy, $r;

    my $style = $self->css_push($atts);

    _dbg( $self->getElementName, " cx=$cx cy=$cy r=$r" );
    local $indent = $indent . "  ";

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( "xo save" );
    $xo->save;

    $self->set_graphics($style);

    my $paint = _paintsub( $xo, $style );

    $xo->circle( $cx, -$cy, $r );
    $paint->();

    _dbg( "xo restore" );
    $xo->restore;
    $self->css_pop;
}

sub process_image ( $self ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my $x  = delete($atts->{x}) || 0;
    my $y  = delete($atts->{y}) || 0;
    my $width  = delete($atts->{width})  || 0;
    my $height = delete($atts->{height}) || 0;
    my $link = delete($atts->{'xlink:href'});
    s/p[tx]$// for $x, $y, $width, $height;

    my $style = $self->css_push($atts);

    my $par = $style->{'preserveAspectRatio'};
    _dbg( $self->getElementName, " x=$x y=$y w=$width h=$height" );
    local $indent = $indent . "  ";

    my $img;
    if ( $link =~ m!^data:image/(png|jpe?g);(base64),(.*)$! ) {
	# In-line image asset.
	require MIME::Base64;
	require Image::Info;
	require IO::String;
	my $type = $1;
	my $enc = $2;
	my $data = MIME::Base64::decode($3);
	unless ( $enc eq "base64" ) {
	    warn("SVG: Unhandled encoding in image: $enc\n");
	    $self->css_pop, return;
	}

	# Get info.
	my $info = Image::Info::image_info(\$data);
	if ( $info->{error} ) {
	    warn($info->{error});
	    $self->css_pop, return;
	}

	# Place the image.
	$img = $self->{svg}->{ps}->{pr}->{pdf}->image(IO::String->new($data));
    }

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( "xo save" );
    $xo->save;
    $xo->transform( translate => [ $x, -$y-$height ] );
    $xo->image( $img, 0, 0, $width, $height );
    _dbg( "xo restore" );
    $xo->restore;
    $self->css_pop;
}

################ Recurse ################

sub process_svg ( $self ) {
    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";

    nfi("recursive svg elements");;
    my $savexo = $self->{svg}->{xoforms}->[-1]->{xo};

    my $xo =
      $debug
      ? PDF::SVG::PAST->new( pdf => $self->{ps}->{pr}->{pdf} )
      : $self->{ps}->{pr}->{pdf}->xo_form;

    my $atts = $self->getAttributes;
    my $width  = delete( $atts->{width} ) || 595;
    my $height = delete( $atts->{height}) || 842;
    s/p[tx]$// for $width, $height;
    s;([\d.]+)mm;sprintf("%.2f",$1*72/25.4);ge for $width, $height;
    my $vbox   = delete( $atts->{viewBox} ) || "0 0 $width $height";

    delete $atts->{$_} for qw( xmlns:xlink xmlns:svg xmlns version );
    my $style = $self->css_push($atts);

    # Set up result forms.
    # Currently we rely on the <svg> to supply the correct viewBox.
    push( @{ $self->{svg}->{xoforms} },
	  { xo     => $xo,
	    width  => $width,
	    height => $height } );

    my @bb = split( ' ', $vbox );
    _dbg( "bb %.2f %.2f %.2f %.2f", @bb );
    $xo->bbox(@bb);
    # <svg> coordinates are topleft down, so translate.
    $xo->transform( translate => [ $bb[0], $bb[3] ] );

    for ( $self->getChildren ) {
	$_->traverse;
    }

    $savexo->formimage( $xo, 0, -$height, 1 );

    pop(@{ $self->{svg}->{xoforms} });
    $self->css_pop;
}


################ Graphics context ################

sub process_g ( $self ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my $t  = delete($atts->{transform});
    my $style = $self->css_push($atts);

    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    my $x;
    my $y;
    my $scale;
    my @m;
    my %o;

    if ( $t ) {
	if ( $t =~ m/translate \( \s*
		     ([-.\d]+) [,\s] \s*
		     ([-.\d]+)
		     \s* \)/x ) {
	    $x = $1;
	    $y = $2;
	    _dbg( "xo translate( %.2f, %.2f )", $x, $y );
	}
	if ( $t =~ m/scale \( \s*
		     ([-.\d]+)
		     \s* \)/x ) {
	    $scale = $1;
	    _dbg( "xo scale( %.2f )", $scale );
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
	    _dbg( "xo matrix( %.2f %.2f %.2f %.2f %.2f %.2f)", @m );
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
	if ( defined($scale) ) {
	    $o{scale} = [ $scale, $scale ];
	}
	if ( %o ) {
	    _dbg( "xo save" );
	    $xo->save;
	    $xo->transform( %o );
	}
    }

    for ( $self->getChildren ) {
	$_->traverse;
    }

    if ( @m || %o ) {
	$xo->restore;
	_dbg( "xo restore" );
    }

    $self->css_pop;
}

sub atts ( $e ) {
    my $atts = "";
    my %h = %{$e->getAttributes};
    while ( my ($k,$v) = each(%h) ) {
	$atts .= " " if $atts;
	$atts .= "$k=\"$v\"";
    }
    return $atts ? "($atts)" : "";
}

sub set_graphics ( $self, $style ) {

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};

    my $lw = $style->{'stroke-width'} || 0.01;
    $xo->line_width($lw);
    _dbg( $self->getElementName, " stroke-width=", $lw );

    my $stroke = $style->{stroke};
    if ( lc($stroke) eq "currentcolor" ) {
	# Nothing. Use current.
    }
    elsif ( $stroke ne "none" ) {
	$stroke =~ s/\s+//g;
	if ( $stroke =~ /rgb\((\d+),(\d+),(\d+)\)/ ) {
	    $stroke = sprintf("#%02X%02X%02X", $1, $2, $3);
	}
	$xo->stroke_color($stroke);
	_dbg( $self->getElementName, " stroke=", $stroke );
    }

    my $fill = $style->{fill};
    if ( lc($fill) eq "currentcolor" ) {
	# Nothing. Use current.
    }
    elsif ( lc($fill) ne "none" && $fill ne "transparent" ) {
	$fill =~ s/\s+//g;
	if ( $fill =~ /rgb\((\d+),(\d+),(\d+)\)/ ) {
	    $fill = sprintf("#%02X%02X%02X", $1, $2, $3);
	}
	$xo->fill_color($fill);
	_dbg( $self->getElementName, " fill=", $fill );
    }

    if ( my $sda = $style->{'stroke-dasharray'}  ) {
	$sda =~ s/,/ /g;
	my @sda = split( ' ', $sda );
	_dbg( $self->getElementName, " sda=@sda" );
	$xo->line_dash_pattern(@sda);
    }

    return $style;
}

################ Definitions and use ################

sub process_defs ( $self ) {
    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";
    for ( $self->getChildren ) {
	$self->{svg}->{defs}->{ "#" . $_->getAttributes->{id} } = $_;
    }
}

sub process_use ( $self ) {

    my $atts = $self->getAttributes;
    return if $atts->{omit};	# for testing/debugging.

    my $x  = delete($atts->{x}) || 0;
    my $y  = delete($atts->{y}) || 0;
    my $xr = delete($atts->{"xlink:href"});
    my $style = $self->css_push($atts);

    $y = -$y;
    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( $self->getElementName, " ref=", $xr//"<undef>", " x=$x, y=$y" );
    local $indent = $indent . "  ";

    my $r = $self->{svg}->{defs}->{$xr};
    die("missing def for $xr") unless $r;

    $xo->save;
    $xo->transform( translate => [ $x, $y ] );
    $r->traverse;
    $xo->restore;
}

################ Ignored ################

sub process_title {
    _dbg( "SVG: Ignored: title" );
}

sub process_desc {
    _dbg( "SVG: Ignored: desc" );
}

sub nfi ( $tag ) {
    state $aw = {};
    warn("SVG: $tag are not fully implemented, expect strange results.")
      unless $aw->{$tag}++;
}

################ Styles and Fonts ################

sub makefont ( $self, $style ) {
    local $indent = $indent . "  ";

    my ( $fn, $sz, $em, $bd ) = ("Times-Roman", 12, 0, 0 );

    $fn = $style->{'font-family'} // "Times-Roman";
    $sz = $style->{'font-size'} || 12;
    $sz = $1 if $sz =~ /^([.\d]+)p[xt]/; # TODO: units
    $em = $style->{'font-style'}
      && $style->{'font-style'} =~ /^(italic|oblique)$/;
    $bd = $style->{'font-weight'}
      && $style->{'font-weight'} =~ /^(bold|black)$/;

    if ( $fn =~ /^(sans|helvetica|(?:text,)?sans-serif)$/i ) {
	$fn = $bd
	  ? $em ? "Helvetica-BoldOblique" : "Helvetica-Bold"
	  : $em ? "Helvetica-Oblique" : "Helvetica";
    }
    elsif ( $fn =~ /^abc2svg(?:\.ttf)?/ or $fn eq "music" ) {
	$fn = "abc2svg.ttf";
    }
    elsif ( $fn =~ /^musejazz\s*text$/ ) {
	$fn = "MuseJazzText.otf";
    }
    else {
	$fn = $bd
	  ? $em ? "Times-BoldItalic" : "Times-Bold"
	  : $em ? "Times-Italic" : "Times-Roman";
    }
    my $font = $self->{svg}->{ps}->{pr}->{pdf}->{__fontcache__}->{$fn} //= do {
	$self->{svg}->{ps}->{pr}->{pdf}->font($fn);
    };
    ( $font, $sz, $fn );
}

################ Service ################

sub PDF::SVG::grid ( $xof ) {
    my $d = 10;
    my $c = 6;
    my $xo = $xof->{xo};
    my $w = $xof->{width};
    my $h = $xof->{height};

    _dbg("grid (for debugging)");
    local $indent = $indent . "  ";
    $xo->save;
    $xo->stroke_color("#bbbbbb");
    $xo->line_width(0.1);
    for ( my $x = 0; $x <= $w; $x += $d ) {
	if ( --$c == 0 ) {
	    $xo->line_width(1);
	}
	$xo->move( $x, 0 );
	$xo->vline(-$h);
	$xo->stroke;
	if ( $c == 0 ) {
	    $xo->line_width(0.2);
	    $c = 5;
	}
    }
    $c = 6;
    for ( my $y = 0; $y <= $h; $y += $d ) {
	if ( --$c == 0 ) {
	    $xo->line_width(1);
	}
	$xo->move( 0, -$y );
	$xo->hline($w);
	$xo->stroke;
	if ( $c == 0 ) {
	    $xo->line_width(0.2);
	    $c = 5;
	}
    }
    $xo->restore;
}

################ Test program ################

package SVG::Parser;

use XML::Tiny;

sub new ( $pkg ) {
    bless {} => $pkg
}

sub parsefile ( $self, $fname ) {
    my $ret = XML::Tiny::parsefile( $fname );
    die("Error parsing $fname\n") unless $ret && @$ret == 1;
    bless $ret->[0] => 'XML::Tiny::_Element';
}

package XML::Tiny::_Element;

sub getElementName ( $self ) {
    $self->{name};
}

sub getChildren ( $self ) {
    my @res;
    for ( @{ $self->{content} } ) {
	if ( $_->{type} eq 'e' ) {
	    push( @res, bless $_ => 'XML::Tiny::_Element' );
	}
	elsif ( $_->{type} eq 't' ) {
	    push( @res, bless $_ => 'XML::Tiny::_Text' );
	}
	else {
	    die("Unhandled node type ", $_->{type});
	}
    }
    return @res;
}

package XML::Tiny::_Text;

our @ISA = qw ( XML::Tiny::_Element );

sub getChildren { () }

package PDF::API2::Content;

use Math::Trig;

sub bogen {
    my ($self, $x1,$y1, $x2,$y2, $r, $move, $larc, $spf) = @_;

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

1; # End of PDF::SVG
