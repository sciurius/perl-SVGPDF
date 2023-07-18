#! perl

use Test::More tests => 2;
use SVG::CSS;

my $css = SVG::CSS->new;

is_deeply( $css->base,
	   {
	    'background-color'	=> 'white',
	    color		=> 'black',
	    fill		=> 'currentColor',
	    'font-family'	=> 'serif',
	    'font-size'		=> 10,
	    'line-width'	=> 1,
	    stroke		=> 'none',
	   },
	   "base" );

is_deeply( $css->css, {}, "empty" );

