#! perl

use v5.26;
use Object::Pad;
use utf8;
use Carp;

# SVG Parser, based on a modified version of XML::Tiny.

class SVG::Parser;

use File::LoadLines;
use XML::Tiny;

field $debug;

method parse_file ( $fname, %args ) {
    $debug = $args{debug} if defined $args{debug};
    my $data = loadlines( $fname, { split => 0, chomp => 0 } );
    $self->parse_string( $data, %args );
}

method parse_string ( $data, %args ) {
    if ( $debug ) {
	# Make it easier to read/write long lines and disable parts.
	$data =~ s/^#.*//mg;
	$data =~ s/\\[\n\r]+\s*//g;
    }
    XML::Tiny::parsefile( "_TINY_XML_STRING_".$data, %args );
}

1;
