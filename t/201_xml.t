#! perl

# Test if the XML parser delivers whitespace elements.

use Test::More tests => 2;
use XML::Tiny;

my $res = XML::Tiny::parsefile( <<EOD, whitespace_tokens => 1 );
_TINY_XML_STRING_<x><y>aaa</y> <y>bbb</y> <y>ccc</y>dddd</x>
EOD

is_deeply( $res,
	   [
	    {
	     attrib => {},
	     content => [
			 {
			  attrib => {},
			  content => [{content => 'aaa', type => 't',},],
			  name => 'y',
			  type => 'e',
			 },
			 {
			  content => ' ',
			  type => 't',
			 },
			 {
			  attrib => {},
			  content => [{content => 'bbb', type => 't',},],
			  name => 'y',
			  type => 'e',
			 },
			 {
			  content => ' ',
			  type => 't',
			 },
			 {
			  attrib => {},
			  content => [{content => 'ccc', type => 't',},],
			  name => 'y',
			  type => 'e',
			 },
			 {
			  content => 'dddd',
			  type => 't',
			 },
			],
	     name => 'x',
	     type => 'e',
	    },
	   ]
	   , "result" );

my $res = XML::Tiny::parsefile( <<EOD );
_TINY_XML_STRING_<x><y>aaa</y> <y>bbb</y> <y>ccc</y>dddd</x>
EOD

is_deeply( $res,
	   [
	    {
	     attrib => {},
	     content => [
			 {
			  attrib => {},
			  content => [{content => 'aaa', type => 't',},],
			  name => 'y',
			  type => 'e',
			 },
			 {
			  attrib => {},
			  content => [{content => 'bbb', type => 't',},],
			  name => 'y',
			  type => 'e',
			 },
			 {
			  attrib => {},
			  content => [{content => 'ccc', type => 't',},],
			  name => 'y',
			  type => 'e',
			 },
			 {
			  content => 'dddd',
			  type => 't',
			 },
			],
	     name => 'x',
	     type => 'e',
	    },
	   ]
	   , "result" );
