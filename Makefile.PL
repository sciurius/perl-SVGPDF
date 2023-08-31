#! perl

use strict;
use warnings;

exit 0 if $ENV{AUTOMATED_TESTING} && $] < 5.026000;

use ExtUtils::MakeMaker 7.24;	# comes with 5.26

# For binaries/scripts.
my @bins; # = qw( prog );

my @pdfapi = ( 'PDF::API2' => 2.043 ); # default
if ( my $a = $ENV{SVGPDF_API} ) {
    if ( $a =~ /PDF::Builder/ ) {
	@pdfapi = ( 'PDF::Builder' => 3.025 );
    }
    elsif ( $a =~ /PDF::API2/ ) {
    }
    else {
	@pdfapi = ( $a => 0 );
    }
}

WriteMakefile(
    NAME                => 'SVGPDF',
    AUTHOR              => 'Johan Vromans <jvromans@squirrel.nl>',
    VERSION_FROM        => 'lib/SVGPDF.pm',
    ABSTRACT            => 'SVG processor for PDF::API2',
    LICENSE             => 'perl_5',
    PL_FILES            => {},
    MIN_PERL_VERSION    => 5.026000,

    @bins == 0 ? () : (
      EXE_FILES         => [ map { "script/$_" } @bins ],
      PL_FILES          => {
                             'script/pp.PL' => [ map { "script/$_" } @bins ]
                           },
    ),

    PREREQ_PM      => {
			@pdfapi,
			'File::LoadLines'	=> 1.021,
			'Image::Info'           => 1.42,
			'Object::Pad'           => 0.78,
		      },

    CONFIGURE_REQUIRES => {
			'ExtUtils::MakeMaker'	=> 7.24,
		       },

    META_MERGE => {
      resources    => {
        repository => 'https://github.com/sciurius/perl-DVG-PDF',
        bugtracker => "https://github.com/sciurius/perl-DVG-PDF/issues",
        license    => "https://dev.perl.org/licenses/",
      },
      'meta-spec' => {
        version => '2',
        url     => 'https://metacpan.org/pod/CPAN::Meta::Spec',
      },
    },
);
