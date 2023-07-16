#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Line :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my $x1  = $self->u(delete($atts->{x1}) || 0);
    my $y1  = $self->u(delete($atts->{y1}) || 0);
    my $x2  = $self->u(delete($atts->{x2}) || 0);
    my $y2  = $self->u(delete($atts->{y2}) || 0);

    $self->css_push;
    my $style = $self->style;

    $self->_dbg( $self->getElementName, " x1=$x1 y1=$y1 x2=$x2 y2=$y2" );
    $self->_dbg( "+ xo save" );
    $xo->save;

    $self->set_graphics;

    $xo->move( $x1, -$y1 );
    $xo->line( $x2, -$y2 );
    $self->_paintsub->();

    $self->_dbg( "- xo restore" );
    $xo->restore;
    $self->css_pop;
}


1;
