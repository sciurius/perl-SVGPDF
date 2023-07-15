#! perl

use v5.26;
use Object::Pad;
use Carp;
use utf8;

class  PDF::SVG;

our $VERSION = 0.02;

field $ps           :param :accessor;
field $atts         :param :accessor;

# If an SVG file contains more than a single SVG, the CSS applies to all.
field $css          :accessor;
field $tree	    :accessor;

field $xoforms      :accessor;

# For debugging/development.
field $debug        :accessor;
field $grid         :accessor;
field $debug_styles :accessor;
field $trace        :accessor;
field $wstokens     :accessor;

our $indent = "";

use SVG::Parser;
use SVG::Element;
use SVG::Rect;
use SVG::Text;
use SVG::Tspan;
use SVG::CSS;
use PDF::PAST;
use DDumper;

################ General methods ################

BUILD {
    $debug        = $atts->{debug}        || 0;
    $grid         = $atts->{grid}         || 0;
    $debug_styles = $atts->{debug_styles} || $debug > 1;
    $trace        = $atts->{trace}        || 0;
    $wstokens     = $atts->{wstokens}     || 0;
    $indent       = "";
    $xoforms      = [];
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
	warn( $indent, $1, "\n");
    }
    elsif ( $msg =~ /^\-\s*(.*)/ ) {
	warn( $indent, $1, "\n");
	$indent = substr( $indent, 2 );
    }
    else {
	warn( $indent, $msg, "\n");
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

    $self->_dbg( "+ ", $e->{name}, " ====" );

    my $xo;
    if ( $debug ) {
	$xo = PDF::PAST->new( pdf => $ps->{pr}->{pdf} );
    }
    else {
	$xo = $ps->{pr}->{pdf}->xo_form;
    }
    push( @$xoforms, { xo => $xo } );
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
    my $width  = $svg->u(delete( $atts->{width} )) || 595;
    my $height = $svg->u(delete( $atts->{height})) || 842;
    my $vbox   = delete( $atts->{viewBox} ) || "0 0 $width $height";

    delete $atts->{$_} for qw( xmlns:xlink xmlns:svg xmlns version );
    my $style = $svg->css_push($atts);

    my @bb = $svg->getargs($vbox);
    $self->_dbg( "bb $vbox => %.2f %.2f %.2f %.2f", @bb );
    $xo->bbox(@bb);
    # <svg> coordinates are topleft down, so translate.
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

    $self->_dbg( "- ", $e->{name}, " ====" );
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

1; # End of PDF::SVG
