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
    my $svg = PDF::SVG->new($pdf);
    my $xof = $svg->process("demo.svg");

    # If all goes well, $xof is an array of hashes, each representing an
    # XObject corresponding to the <svg> elements in the file.
    # Get a page and graphics context.
    my $page = $pdf->page;
    $page->bbox( 0, 0, 595, 842 );
    my $gfx = $pdf->gfx;

    # Place the objects.
    my $y = 832;
    foreach my $xo ( @$xof ) {
	my @bb = @{$xo->{vbox}};
        my $h = $bb[3];
	$gfx->object( $xo->{xo}, 10, $y-$h, 1 );
	$y -= $h;
    }

    $pdf->save("demo.pdf");

=head1 DESCRIPTION

This module processes SVG data and produces one or more PDF XObjects
to be placed in a PDF document. This module is intended to be used
with L<PDF::Builder>, L<PDF::API2> and compatible PDF packages.

The main routine is process(). It takes an input specification (see
below) and an optional hash with sttributes for the processing.

=head1 CONSTRUCTOR

In its most simple form, a new PDF::SVG object can be created with a
single argument, the PDF document.

     $svg = PDF::SVG->new($pdf);

There are two additional arguments, these must be specified as
key/value pairs.

=over

=item C<fc>

A reference to a callback routine to handle fonts. See below.

=item C<grid>

If not zero, a grid will be added to the image. This is mostly for
developing and debugging.

The value determines the grid spacing.

=back

For convenience, the mandatory PDF argument can also be specified with
a key/value pair:

    $svg = PDF::SVG->new( pdf => $pdf, grid => 1, fc => \&fonthandler );



=head1 INPUT

The SVG data can come from several sources.

=over 4

=item *

An SVG document on disk, specified as the name of the document.

=item *

A file handle, openened on a SVG document, specified as a glob
reference. You can use C<\*DATA> to append the SVG data after a
C<__DATA__> separator at the end of the program.

=item *

A string containing SVG data, specified as a reference to a scalar.

=back

The SVG data can be a single C<< <svg> >> element, or a container
element (e.g. C<< <html> >> or C<< <xml> >>) with one or more
C<< <svg> >> elements among its children.

=head1 OUTPUT

The result from calling process() is a reference to an array
containing hashes that describe the XObjects. Each hash has the
following keys:

=over 4

=item C<vbox>

The viewBox as specified in the SVG element.

If no viewBox is specified it is set to C<0 0> I<W H>, where I<W> and
I<H> are the width and the height.

=item C<width>

The width of the XObject, as specified in the SVG element or derived
from its viewBox.

=item C<height>

The height of the XObject, as specified in the SVG element or derived
from its viewBox.

=item C<vwidth>

The desired width, as specified in the SVG element or derived
from its viewBox.

=item C<vheight>

The desired height, as specified in the SVG element or derived
from its viewBox.

=item C<xo>

The XObject itself.

=back

=head1 FONT HANDLER CALLBACK

In SVG fonts are designated by style attributes C<font-family>,
C<font-style>, C<font-weight>, and C<font-size>. How these translate
to a PDF font is system dependent. PDF::SVG provides a callback
mechanism to handle this. As described at L<CONSTRUCTOR>, constructor
argument C<fc> can be set to designate a user routine.

When a font is required at the PDF level, PDF::SVG first checks if a
C<@font-face> CSS rule has been set up with matching properties. If a
match is found, it is resolved and the font is set. If there is no
appropriate CSS rule for this font, the callback is called with three
arguments:

    ( $pdf, $gfx, $style )

where C<$pdf> is de PDF document, C<$gfx> the graphics context where
the font must be set, and C<$style> a has reference that contains
values for C<font-family>, C<font-style>, C<font-weight>, and
C<font-size>.

The callback function can use the contents of C<$style> to select an
appropriate font, B<and set it on the graphics context>:

    $gfx->font( $font, $size );

B<IMPORTANT:> The callback function must return a 'true' result when
it did set the font. If it returns a 'false' result PDF::SVG will
fallback to default fonts.

Example of an (extremely simplified) callback:

    sub simple_font_handler {
        my ( $pdf, $gfx, $style ) = @_;

	my $family = $style->{'font-family'};
	my $size   = $style->{'font-size'};

	my $font;
	if ( $family eq 'sans' ) {
	    $font = $pdf->font('Helvetica');
	}
	else {
	    $font = $pdf->font('Times-Roman');
	}

	$gfx->font( $font, $size );

        return 1;
    }

If no callback function is set, PDF::SVG will recognize the standard
PDF corefonts, and aliases C<serif>, C<sans> and C<mono>.

B<IMPORTANT: With the standard corefonts only characters of the
ISO-8859-1 set (Latin-1) can be used. No greek, no chinese, no cyrillic.
You have been warned.>

=head1 LIMITATIONS

The following SVG elements are implemented.

=over 3

=item *

C<svg>, but not nested.

=item *

C<style>, as a child of the outer C<svg>.

Many style attributes are understood, including but not limited to:

color,
stroke, stroke-width, stroke-linecap, stroke-linejoin, stroke-dasharray,
fill, stroke-width, stroke-linecap, stroke-linejoin,
transform (translate, scale, skewX, skewY, rotate, matrix)
font-family, font-style, font-weight, font-size,
text-anchor.

Partially implemented: @font-face (src url data and local file only).

=item *

circle,
ellipse,
g,
image,
line,
path,
polygon,
polyline,
rect,
text and tspan.

=item *

defs and use,

=back

The following SVG features are partially implemented.

=over 3

=item *

Matrix transformations.

=item *

Nested SVG elements and preserveAspectRatio.

=item *

Standalone T-path elements.

=back

The following SVG features are not (yet) implemented.

=over 3

=item *

Percentage units.

=item *

title, desc elements

=back

The following SVG features will not be implemented.

=over 3

=item *

Shades, gradients, patterns and animations.

=item *

Transparency.

=back

=head1 AUTHOR

Johan Vromans C<< < jvromans at squirrel dot nl > >>

Code for circular and elliptic arcs donated by Phil Perry.

=head1 SUPPORT

PDF::SVG development is hosted on GitHub, repository
L<https://github.com/sciurius/perl-PDF-SVG>.

Please report any bugs or feature requests to the GitHub issue tracker,
L<https://github.com/sciurius/perl-PDF-SVG/issues>.

=head1 LICENSE

Copyright (C) 2022.2023 Johan Vromans,

Redistribution and use in source and binary forms, with or without
modification, are permitted provided under the terms of the Simplified
BSD License.

=cut

field $pdf          :accessor :param;
field $atts         :accessor :param = undef;

# Callback for font handling.
field $fc           :accessor :param = undef;

# If an SVG file contains more than a single SVG, the CSS applies to all.
field $css          :accessor;

# Font manager.
field $fontmanager  :accessor;

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
use SVG::FontManager;
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
use SVG::Style;
use SVG::Svg;
use SVG::Text;
use SVG::Tspan;
use SVG::Use;


################ General methods ################

# $pdf [ , fc => $callback ] [, atts => { ... } ] [, foo => bar ]
# pdf => $pdf [ , fc => $callback ] [, atts => { ... } ] [, foo => bar ]

sub BUILDARGS ( @args ) {
    my $cls = shift(@args);

    # Assume first is pdf if uneven.
    unshift( @args, "pdf" ) if @args % 2;

    my %args = @args;
    @args = ();
    push( @args, $_, delete $args{$_} ) for qw( pdf fc );

    # Flatten everything else into %atts.
    my %x = %{ delete($args{atts}) // {} };
    $x{$_} = $args{$_} for keys(%args);

    # And store as ref.
    push( @args, "atts", \%x );

    # Return new argument list.
    @args;
}

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
    $fontmanager  = SVG::FontManager->new( svg => $self );
    $self;
}

method process ( $data, %attr ) {

    # Load the SVG data.
    my $svg = SVG::Parser->new;
    my $tree = $svg->parse_file
      ( $data,
	whitespace_tokens => $wstokens||$attr{whitespace_tokens} );
    return unless $tree;

    # CSS persists over svgs, but not over files.
    $css = SVG::CSS->new;

    # Search for svg elements and process them.
    $self->search($tree);

    # Return (hopefully a stack of XObjects).
    return $xoforms;
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
confess("oeps") if length($indent) < 2;
	$indent = substr( $indent, 2 );
    }
    elsif ( $msg =~ /^\^\s*(.*)/ ) {
	$indent = "";
	warn( $indent, $1, "\n") if $1;
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

    $self->_dbg( "^ ==== start ", $e->{name}, " ====" );

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
	  atts    => { map { lc($_) => $e->{attrib}->{$_} } keys %{$e->{attrib}} },
	  content => $e->{content},
	  root    => $self,
	);

    # If there are <style> elements, these must be processed first.
    my $cdata = "";
    for ( $svg->get_children ) {
	next unless ref($_) eq "SVG::Style";
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

    # The viewport, llx lly width height.
    my $vbox   = delete $atts->{viewbox};

    # Width and height are the display size of the viewport.
    # Not relevant now, but needed later when the XObject is placed.
    my $vw = delete $atts->{width};
    my $vh = delete $atts->{height};

    delete $atts->{$_} for qw( xmlns:xlink xmlns:svg xmlns version );
    my $style = $svg->css_push($atts);

    my @vb;			# viewBox: llx lly width height
    my @bb;			# bbox:    llx lly urx ury

    # Currently we rely on the <svg> to supply the correct viewBox.
    my $width;			# width of the vbox
    my $height;			# height of the vbox
    if ( $vbox ) {
	@vb     = $svg->getargs($vbox);
	$width  = $svg->u($vb[2]);
	$height = $svg->u($vb[3]);
    }
    else {
	# Fallback to width/height, falling back to A4.
	$width  = $svg->u($vw||595);
	$height = $svg->u($vh||842);
	@vb     = ( 0, 0, $width, $height );
	$vbox = "@vb";
    }

    # Get llx lly urx ury bounding box rectangle.
    @bb = ( 0, 0, $vb[2], $vb[3] );
    $self->_dbg( "vb $vbox => bb %.2f %.2f %.2f %.2f", @bb );
    $xo->bbox(@bb);

    # Set up result forms.
    $xoforms->[-1] =
	  { xo      => $xo,
	    bbox    => [ @bb ],
	    vwidth  => $vw ? $svg->u($vw) : $vb[2],
	    vheight => $vh ? $svg->u($vh) : $vb[3],
	    vbox    => [ @vb ],
	    width   => $vb[2],
	    height  => $vb[3] };

    # <svg> coordinates are topleft down, so translate.
    $self->_dbg( "translate( %.2f %.2f )", -$vb[0], $vb[1]+$vb[3] );
    $xo->transform( translate =>         [ -$vb[0], $vb[1]+$vb[3] ] );

    if ( $debug ) {		# show bb
	$xo->save;
	$self->_dbg( "vb rect( %.2f %.2f %.2f %.2f)",
		        $vb[0], -$vb[1], $vb[2]+$vb[0], -$vb[1]-$vb[3]);
	$xo->rectangle( $vb[0], -$vb[1], $vb[2]+$vb[0], -$vb[1]-$vb[3]);
	$xo->fill_color("#ffffc0");
	$xo->fill;
	$xo->move(  $vb[0], 0 );
	$xo->hline( $vb[0]+$vb[2]);
	$xo->move( 0, -$vb[1] );
	$xo->vline( -$vb[1]-$vb[3] );
	$xo->line_width(0.5);
	$xo->stroke_color( "red" );
	$xo->stroke;
	$xo->restore;
    }
    $self->draw_grid( $xo, \@vb ) if $grid;


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

    $self->_dbg( "==== end ", $e->{name}, " ====" );
}

################ Service ################

method draw_grid ( $xo, $vb ) {
    my $d = $grid >= 5 ? $grid : 10;
    my @vb = @$vb;
    my $w = $vb[2];
    my $h = $vb[3];
    my $thick = 1;
    my $thin = 0.2;
    my $maxlines = 100;

    # Avoid too many grid lines.
    while ( $h/$d > $maxlines || $w/$d > $maxlines ) {
	$d += $d;
    }
 
    $xo->save;
    $xo->stroke_color("#bbbbbb");

    # Map viewbox to 0,0.
    $xo->transform( translate => [ $vb[0], -$vb[1] ] );

    # Show boundary points.
    my $dd = $d/2;
    $xo->rectangle(-$dd,-$dd,$dd,$dd);
    $xo->fill_color("blue");
    $xo->fill;
    $xo->rectangle( $vb[2]-$dd, -$vb[3]-$dd, $vb[2]+$dd, -$vb[3]+$dd);
    $xo->fill_color("blue");
    $xo->fill;
    # Show origin. This will cover the bb corner unless it is offset.
    $xo->rectangle( -$vb[0]-$dd, $vb[1]-$dd, -$vb[0]+$dd, $vb[1]+$dd);
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
