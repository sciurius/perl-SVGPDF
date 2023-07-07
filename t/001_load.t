#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'PDF::SVG' );
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
diag( "Using XML::Tiny version $XML::Tiny::VERSION" );
