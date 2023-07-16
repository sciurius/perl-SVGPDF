#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Circle :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my $cx  = $self->u(delete($atts->{cx})     ) || 0;
    my $cy  = $self->u(delete($atts->{cy})     ) || 0;
    my $r   = $self->u(delete($atts->{r}) ) || 0;

    $self->css_push;

    $self->_dbg( $self->name, " cx=$cx cy=$cy r=$r" );
    $self->_dbg( "+ xo save" );
    $xo->save;

    $self->set_graphics;
    $xo->circle( $cx, -$cy, $r );
    $self->_paintsub->();

    $self->_dbg( "- xo restore" );
    $xo->restore;
    $self->css_pop;
}


1;
