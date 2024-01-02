#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

class SVGPDF::Image :isa(SVGPDF::Element);

method process () {
    my $atts = $self->atts;
    my $xo   = $self->xo;
    return if $atts->{omit};	# for testing/debugging.

    my ( $x, $y, $w, $h, $link, $tf ) =
      $self->get_params( $atts, qw( x:H y:V width:H height:V href:! transform:s ) );

    $x ||= 0; $y ||= 0;
    $w ||= 0; $h ||= 0;

    unless ( $w && $h ) {
	$self->_dbg( $self->name, " x=$x y=$y w=$w h=$h  **skipped**" );
	return;
    }

    $self->_dbg( $self->name, " x=$x y=$y w=$w h=$h" );

    my $img;
    if ( $link =~ m!^data:image/(\w+);(base64),(.*)$!s ) {
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

	my $format = $info->{file_ext};
	$format = "jpeg" if $format eq "jpg";
	$format = "pnm"  if $format =~ /^p.m$/;
	$format = "tiff" if $format eq "tif";

	# Make the image. Silence missing library warnings.
	# Also, do not use the fast IPL module, it cannot read from scalar.
	open( my $fh, '<:raw', \$data );
	$img = $self->root->pdf->image( $fh, format => $format,
					silent => 1, nouseIPL => 1 );
    }
    elsif ( $link =~ m!^.+\.(png|jpe?g|gif)$!i && -s $link ) {
	# Autodetected. Make the image.
	$img = $self->root->pdf->image( $link, silent => 1 );
    }
    elsif ( $link =~ m!^.+\.(tiff?|pnm|pbm|pgm|ppm)$!i && -s $link ) {
	# Not autodetected, need format.
	my $format = lc $1;
	$format = $format =~ /tif/ ? "tiff" : "pnm";
	# Make the image.
	$img = $self->root->pdf->image( $link, format => $format, silent => 1 );
    }
    else {
	warn("SVG: Unhandled or missing image link: ",
	     "\"$link\""//"<undef>", "\n");
	return;
    }

    $self->_dbg( "xo save" );
    $xo->save;

    # Place the image.
    $self->set_transform($tf) if $tf;
    $xo->transform( translate => [ $x, $y+$h ] );
    $xo->image( $img, 0, 0, $w, -$h );

    $self->_dbg( "xo restore" );
    $xo->restore;
    $self->css_pop;
}


1;
