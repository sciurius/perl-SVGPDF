#! perl

use v5.26;
use Object::Pad;
use utf8;
class SVG::FontManager;

use Carp;

field $svg	:mutator :param;
field $fc       :mutator;

# Set a font according to the style.
#
# Strategy: First see if there was a @font-face defined. If so, use it.
# Then dispatch to user callback, if specified.
# Otherwise, try builtin fonts.

method set_font ( $xo, $style ) {

    use File::Temp qw( tempfile tempdir );
    use MIME::Base64 qw( decode_base64 );
    state $td = tempdir( CLEANUP => 1 );

    if ( $style->{'font-family'} && $style->{'@font-face'} ) {
	my $fam = lc( $style->{'font-family'}    // "<undef>" );
	my $stl = lc( $style->{'font-style'}     // "normal" );
	my $weight = lc( $style->{'font-weight'} // "normal" );

	# Font in cache?
	my $key = join( "|", $fam, $weight, $stl );
	if ( my $f = $fc->{$key} ) {
	    $xo->font( $f->{font},
		       $style->{'font-size'} || 12,
		       $f->{src} );
	    return;
	}

	my $ff = $style->{'@font-face'};
	for ( @$ff ) {
	    next unless $_->{'font-family'};
	    next unless $_->{src};
	    next unless $fam eq lc( $_->{'font-family'} );
	    next if $_->{'font-style'} && $style->{'font-style'}
	      && $_->{'font-style'} ne $style->{'font-style'};
	    next if $_->{'font-weight'} && $style->{'font-weight'}
	      && $_->{'font-weight'} ne $style->{'font-weight'};
 
	    my $src = $_->{src};
	    if ( $src =~ /^\s*url\s*\((["'])data:application\/octet-stream;base64,(.*?)\1\s*\)/is ) {
		my $data = $2;
		my ( $fh,$fn) = tempfile( "${td}SVGXXXX", SUFFIX => '.ttf' );
		binmode( $fh => ':raw' );
		print $fh decode_base64($data);
		close($fh);
		my $font = eval { $svg->pdf->font($fn) };
		croak($@) if $@;
		my $f = $fc->{$key} =
		  { font => $font,
		    src => 'data' };
		$xo->font( $f->{font},
			   $style->{'font-size'} || 12,
			   $f->{src} );
		return;
	    }
	    elsif ( $src =~ /^\s*url\s*\((["'])(.*?\.[ot]tf)\1\s*\)/is ) {
		my $fn = $2;
		my $font = eval { $svg->pdf->font($fn) };
		croak($@) if $@;
		my $f = $fc->{$key} =
		  { font => $font,
		    src => $fn };
		$xo->font( $f->{font},
			   $style->{'font-size'} || 12,
			   $f->{src} );
		return;
	    }
	    else {
		croak("\@font-face: Unhandled src \"", substr($src,0,50), "...\"");
	    }


	}
    }

    if ( $svg->fc ) {
	# Use user callback.
	return if $svg->fc->( $svg->pdf, $xo, $style );
    }

    # No @font-face, no (or failed) callback, we're on our own.

    my ( $fn, $sz, $em, $bd ) = ("Times-Roman", 12, 0, 0 );

    $fn = $style->{'font-family'} // "Times-Roman";
    $sz = $style->{'font-size'} || 12;
    $em = $style->{'font-style'}
      && $style->{'font-style'} =~ /^(italic|oblique)$/;
    $bd = $style->{'font-weight'}
      && $style->{'font-weight'} =~ /^(bold|black)$/;

    if ( $fn =~ /^(sans|helvetica|(?:text,)?sans-serif)$/i ) {
	$fn = $bd
	  ? $em ? "Helvetica-BoldOblique" : "Helvetica-Bold"
	  : $em ? "Helvetica-Oblique" : "Helvetica";
    }
    elsif ( $fn =~ /^abc2svg(?:\.ttf)?/ or $fn eq "music" ) {
	$fn = "abc2svg.ttf";
    }
    elsif ( $fn =~ /^musejazz\s*text$/ ) {
	$fn = "MuseJazzText.otf";
    }
    else {
	$fn = $bd
	  ? $em ? "Times-BoldItalic" : "Times-Bold"
	  : $em ? "Times-Italic" : "Times-Roman";
    }
    my $font = $fc->{$fn} //= do {
	{ font => $svg->pdf->font($fn), src => $fn };
    };
    $xo->font( $font->{font}, $sz, $font->{src} );
}

1;
