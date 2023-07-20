#! perl

use v5.26;
use Object::Pad;
use Carp;
use utf8;

class  PDF::SVG;

our $VERSION = '0.040';

=head1 NAME

PDF::SVG - Create XObject from SVG data

=head1 SYNOPSIS

    my $pdf = PDF::API2->new;
    my $gfx = $pdf->gfx;
    my $svg = PDF::SVG->new( pdf => $pdf, {} );
    my $xof = $svg->process_file("demo.svg");

    # If all goes well, $xof is an array of hashes, each representing an
    # XObject corresponding to the <svg> elements in the file.
    my $y = 800;
    foreach my $xo ( @$xof ) {
	my @bb = @{$xo->{vbox}};
        my $h = $bb[2];
	$gfx->object( $xo->{xo}, 10, $y-$h, 1 );
	$y -= $h;
    }


This module is intended to be used with PDF::Builder, PDF::API2 and
compatible PDF packages.

=head1 DESCRIPTION



=cut

field $pdf          :accessor :param;
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
field $prog         :accessor;
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
use SVG::Ellipse;
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
    $prog         = $atts->{prog}         || 0;
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
    if ( $prog ) {
	$xo = PDF::PAST->new( pdf => $pdf );
    }
    else {
	$xo = $pdf->xo_form;
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

    my $width  = delete $atts->{width};
    my $height = delete $atts->{height};
    my $vbox   = delete $atts->{viewBox};

    delete $atts->{$_} for qw( xmlns:xlink xmlns:svg xmlns version );
    my $style = $svg->css_push($atts);

    my @bb;
    # Currently we rely on the <svg> to supply the correct viewBox.
    if ( $vbox ) {
	@bb = $svg->getargs($vbox);
	$width = $svg->u($width//$bb[2]);
	$height = $svg->u($height//$bb[3]);
    }
    else {
	# Fallback to width/height.
	$width = $svg->u($width||595);
	$height = $svg->u($height||842);
	@bb = ( 0, 0, $width, $height );
	$vbox = "@bb";
    }
    $self->_dbg( "bb $vbox => %.2f %.2f %.2f %.2f", @bb );
    $xo->bbox(@bb);

    # Set up result forms.
    $xoforms->[-1] =
	  { xo      => $xo,
	    vwidth  => $width,
	    vheight => $height,
	    vbox    => [ @bb ],
	    width   => $bb[2] - $bb[0],
	    height  => $bb[3] - $bb[1] };

    # <svg> coordinates are topleft down, so translate.
    $self->_dbg( "translate( %.2f %.2f )", 0, $bb[1]+$bb[3] );
    $xo->transform( translate => [ -$bb[0], $bb[1]+$bb[3] ] );

    if ( $debug ) {		# show bb
	$xo->save;
	$self->_dbg( "bb rect( %.2f %.2f %.2f %.2f)",
		     $bb[0], -$bb[1], $bb[2]+$bb[0], -$bb[1]-$bb[3]);
	$xo->rectangle( $bb[0], -$bb[1], $bb[2]+$bb[0], -$bb[1]-$bb[3]);
	$xo->fill_color("#ffffc0");
	$xo->fill;
	$xo->move(  $bb[0], 0 );
	$xo->hline( $bb[0]+$bb[2]);
	$xo->move( 0, -$bb[1] );
	$xo->vline( -$bb[1]-$bb[3] );
	$xo->line_width(0.5);
	$xo->stroke_color( "red" );
	$xo->stroke;
	$xo->restore;
    }
    $self->draw_grid( $xo, \@bb ) if $grid;


    # Establish currentColor.
    for ( $css->find("fill") ) {
	next if $_ eq 'none' or $_ eq 'transparent';
	$self->_dbg( "xo fill_color ",
		     $_ eq 'currentColor' ? 'black' : $_,
		     " (initial)");
	$xo->fill_color( $_ eq 'currentColor' ? 'black' : $_ );
    }
    for ( $css->find("stroke") ) {
	next if $_ eq 'none' or $_ eq 'transparent';
	$self->_dbg( "xo stroke_color ",
		     $_ eq 'currentColor' ? 'black' : $_,
		     " (initial)");
	$xo->stroke_color( $_ eq 'currentColor' ? 'black' : $_ );
    }
    $svg->traverse;

    $svg->css_pop;
    $self->_dbg( "- ==== end ", $e->{name}, " ====" );
}

################ Service ################

method draw_grid ( $xo, $bb ) {
    my $d = 10;
    my $c = 6;
    my @bb = @$bb;
    my $w = $bb[2];
    my $h = $bb[3];
    my $thick = 1;
    my $thin = 0.2;

    $xo->save;
    $xo->stroke_color("#bbbbbb");

    # Map viewbox to 0,0.
    $xo->transform( translate => [ $bb[0], -$bb[1] ] );

    # Show boundary points.
    $xo->rectangle(-2,-2,2,2);
    $xo->fill_color("blue");
    $xo->fill;
    $xo->rectangle( $bb[2]-2, -$bb[3]-2, $bb[2]+2, -$bb[3]+2);
    $xo->fill_color("blue");
    $xo->fill;
    # Show origin. This will cover the bb corner unless it is offset.
    $xo->rectangle( -$bb[0]-2, $bb[1]-2, -$bb[0]+2, $bb[1]+2);
    $xo->fill_color("red");
    $xo->fill;

    # Draw the grid (thick lines).
    $xo->line_width($thick);
    for ( my $x = 0; $x <= $w; $x += 5*$d ) {
	$xo->move( $x, 0 );
	$xo->vline(-$h);
	$xo->stroke;
    }
    for ( my $y = 0; $y <= $h; $y += 5*$d ) {
	$xo->move( 0, -$y );
	$xo->hline($w);
	$xo->stroke;
    }
    # Draw the grid (thin lines).
    $xo->line_width($thin);
    for ( my $x = 0; $x <= $w; $x += $d ) {
	$xo->move( $x, 0 );
	$xo->vline(-$h);
	$xo->stroke;
    }
    for ( my $y = 0; $y <= $h; $y += $d ) {
	$xo->move( 0, -$y );
	$xo->hline($w);
	$xo->stroke;
    }
    $xo->restore;
}

1; # End of PDF::SVG
