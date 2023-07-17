#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVG::Image :isa(SVG::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my ( $x, $y, $w, $h, $link ) =
      $self->get_params( $atts, qw( x:U y:U width:U height:U xlink:href:! ) );

    $self->_dbg( $self->name, " x=$x y=$y w=$w h=$h" );

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

	# Make the image.
	$img = $self->root->ps->{pr}->{pdf}->image(IO::String->new($data));
    }
    else {
	warn("SVG: Unhandled or missing image link: ",
	     "\"$link\""//"<undef>", "\n");
	return;
    }

    $self->_dbg( "xo save" );
    $xo->save;

    # Place the image.
    $xo->transform( translate => [ $x, -$y-$h ] );
    $xo->image( $img, 0, 0, $w, $h );

    $self->_dbg( "xo restore" );
    $xo->restore;
    $self->css_pop;
}


1;
