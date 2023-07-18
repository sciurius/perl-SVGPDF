#! perl

use v5.26;
use Object::Pad;
use Carp;
use utf8;

class  PDF::SVG;

our $VERSION = 0.03;

field $ps           :accessor :param;
field $atts         :accessor :param;

# Callback for font handling.
field $fc           :accessor :param = undef;

# If an SVG file contains more than a single SVG, the CSS applies to all.
field $css          :accessor;
field $tree	    :accessor;

field $xoforms      :accessor;
field $defs         :accessor;

# For debugging/development.
field $debug        :accessor;
field $grid         :accessor;
field $debug_styles :accessor;
field $trace        :accessor;
field $wstokens     :accessor;

our $indent = "";

use SVG::Parser;
use SVG::Element;
use SVG::CSS;
use PDF::PAST;
use DDumper;

# The SVG elements.
use SVG::Circle;
use SVG::Defs;
use SVG::G;
use SVG::Image;
use SVG::Line;
use SVG::Path;
use SVG::Polygon;
use SVG::Polyline;
use SVG::Rect;
use SVG::Svg;
use SVG::Text;
use SVG::Tspan;
use SVG::Use;


################ General methods ################

BUILD {
    $debug        = $atts->{debug}        || 0;
    $grid         = $atts->{grid}         || 0;
    $debug_styles = $atts->{debug_styles} || $debug > 1;
    $trace        = $atts->{trace}        || 0;
    $wstokens     = $atts->{wstokens}     || 0;
    $indent       = "";
    $xoforms      = [];
    $defs         = {};
    $self;
}

method process_file ( $file, %attr ) {

    # Load the SVG file.
    my $svg = SVG::Parser->new;
    $tree = $svg->parse_file
      ( $file,
	whitespace_tokens => $wstokens||$attr{whitespace_tokens} );
    return unless $tree;

    # CSS persists over svgs, but not over files.
    $css = SVG::CSS->new;

    # Search for svg elements and process them.
    $self->search($tree);

    # Return (hopefully a stack of XObjects).
    return;
}

method _dbg ( @args ) {
    return unless $debug;
    my $msg;
    if ( $args[0] =~ /\%/ ) {
	$msg = sprintf( $args[0], @args[1..$#args] );
    }
    else {
	$msg = join( "", @args );
    }
    if ( $msg =~ /^\+\s*(.*)/ ) {
	$indent = $indent . "  ";
	warn( $indent, $1, "\n") if $1;
    }
    elsif ( $msg =~ /^\-\s*(.*)/ ) {
	warn( $indent, $1, "\n") if $1;
	$indent = substr( $indent, 2 );
    }
    else {
	warn( $indent, $msg, "\n") if $msg;
    }
}

method search ( $content ) {

    # In general, we'll have an XHTML tree with one or more <sgv>
    # elements.

    for ( @$content ) {
	next if $_->{type} eq 't';
	my $name = $_->{name};
	if ( $name eq "svg" ) {
	    $indent = "";
	    $self->handle_svg($_);
	    # Adds results to $self->{xoforms}.
	}
	else {
	    # Skip recursively.
	    $self->_dbg( "$name (ignored)" ) unless $name eq "<>"; # top
	    $self->search($_->{content});
	}
    }
}

method handle_svg ( $e ) {

    $self->_dbg( "+ ==== start ", $e->{name}, " ====" );

    my $xo;
    if ( $debug ) {
	$xo = PDF::PAST->new( pdf => $ps->{pr}->{pdf} );
    }
    else {
	$xo = $ps->{pr}->{pdf}->xo_form;
    }
    push( @$xoforms, { xo => $xo } );
    $self->_dbg("XObject #", scalar(@$xoforms) );
    my $svg = SVG::Element->new
	( name    => $e->{name},
	  atts    => $e->{attrib},
	  content => $e->{content},
	  root    => $self,
	);

    # If there are <style> elements, these must be processed first.
    my $cdata = "";
    for ( $svg->get_children ) {
	next unless ref($_) eq "SVG::Element" && $_->name eq 'style';
	DDumper($_->get_children) unless scalar($_->get_children) == 1;
	croak("ASSERT: 1 child") unless scalar($_->get_children) == 1;
	for my $t ( $_->get_children ) {
	    croak("# ASSERT: non-text child in style")
	      unless ref($t) eq "SVG::TextElement";
	    $cdata .= $t->content;
	}
    }
    if ( $cdata =~ /\S/ ) {
	$css->read_string($cdata);
    }

    my $atts   = $svg->atts;
    my $width  = $svg->u(delete( $atts->{width} ) || 595);
    my $height = $svg->u(delete( $atts->{height}) || 842);
    my $vbox   = delete( $atts->{viewBox} ) || "0 0 $width $height";

    delete $atts->{$_} for qw( xmlns:xlink xmlns:svg xmlns version );
    my $style = $svg->css_push($atts);

    my @bb = $svg->getargs($vbox);
    $self->_dbg( "bb $vbox => %.2f %.2f %.2f %.2f", @bb );
    $xo->bbox(@bb);
    # <svg> coordinates are topleft down, so translate.
    $self->_dbg( "translate( %.2f %.2f )", 0, $bb[1]+$bb[3] );
    $xo->transform( translate => [ 0, $bb[1]+$bb[3] ] );
    if ( $debug ) {		# show bb
	$xo->save;
	$xo->rectangle( $bb[0], -$bb[1], $bb[0]+$bb[2], -($bb[1]+$bb[3]));
	$xo->line_width(1);
	$xo->stroke;
	$xo->restore;
    }

    # Set up result forms.
    # Currently we rely on the <svg> to supply the correct viewBox.
    $xoforms->[-1] =
	  { xo      => $xo,
	    vwidth  => $width,
	    vheight => $height,
	    vbox    => [ @bb ],
	    width   => $bb[2] - $bb[0],
	    height  => $bb[3] - $bb[1] };

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
    grid( $self->xoforms->[-1] ) if $grid;
    $svg->traverse;

    $svg->css_pop;
    $self->_dbg( "- ==== end ", $e->{name}, " ====" );
}

################ Service ################

no warnings 'redefine';
sub PDF::SVG::grid ( $xof ) {
    my $d = 10;
    my $c = 6;
    my $xo = $xof->{xo};
    my $w = $xof->{width};
    my $h = $xof->{height};

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

################ Tweaks ################

package PDF::API2::Content;

use Math::Trig;

# Fixed version of 'bogen', extraced from PDF::Builder.
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
