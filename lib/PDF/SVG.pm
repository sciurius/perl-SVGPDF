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

################ General methods ################

sub new ( $pkg, $ps, %atts ) {
    my $self = bless { ps => $ps, %atts } => $pkg;
    $debug = $atts{debug};
    $debug_styles = $atts{debug_styles};
    $trace = $atts{trace};
    $self;
}

sub _dbg ( $fmt, @args ) {
    return unless $trace;
    if ( $fmt =~ /\%/ ) {
	warn( $indent, sprintf( $fmt, @args), "\n" );
    }
    else {
	warn( $indent, join( "", $fmt, @args ), "\n" );
    }
}

sub process_file ( $self, $file ) {
    open( my $fd, '<:utf8', $file )
      or die(" $file: $!\n" );
    my $svg = SVG::Parser->new->parsefile($fd);
    close($fd);
    return unless $svg;

#    use DDumper;DDumper($svg);exit;

    my $ret = $self->search($svg);
    PAST::finish() if $debug;
    return $ret;
}

sub search ( $self, $e ) {
    local $indent = $indent . "  ";

    # In general, we'll have an XHTML tree with one or more <sgv>
    # elements.

    my $en = $e->getElementName;
    if ( $en eq "svg" ) {
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
      ? PAST->new( $self->{ps}->{pr}->{pdf} )
      : $self->{ps}->{pr}->{pdf}->xo_form;

    # Turn the <svg> element into an SVG:Element.
    $e = SVG::Element->wrap( $e, $self );

    my $width  = $e->getAttribute("width") || 595;
    my $height = $e->getAttribute("height") || 842;
    s/px$// for $width, $height;

    # Set up result forms.
    # Currently we rely on the <svg> to supply the correct viewBox.
    push( @{ $self->{xoforms} },
	  { xo     => $xo,
	    width  => $width,
	    height => $height } );

    my @bb;
    if ( $e->getAttribute("viewBox") ) {
	@bb = split( ' ', $e->getAttribute("viewBox") );
    }
    else {
	@bb = ( 0, 0, $width, $height );
    }
    _dbg( "bb %.2f %.2f %.2f %.2f", @bb );
    $xo->bbox(@bb);
    # <svg> coordinates are topleft down, so translate.
    $xo->transform( translate => [ $bb[0], $bb[3] ] );

#    $xo->rectxy(@bb);
#    $xo->fill_color("#00ff00");
#    $xo->fill;
#    $xo->fill_color("black");

    $self->{class} = [ split( ' ', $e->getAttribute("class")//"" ) ];
    my $style = $e->getStyle;

    # Defaults.
    $style->{'font-family'} //= "Times-Roman";
    $style->{'font-size'} //= 10;
    $style->{stroke} //= 'none';
    $style->{fill}   //= $style->{color} // 'black';

    $self->{attrstyle} = $style;

    # Establish currentColor.
    $xo->fill_color($style->{fill})
      unless $style->{fill}   eq 'none'
      or     $style->{fill}   eq 'currentColor';
    $xo->stroke_color($style->{stroke})
      unless $style->{stroke} eq 'none'
      or     $style->{stroke} eq 'currentColor';


#    use DDumper; DDumper $e;

    for ( $e->getChildren ) {
	$_->traverse;
    }

}

################ SVG ################

package SVG::Text;

our @ISA = qw ( SVG::Element );

package SVG::Element;

our @ISA = qw ( XML::Tiny::_Element );

*_dbg = \&PDF::SVG::_dbg;

sub wrap ( $pkg, $e, $parent = undef, $svg = undef ) {
    $parent //= $pkg;
    $pkg = ref($pkg) || $pkg;
    $svg //= $parent->{svg} // $parent;
    my $self = { %$e,
		 parent => $parent,
		 svg => $svg };
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
#	_dbg( "$en ", atts($e) );
	_dbg( "traverse $en " );
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
	    push( @res, $self->wrap($_) );
	}
	elsif ( $_->{type} eq 't' ) {
	    push( @res, SVG::Text->wrap( $_, $self ) );
	}
	else {
	    die("Unhandled node type ", $_->{type});
	}
    }
    return @res;
}

sub getAttributes ( $self, $att ) {
    $self->{attrib} // {};
}

sub getStyle ( $self ) {

    my $style = $self->getAttrStyle;

    $style;
}

sub getClassStyle ( $self ) {

    my %style;

    # Inherited styles from classes.
    my @class = split( ' ', $self->getAttribute("class") // "" );
#    push( @class, @{ $self->{svg}->{class} } );
    return {} unless @class;
    for my $class ( @class ) {
	$style{$_} //= $self->{svg}->{cstyles}->{$class}->{$_}
	  foreach keys %{ $self->{svg}->{cstyles}->{$class} };
    }

    \%style;
}

sub getElementStyle ( $self ) {

    my %style;

    # Inherited styles from elements.
    my $el = $self->getElementName;
    return {} unless $self->{svg}->{estyles}->{$el};
    $style{$_} //= $self->{svg}->{estyles}->{$el}->{$_}
      foreach keys %{ $self->{svg}->{estyles}->{$el} };

    \%style;
}

sub getAttrStyle ( $self, $tag = undef ) {
    $tag //= $self->getElementName;

    $self->{attrstyle} //= do {
	my %style = ( _origin => {} );

	# 1. Display attributes (subset).
	for ( qw( color fill font-family font-size font-weight font-style
		  stroke stroke-dasharray stroke-width text-anchor ) ) {
	    next unless defined $self->{attrib}->{$_};
	    $style{$_} = $self->{attrib}->{$_};
	    $style{_origin}{$_} = "display";
	}

	my %s;

	# 2. Style attribute.
	if ( my $style = $self->getAttribute("style") ) {
	    %s = %{ parse_style($style) // {} };
	    foreach ( keys %s ) {
		$style{$_} = $s{$_};
		$style{_origin}{$_} = "style";
	    }
	}

	# 3. Styles from elements.
	%s = %{ $self->getElementStyle // {} };
	foreach ( keys %s ) {
	    next if defined( $style{$_} );
	    $style{$_} = $s{$_};
	    $style{_origin}{$_} = "element";
	}

	# 4. Styles from class.
	%s = %{ $self->getClassStyle // {} };
	foreach ( keys %s ) {
	    next if defined( $style{$_} );
	    $style{$_} = $s{$_};
	    $style{_origin}{$_} = "class";
	}

	# 5. Inherits.
	if ( my $gs = $self->{parent}->can("getStyle") ) {
	    %s = %{ $gs->( $self->{parent} ) // {} };
	    foreach ( keys %s ) {
		next if defined( $style{$_} );
		$style{$_} = $s{$_};
		$style{_origin}{$_} = "inherited";
	    }
	}

	$self->_st( $tag, \%style );
	\%style;
    }
}

sub _st ( $self, $tag, $s ) {
    return unless $debug_styles;
    return unless %$s;
    return unless %$s > 1;
    warn( "$tag {\n" );
    foreach ( sort keys %$s ) {
	next if $_ eq "_origin";
	warn( "   $_: ", $s->{$_}, " (", $s->{_origin}{$_}, ")\n" );
    }
    warn("}\n");
}

sub getAttribute ( $self, $att ) {
    $self->{attrib}->{$att};
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
    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";

    my $class = $self->getAttribute("class") || "<none>";
    my $style = $self->getStyle;

    my $text = "";

    my $x = $self->getAttribute("x") || 0;
    my $y = $self->getAttribute("y") || 0;
    my $tf = $self->getAttribute("transform") || "";

    my $color = $style->{color};
    my $anchor = $style->{'text-anchor'} || "left";
    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};

    _dbg( $self->getElementName, " ",
	  defined($self->getAttribute("x")) ? ( " x=$x" ) : (),
	  defined($self->getAttribute("y")) ? ( " y=$y" ) : (),
	  defined($self->getAttribute("text-anchor"))
	  ? ( " anchor=\"$anchor\"" ) : (),
	  defined($self->getAttribute("transform"))
	  ? ( " transform=\"$tf\"" ) : (),
	  defined($self->getAttribute("class"))
	  ? ( " class=\"", $self->getAttribute("class"), "\"" )
	  : ( " class=\"$class\" (inh.)" ),
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
	_dbg( "txt translate( %.2f, %.2f )%s %x",
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
	$xo->font( $self->makefont($style) );
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
		$xo->font( $self->makefont($style) );
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
    }
    _dbg( "xo restore" );
    $xo->restore;
}

sub process_tspan {
    my ( $self ) = @_;
    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";

    my $class = $self->getAttribute("class") || "<none>";
    my $style = $self->getStyle;

    my $text = "";

    my $x  = $self->getAttribute("x")  || 0;
    my $y  = $self->getAttribute("y")  || 0;
    my $dx = $self->getAttribute("dx") || 0;
    my $dy = $self->getAttribute("dy") || 0;

    $dx = $1 * $style->{'font-size'} if $dx =~ /^([.\d]+)em$/;
    $dy = $1 * $style->{'font-size'} if $dy =~ /^([.\d]+)em$/;
    
    my $color = $style->{color};
    my $anchor = $style->{'text-anchor'} || "left";
    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};

    _dbg( $self->getElementName, " ",
	  defined($self->getAttribute("x")) ? ( " x=$x" ) : (),
	  defined($self->getAttribute("y")) ? ( " y=$y" ) : (),
	  defined($self->getAttribute("dx")) ? ( " dx=$dx" ) : (),
	  defined($self->getAttribute("dy")) ? ( " dy=$dy" ) : (),
	  defined($self->getAttribute("text-anchor"))
	  ? ( " anchor=\"$anchor\"" ) : (),
	  defined($self->getAttribute("class"))
	  ? ( " class=\"", $self->getAttribute("class"), "\"" )
	  : ( " class=\"$class\" (inh.)" ),
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
		$xo->font( $self->makefont($style) );
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
	return wantarray ? ( $x, $y ) : $x;
    }
}

sub process_path ( $self ) {

    my $d = $self->getAttribute("d");
    return unless $d;

    my $class = $self->getAttribute("class") || "<none>";
    my $style = $self->getStyle;

    my $x = 0;
    my $y = 0;
    _dbg( $self->getElementName, " x=$x y=$y class=$class" );
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
	    while ( @d && $d[0] =~ /^-?[.\d]+$/ ) {
		$ix = $x, $iy = $y unless $open++;
		my @c = ( $x + $d[0], $y - $d[1],
			  $d[2], $d[3],
			  $d[4], $d[5] );
		_dbg( "xo arc(%.2f,%.2f %.2f,%.2f %.2f,%.2f)", @c );
		...;
		$xo->arc( @c, $new );
		$new = 0;
		splice( @d, 0, 5 );
		# $x = ...; $y = ...;
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
}

sub process_rect ( $self ) {

    my $class = $self->getAttribute("class") || "<none>";
    my $style = $self->getStyle;

    my $sda = $style->{'stroke-dasharray'};
    my $x = $self->getAttribute("x");
    my $y = $self->getAttribute("y");
    my $w = $self->getAttribute("w");
    my $h = $self->getAttribute("h");
    _dbg( $self->getElementName, " x=$x y=$y w=$w h=$h class=$class" );
    local $indent = $indent . "  ";

    my $xo = $self->{xoforms}->[-1]->{xo};
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

    $xo->rect( $x, $y, $w, $h );
    $paint->();

    _dbg( "xo restore" );
    $xo->restore;
}

################ Graphics context ################

sub process_g ( $self ) {
    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";

    my $class = $self->getAttribute("class") || "<none>";
    my $style = $self->getStyle;

    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    my $x;
    my $y;
    my $scale;

    if ( my $t = $self->getAttribute("transform") ) {
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

    $style //= $self->getStyle;
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
	$self->{svg}->{defs}->{ "#" . $_->getAttribute("id") } = $_;
    }
}

sub process_use ( $self ) {
    my $x = + $self->getAttribute("x");
    my $y = - $self->getAttribute("y");
    my $xo = $self->{svg}->{xoforms}->[-1]->{xo};
    _dbg( $self->getElementName, " x=$x, y=$y" );
    local $indent = $indent . "  ";

    my $r = $self->{svg}->{defs}->{ $self->getAttribute("xlink:href") };
    die("missing def ", $self->getAttribute("xlink:href")) unless $r;

    $xo->save;
    $xo->transform( translate => [ $x, $y ] );
    $r->traverse;
    $xo->restore;
}

################ Styles and Fonts ################

use Text::ParseWords qw( shellwords );

sub process_style ( $self ) {
    _dbg( $self->getElementName, " ====" );
    local $indent = $indent . "  ";

    # .class { defs* }
    # .class el[,el] { defs* }		NYI
    #
    # defs ::= def [ ; def ]*
    # def ::= ident : value

    my %cs = %{ $self->{svg}->{cstyles} // {} };
    my %es = %{ $self->{svg}->{estyles} // {} };

    my $s = $self->getCDATA;

    # Ignore @font-face.
    $s =~ s/\@font-face\s*\{.*?\}//sg;

    while ( $s =~ s/([.\w].*?)\{(.*?)\}//s ) {
	warn("CLASS = $1\nDEF = $2\n") if $debug;
	my ( $class, $defs ) = ( $1, $2 );
	trim( $class, $defs );
	my $d = parse_style($defs);
	foreach ( split( ' ', $class ) ) {
	    foreach my $c ( split( ',', $_ ) ) {
		if ( $c =~ /^\.(.*)/ ) {
		    $cs{$1}->{$_} = $d->{$_} for keys %$d;
		}
		else {
		    $es{$c}->{$_} = $d->{$_} for keys %$d;
		}
	    }
	}
    }
    $self->{svg}->{cstyles} = \%cs;
    $self->{svg}->{estyles} = \%es;
    if ( $debug ) {
	use DDumper;
	warn "CSTYLES: ", DDumper(\%cs);
	warn "ESTYLES: ", DDumper(\%es);
    }
}

sub parse_style ( $defs ) {
    my %s;
    for my $def ( split( /;/, $defs ) ) {
	trim($def);
	unless ( $def =~ /^([-\w]+)\s*:\s*(.*)$/ ) {
	    warn("Unhandled style definition: \"$def\"\n");
	    next;
	}
	if ( $1 eq "font" ) {

	    my @spec = shellwords($2);

	    foreach my $spec ( @spec ) {
		if ( $spec =~ /^([.\d]+)px/ ) {
		    $s{'font-size'} = $1;
		}
		elsif ( $spec eq "bold" ) {
		    $s{'font-weight'} = "bold";
		}
		elsif ( $spec eq "italic" ) {
		    $s{'font-style'} = "italic";
		}
		elsif ( $spec eq "bolditalic" ) {
		    $s{'font-weight'} = "bold";
		    $s{'font-style'} = "italic";
		}
		elsif ( $spec =~ /^text,serif/ ) {
		    $s{'font-family'} = "Times-Roman";
		}
		elsif ( $spec =~ /^text,sans-serif/ ) {
		    $s{'font-family'} = "Helvetica";
		}
		elsif ( $spec =~ /^abc2svg(?:\.ttf)?;?/ ) {
		    $s{'font-family'} = "abc2svg";
		}
		elsif ( $spec eq "music" ) {
		    $s{'font-family'} = "abc2svg";
		}
		elsif ( $spec eq "MuseJazz Text" ) {
		    $s{'font-family'} = "MuseJazzText.otf";
		}
		else {
		    $s{'font-family'} = "Times-Roman";
		}
	    }
	}
	else {
	    $s{$1} = $2;
	    $s{$1} =~ s/px$//;
	}
    }
    \%s
}

sub trim {
    for ( @_ ) {
	s/^\s+//s;
	s/\s+$//s;
	s/[\r\n]+/ /g
    }
    $_[0];
}

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

    if ( $fn =~ /^(helvetica|text,sans-serif)$/i ) {
	$fn = $bd
	  ? $em ? "Helvetica-BoldOblique" : "Helvetica-Bold"
	  : $em ? "Helvetica-Oblique" : "Helvetica";
    }
    elsif ( $fn =~ /^abc2svg(?:\.ttf)?;?/ ) {
	$fn = "abc2svg.ttf";
    }
    elsif ( $fn eq "music" ) {
	$fn = "abc2svg.ttf";
    }
    elsif ( $fn eq "MuseJazz Text" ) {
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
    wantarray ? ( $font, $style->{'font-size'}, $fn ) : $font;
}

################ Development and Debugging ################

# Use this package as an intermediate to trace the actual operations.

package PAST;

use Carp;

sub xdbg ( $fmt, @args ) {
    if ( $fmt =~ /\%/ ) {
	warn( $indent, sprintf( $fmt, @args), "\n" );
    }
    else {
	warn( $indent, join( "", $fmt, @args ), "\n" );
    }
}


sub new ( $pkg, $pdf ) {
    local($indent) = "";
    xdbg( 'use PDF::API2;' );
    xdbg( 'my $pdf  = PDF::API2->new;' );
    xdbg( 'my $page = $pdf->page;' );
    xdbg( 'my $xo   = $page->gfx;' );
    xdbg( 'my $font = $pdf->font("Times-Roman");' );
    xdbg( '' );
    bless { xo => $pdf->xo_form } => $pkg;
}

#### Coordinates

sub bbox ( $self, @args ) {
    xdbg( "\$page->bbox( ", join(", ", @args ), " );" );
    $self->{xo}->bbox( @args );
}

sub transform ( $self, %args ) {
    my $tag = "\$xo->transform(";
    while ( my ($k,$v) = each %args ) {
	$tag .= " $k => ";
	if ( ref($v) eq 'ARRAY' ) {
	    $tag .= "[ " . join(", ", @$v) . " ]";
	}
	else {
	    $tag .= "\"$v\"";
	}
	$tag .= ", ";
    }
    substr( $tag, -2, 2, " );" );
    xdbg($tag);
    $self->{xo}->transform( %args );
}

#### Graphics.

sub fill_color ( $self, @args ) {
    Carp::confess("currentColor") if $args[0] eq 'currentColor';
    xdbg( "\$xo->fill_color( @args );" );
    $self->{xo}->fill_color( @args );
}

sub stroke_color ( $self, @args ) {
    xdbg( "\$xo->stroke_color( @args );" );
    $self->{xo}->stroke_color( @args );
}

sub fill ( $self, @args ) {
    die if @args;
    xdbg( "\$xo->fill();" );
    $self->{xo}->fill( @args );
}

sub stroke ( $self, @args ) {
    die if @args;
    xdbg( "\$xo->stroke();" );
    $self->{xo}->stroke( @args );
}

sub line_width ( $self, @args ) {
    xdbg( "\$xo->line_width( ", join(", ", @args ), " );" );
    $self->{xo}->line_width( @args );
}

sub line_dash_pattern ( $self, @args ) {
    xdbg( "\$xo->line_dash_pattern( ", join(", ", @args ), " );" );
    $self->{xo}->line_dash_pattern( @args );
}

sub paint ( $self, @args ) {
    die if @args;
    xdbg( "\$xo->paint();" );
    $self->{xo}->paint( @args );
}

sub save ( $self, @args ) {
    die if @args;
    xdbg( "\$xo->save();" );
    $self->{xo}->save( @args );
}

sub restore ( $self, @args ) {
    die if @args;
    xdbg( "\$xo->restore();" );
    $self->{xo}->restore( @args );
}

#### Texts,

sub textstart ( $self, @args ) {
    die if @args;
    xdbg( "\$xo->textstart();" );
    $self->{xo}->textstart( @args );
}

sub textend ( $self, @args ) {
    die if @args;
    xdbg( "\$xo->textend();" );
    $self->{xo}->textend( @args );
}

sub font ( $self, $font, $size, $name ) {
    xdbg( "\$xo->font( \$font, $size );\t# $name" );
    $self->{xo}->font( $font, $size );
}

sub text ( $self, $text, %opts ) {
    xdbg( "\$xo->text( \"$text\", ",
	  join( ", ", map { "$_ => \"$opts{$_}\"" } keys %opts ),
	  " );" );
    $self->{xo}->text( $text, %opts );
}

#### Paths.

sub move ( $self, @args ) {
    xdbg( "\$xo->move( ", join(", ",@args), " );" );
    $self->{xo}->move( @args );
}

sub hline ( $self, @args ) {
    xdbg( "\$xo->hline( @args );" );
    $self->{xo}->hline( @args );
}

sub vline ( $self, @args ) {
    xdbg( "\$xo->vline( @args );" );
    $self->{xo}->vline( @args );
}

sub line ( $self, @args ) {
    xdbg( "\$xo->line( ", join(", ",@args), " );" );
    $self->{xo}->line( @args );
}

sub curve ( $self, @args ) {
    xdbg( "\$xo->curve( ", join(", ",@args), " );" );
    $self->{xo}->curve( @args );
}

sub rect ( $self, @args ) {
    xdbg( "\$xo->rect( ", join(", ",@args), " );" );
    $self->{xo}->rect( @args );
}

sub close ( $self, @args ) {
    die if @args;
    xdbg( "\$xo->close();" );
    $self->{xo}->close( @args );
}

#### Misc.

sub finish () {
    xdbg( "\$pdf->save(\"z.pdf\");" );
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


################ Test program ################

package main;

unless ( caller ) {

    binmode STDOUT => ':utf8';
    binmode STDERR => ':utf8';
    *xdbg = \&PDF::SVG::xdbg;

    require PDF::API2; PDF::API2->VERSION(2.042);

    my $pdf = PDF::API2->new;
    PDF::API2->add_to_font_path($ENV{HOME}."/.fonts");

    my $p = PDF::SVG->new
      ( { pr => { pdf => $pdf } }, debug => 1 );
    my $o = $p->process_file( shift);
    warn("PDF: SVG objects: ", 0+@$o, "\n");
    my $page = $pdf->page;
    $page->size( [ 0, 0, 595, 842 ] );
    my $gfx = $page->gfx;
    my $x = 0;
    my $y = 842;

    sub crosshairs {
	my ( $x, $y, $col ) = @_;
	for ( $gfx  ) {
	    $_->save;
	    $_->line_width(0.1);
	    $_->stroke_color($col//"black");
	    $_->move($x-0,$y);
	    $_->hline($x+20);
	    $_->stroke;
	    $_->move($x,$y+20);
	    $_->vline($y-20);
	    $_->stroke;
	    $_->restore;
	}
    }

    my $i = 0;
    foreach my $xo ( @$o ) {
	$i++;
	if ( ref($xo->{xo}) eq "PAST" ) {
	    $xo->{xo} = $xo->{xo}->{xo};
	}
	my $w = $xo->{width};
	my $h = $xo->{height};
	my $scale = 1;
	if ( $w > 595 ) {
	    $scale = 595/$w;
	}

	if ( $y - $h * $scale <= 0 ) {
	    $page = $pdf->page;
	    $page->size( [ 0, 0, 595, 842 ] );
	    $gfx = $page->gfx;
	    $x = 0;
	    $y = 842;
	}

	warn(sprintf("object %d ( %.2f, %.2f, %.2f, %.2f @%.2f )\n",
		     $i, $x, $y-$h*$scale, $w*$scale, $h*$scale, $scale ));

	crosshairs( $x, $y, "blue" );
	$gfx->object( $xo->{xo}, $x, $y-$h*$scale, $scale );

	$y -= $h * $scale;
    }
    crosshairs( $x, $y, "blue" );

    $pdf->save("x.pdf");
}

1;

1; # End of PDF::SVG
