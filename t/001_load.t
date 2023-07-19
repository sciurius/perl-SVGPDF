#! perl

use Test::More tests => 18;

BEGIN {
    # Load the elements first.
    use_ok("SVG::Circle");
    use_ok("SVG::CSS");
    use_ok("SVG::Defs");
    use_ok("SVG::Element");
    use_ok("SVG::Ellipse");
    use_ok("SVG::G");
    use_ok("SVG::Image");
    use_ok("SVG::Line");
    use_ok("SVG::Parser");
    use_ok("SVG::Path");
    use_ok("SVG::Polygon");
    use_ok("SVG::Polyline");
    use_ok("SVG::Rect");
    use_ok("SVG::Svg");
    use_ok("SVG::Text");
    use_ok("SVG::Tspan");
    use_ok("SVG::Use");

    # Master
    use_ok("PDF::SVG");
}

diag( "Testing PDF::SVG $PDF::SVG::VERSION, Perl $], $^X" );

my @pdfapi = ( 'PDF::API2' => 2.043 ); # default
if ( my $a = $ENV{PDF_SVG_API} ) {
    if ( $a =~ /PDF::Builder/ ) {
	@pdfapi = ( 'PDF::Builder' => 3.025 );
    }
    elsif ( $a =~ /PDF::API2/ ) {
    }
    else {
	@pdfapi = ( $a => 0 );
    }
}

diag( "Using $pdfapi[0] version $pdfapi[1]" );
