#! perl

use strict;
use warnings;

# Integration tests.
#
# We intercept the debugging output and compare these.

use Test::More;

my $api;

BEGIN {
    $api = "PDF::API2";
    use_ok($api);
    use_ok("PDF::SVG");
}

my $test = 2;

-d "t" && chdir("t");
BAIL_OUT("Missing test data") unless -d "svg";

# Setup PDF context.
my $pdf = $api->new;
my $page = $pdf->page;
my $gfx = $page->gfx;

my $p = PDF::SVG->new
  ( pdf => $pdf, fc => \&fontcallback,
    atts => { debug    => 1, wstokens => 1 } );

ok( $p, "Have PDF::SVG object" );
$test++;

# Collect the test files.
opendir( my $dh, "svg" ) || BAIL_OUT("Cannot open test data");
my @files = grep { /^.+\.svg$/ } readdir($dh);
close($dh);
diag("Testing ", scalar(@files), " SVG files");

foreach my $file ( sort @files ) {
    $file = "svg/$file";
    #diag("Testing: $file");
    ( my $out = $file ) =~ s/\.svg/.out/;
    ( my $ref = $file ) =~ s/\.svg/.ref/;

    my $o;

    # Run test, and intercept stderr.
    my $errfd;
    open( $errfd, '>&', \*STDERR );
    close(STDERR);
    open( STDERR, '>:utf8', $out );
    $o = eval { $p->process( $file, reset => 1 ) };
    close(STDERR);
    open( STDERR, '>&', $errfd );

    ok( $o && @$o, "Have XO results" );
    $test++;

    my $ok = -s $ref && !differ( $out, $ref );
    ok( $ok, $file );
    $test++;
    unlink($out), next if $ok;
    system( $ENV{PDFSVG_DIFF}, $out, $ref) if $ENV{PDFSVG_DIFF};
}

ok( $test == 2*@files+3, "Tested @{[0+@files]} files" );
$test++;
done_testing($test);

use File::LoadLines qw( loadlines );

sub differ {
    my ($file1, $file2) = @_;
    $file2 = "$file1" unless $file2;
    $file1 = "$file1";

    my @lines1 = loadlines($file1);
    my @lines2 = loadlines($file2);
    my $linesm = @lines1 > @lines2 ? @lines1 : @lines2;
    for ( my $line = 1; $line < $linesm; $line++ ) {
	next if $lines1[$line] eq $lines2[$line];
	Test::More::diag("Files $file1 and $file2 differ at line $line");
	Test::More::diag("  <  $lines1[$line]");
	Test::More::diag("  >  $lines2[$line]");
	return 1;
    }
    return 0 if @lines1 == @lines2;
    $linesm++;
    Test::More::diag("Files $file1 and $file2 differ at line $linesm" );
    Test::More::diag("  <  ", $lines1[$linesm] // "***missing***");
    Test::More::diag("  >  ", $lines2[$linesm] // "***missing***");
    1;
}

my $font;
sub fontcallback {
    my ( $pdf, $xo, $style ) = @_;
    $font //= $pdf->font('Times-Roman');
    $xo->font($font,10);
}
