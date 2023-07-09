#! perl

use v5.26;
use Object::Pad;
use Carp;
use utf8;

# Use this package as an intermediate to trace the actual operations.

class PDF::SVG::PAST;

use Carp;

field $pdf :param;
field $xo  :accessor;

sub xdbg ( $fmt, @args ) {
    PDF::SVG::xdbg( $fmt, @args );
}

BUILD {
    xdbg( 'use PDF::API2;' );
    xdbg( 'my $pdf  = PDF::API2->new;' );
    xdbg( 'my $page = $pdf->page;' );
    xdbg( 'my $xo   = $page->gfx;' );
    xdbg( 'my $font = $pdf->font("Times-Roman");' );
    xdbg( '' );
    $xo = $pdf->xo_form;
}

#### Coordinates

method bbox ( @args ) {
    xdbg( "\$page->bbox( ", join(", ", @args ), " );" );
    $xo->bbox( @args );
}

method transform ( %args ) {
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
    $xo->transform( %args );
}

#### Graphics.

method fill_color ( @args ) {
    Carp::confess("currentColor") if $args[0] eq 'currentColor';
    xdbg( "\$xo->fill_color( @args );" );
    $xo->fill_color( @args );
}

method stroke_color ( @args ) {
    xdbg( "\$xo->stroke_color( @args );" );
    $xo->stroke_color( @args );
}

method fill ( @args ) {
    die if @args;
    xdbg( "\$xo->fill();" );
    $xo->fill( @args );
}

method stroke ( @args ) {
    die if @args;
    xdbg( "\$xo->stroke();" );
    $xo->stroke( @args );
}

method line_width ( @args ) {
    xdbg( "\$xo->line_width( ", join(", ", @args ), " );" );
    $xo->line_width( @args );
}

method line_dash_pattern ( @args ) {
    xdbg( "\$xo->line_dash_pattern( ", join(", ", @args ), " );" );
    $xo->line_dash_pattern( @args );
}

method paint ( @args ) {
    die if @args;
    xdbg( "\$xo->paint();" );
    $xo->paint( @args );
}

method save ( @args ) {
    die if @args;
    xdbg( "\$xo->save();" );
    $xo->save( @args );
}

method restore ( @args ) {
    die if @args;
    xdbg( "\$xo->restore();" );
    $xo->restore( @args );
}

#### Texts,

method textstart ( @args ) {
    die if @args;
    xdbg( "\$xo->textstart();" );
    $xo->textstart( @args );
}

method textend ( @args ) {
    die if @args;
    xdbg( "\$xo->textend();" );
    $xo->textend( @args );
}

method font ( $font, $size, $name ) {
    xdbg( "\$xo->font( \$font, $size );\t# $name" );
    $xo->font( $font, $size );
}

method text ( $text, %opts ) {
    my $t = $text;
    if ( length($t) == 1 && ord($t) > 255 ) {
	$t = sprintf("\\x{%04x}", ord($t));
    }
    xdbg( "\$xo->text( \"$t\", ",
	  join( ", ", map { "$_ => \"$opts{$_}\"" } keys %opts ),
	  " );" );
    $xo->text( $text, %opts );
}

#### Paths.

method move ( @args ) {
    xdbg( "\$xo->move( ", join(", ",@args), " );" );
    $xo->move( @args );
}

method hline ( @args ) {
    xdbg( "\$xo->hline( @args );" );
    $xo->hline( @args );
}

method vline ( @args ) {
    xdbg( "\$xo->vline( @args );" );
    $xo->vline( @args );
}

method line ( @args ) {
    xdbg( "\$xo->line( ", join(", ",@args), " );" );
    $xo->line( @args );
}

method curve ( @args ) {
    xdbg( "\$xo->curve( ", join(", ",@args), " );" );
    $xo->curve( @args );
}

method rect ( @args ) {
    xdbg( "\$xo->rect( ", join(", ",@args), " );" );
    $xo->rect( @args );
}

method rectangle ( @args ) {
    xdbg( "\$xo->rectangle( ", join(", ",@args), " );" );
    $xo->rectangle( @args );
}

method circle ( @args ) {
    xdbg( "\$xo->circle( ", join(", ",@args), " );" );
    $xo->circle( @args );
}

method polyline ( @args ) {
    xdbg( "\$xo->polyline( ", join(", ",@args), " );" );
    $xo->polyline( @args );
}

method close ( @args ) {
    die if @args;
    xdbg( "\$xo->close();" );
    $xo->close( @args );
}

#### Misc.

method finish :common () {
    PDF::SVG::xdbg->( "\$pdf->save(\"z.pdf\");" );
}

DESTROY {
    finish();
}

1;
