#! perl

use v5.26;
use Object::Pad;
use feature 'signatures';
no warnings 'experimental::signatures';
use Carp;
use utf8;

package PDF::SVG;

our $VERSION = 0.02;

my $debug = 0;
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
    open( my $fd, '<:utf8', $file )
      or die(" $file: $!\n" );
    my $svg = SVG::Parser->new->parsefile($fd);
    close($fd);
    return unless $svg;

    $css = PDF::SVG::CSS->new;
    my $ret = $self->search($svg);
    PDF::SVG::PAST->finish() if $debug;
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
    my $vbox   = delete( $atts->{viewBox} ) || "0 0 $width $height";

    delete $atts->{$_} for qw( xmlns:xlink xmlns:svg xmlns version );
    my $style = $e->css_push($atts);

    # Set up result forms.
    # Currently we rely on the <svg> to supply the correct viewBox.
    push( @{ $self->{xoforms} },
	  { xo     => $xo,
	    width  => $width,
	    height => $height } );

    my @bb = split( ' ', $vbox );
    _dbg( "bb %.2f %.2f %.2f %.2f", @bb );
    $xo->bbox(@bb);
    # <svg> coordinates are topleft down, so translate.
    $xo->transform( translate => [ $bb[0], $bb[3] ] );

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
    else {
	_dbg( "traverse $en " );
	warn("SVG: Not implemented: $en\n") unless $en eq "style";
	for ( $self->getChildren ) {
	    next if $_->{type} eq 't';
	    $self->new($_)->traverse;
	}
    }
}

sub getChildren ( $self ) {
    my @res;
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

    my ( $dx, $dy, $scale ) = ( 0, 0, 1 );
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
	    $xo->save;
	    $xo->transform( translate => [ $x, $y ],
			    $scale != 1 ? ( scale => [ $scale, $scale ] ) : (),
			  );
	    $scale = 1;		# no more scaling.

	    if ( $c->{type} eq 't' ) {
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
	    }
	    elsif ( $c->{type} eq 'e' && $c->{name} eq 'tspan' ) {
		my ( $x0, $y0 ) = $c->process_tspan;
		$x += $x0; $y += $y0;
		_dbg("tspan moved to $x, $y");
	    }
	    $xo->restore;
	    $ex = $x; $ey = $y;
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
    my $x0 = $x;
    my $y0 = $y;

    $d =~ s/([a-z])([a-z])/$1 $2/gi;
    $d =~ s/([a-z])([-\d])/$1 $2/gi;
    $d =~ s/([-\d])([a-z])/$1 $2/gi;
    $d =~ s/,/ /g;
    my @d = split( ' ', $d );

    my $open;

    my $paint = sub {
	if ( $style->{stroke} && $style->{stroke} ne 'none' ) {
	    if ( $style->{fill} && $style->{fill} ne 'none' ) {
		$xo->paint;
	    }
	    else {
		$xo->stroke;
	    }
	}
	elsif ( $style->{fill} && $style->{fill} ne 'none' ) {
	    $xo->fill;
	}
    };

    # Initial x,y for path. See 'z'.
    my $ix;
    my $iy;

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
	    next;
	}

	# Horizontal LineTo.
	if ( $op eq "h" ) {
	    $ix = $x, $iy = $y unless $open++;
	    _dbg( "xo hline(%.2f)", $d[0] );
	    $x += shift(@d);
	    $xo->hline($x);
	    next;
	}

	# Vertical LineTo.
	if ( $op eq "v" ) {
	    $ix = $x, $iy = $y unless $open++;
	    _dbg( "xo vline(%.2f)", $d[0] );
	    $y -= shift(@d);
	    $xo->vline($y);
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
	    next;
	}

	# Curves.
	if ( $op eq "c" ) {
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $x, $iy = $y unless $open++;
		my @c = ( $x + $d[0], $y - $d[1],
			  $x + $d[2], $y - $d[3],
			  $x + $d[4], $y - $d[5] );
		_dbg( "xo curve(%.2f,%.2f %.2f,%.2f %.2f,%.2f)", @c );
		$xo->curve(@c);
		splice( @d, 0, 6 );
		$x = $c[4]; $y = $c[5];
	    }
	    next;
	}

	# TODO: S/s
	# unshift( @d, 's', 2 * $c[4] - $c[2], 2 * $c[5] - $c[3] )
	# TODO: Q/q (but how?)
	# TODO: T/t (but how?)
	# TODO: A/a

	# Arcs.
	if ( $op eq "a" ) {
	    my $new = 1;
	    while ( @d > 6 && $d[0] =~ /^-?[.\d]+$/ ) {
		my $sx = shift(@d);
		my $sy = shift(@d);
		my $rot = shift(@d);
		my $large = shift(@d);
		my $sweep = shift(@d);
		my $ex = shift(@d);
		my $ey = shift(@d);
		$ix = $x, $iy = $y unless $open++;
		_dbg( "xo arc(%.2f,%.2f %.2f %d %d %.2f,%.2f)",
		      $sx, $sy, $rot, $large, $sweep, $ex, $ey );
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

    my $sda = $style->{'stroke-dasharray'};
    _dbg( $self->getElementName, " x=$x y=$y w=$w h=$h" );
    local $indent = $indent . "  ";

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( "xo save" );
    $xo->save;

    $self->set_graphics($style);

    my $paint = sub {
	if ( $style->{stroke} && $style->{stroke} ne 'none' ) {
	    if ( $style->{fill} && $style->{fill} ne 'none' ) {
		$xo->paint;
	    }
	    else {
		$xo->stroke;
	    }
	}
	elsif ( $style->{fill} && $style->{fill} ne 'none' ) {
	    $xo->fill;
	}
    };

    $xo->rectangle( $x, -$y, $x+$w, -$y-$h );
    $paint->();

    _dbg( "xo restore" );
    $xo->restore;
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

    if ( $t ) {
	if ( $t =~ /translate\(([.\d]+),\s*([.\d]+)\)/ ) {
	    $x = $1;
	    $y = $2;
	    _dbg( "xo translate( %.2f, %.2f )", $x, $y );
	}
	if ( $t =~ /scale\(([.\d]+)\)/ ) {
	    $scale = $1;
	    _dbg( "xo scale( %.2f )", $scale );
	}
    }

    my %o;
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

    for ( $self->getChildren ) {
	$_->traverse;
    }

    if ( %o ) {
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
	$xo->stroke_color($stroke);
	_dbg( $self->getElementName, " stroke=", $stroke );
    }

    my $fill = $style->{fill};
    if ( lc($fill) eq "currentcolor" ) {
	# Nothing. Use current.
    }
    elsif ( lc($fill) ne "none" ) {
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

################ Styles and Fonts ################

sub makefont ( $self, $style ) {
    local $indent = $indent . "  ";

    my ( $fn, $sz, $em, $bd ) = ("Times-Roman", 12, 0, 0 );

    $fn = $style->{'font-family'} // "Times-Roman";
    $sz = $style->{'font-size'} || 12;
    $sz = $1 if $sz =~ /^([.\d]+)px/; # TODO: units
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

1; # End of PDF::SVG
