#!/usr/bin/perl

# Author          : Johan Vromans
# Created On      : Wed Jul  5 09:14:28 2023
# Last Modified By: 
# Last Modified On: Fri Jul 21 07:35:25 2023
# Update Count    : 102
# Status          : Unknown, Use with caution!

################ Common stuff ################

use v5.36;
use feature qw(signatures);
no warnings qw(experimental::signatures);
use utf8;

# Package name.
my $my_package = 'PDF-SVG';
# Program name and version.
my ($my_name, $my_version) = qw( svgpdf 0.01 );

use FindBin;
use lib "$FindBin::Bin/../lib";

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $output = "__new__.pdf";
my $api = "PDF::API2";		# or PDF::Builder
my $wstokens = 1;
my $grid;			# add grid
my $prog;			# generate program
my $verbose = 1;		# verbose processing

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);

################ Presets ################

my @pgsz = ( 595, 842 );	# A4

################ The Process ################

eval "require $api;"     || die($@);
# PDF::SVG may redefine some PDF:XXX modules.
eval "require PDF::SVG;" || die($@);

my $pdf = $api->new;
$api->add_to_font_path($ENV{HOME}."/.fonts");
my $page = $pdf->page;
$page->size( [ 0, 0, @pgsz ] );
my $gfx = $page->gfx;
my $x = 0;
my $y = $pgsz[1];

foreach my $file ( @ARGV ) {
    my $p = PDF::SVG->new
      ( pdf => $pdf,
	atts => { debug    => $debug,
		  grid     => $grid,
		  prog     => $prog,
		  wstokens => $wstokens,
		  trace    => $trace } );

    $p->process($file);
    my $o = $p->xoforms;
    warn("$file: SVG objects: ", 0+@$o, "\n") if $verbose;

    my $i = 0;
    foreach my $xo ( @$o ) {
	$i++;
	if ( ref($xo->{xo}) eq "PDF::PAST" ) {
	    if ( $prog ) {
		open( my $fd, '>', $prog );
		my $pdf = $prog =~ s/\.pl$/.pdf/r;
		print $fd ( "#! perl\n",
			    "use v5.26;\n",
			    "use utf8;\n",
			    "use $api;\n",
			    "my \$pdf  = $api->new;\n",
			    "my \$page = \$pdf->page;\n",
			    "my \$xo   = \$page->gfx;\n",
			    "my \$font = \$pdf->font('Times-Roman');\n",
			    "\n",
			    $xo->{xo}->prog,
			    "\n\$pdf->save('$pdf');\n" );
		close($fd);
	    }
	    $xo->{xo} = $xo->{xo}->xo;
	}
	my @bb = @{$xo->{vbox}};
	my $w = $bb[2];
	my $h = $bb[3];
	my $scale = 1;
	if ( $xo->{vwidth} ) {
	    $scale = $xo->{vwidth} / $w;
	}
	if ( $w*$scale > $pgsz[0] ) {
	    $scale *= $pgsz[0]/$w;
	}

	if ( $y - $h * $scale < 0 ) {
	    $page = $pdf->page;
	    $page->size( [ 0, 0, @pgsz ] );
	    $gfx = $page->gfx;
	    $x = 0;
	    $y = $pgsz[1];
	}
	warn(sprintf("object %d [ %.2f, %.2f %s] ( %.2f, %.2f, %.2f, %.2f @%.2f )\n",
		     $i, $w, $h,
		     $xo->{vwidth}
		     ? sprintf("=> %.2f, %.2f ", $xo->{vwidth}, $xo->{vheight})
		     : "",
		     $x, $y-$h*$scale, $w, $h, $scale ))
	  if $verbose;

	crosshairs( $gfx, $x, $y, "blue" );
	if ( $bb[0] || $bb[1] ) {
	    crosshairs( $gfx, $x-$bb[0]*$scale, $y+$bb[1]*$scale, "red" );
	}
	$gfx->object( $xo->{xo}, $x, $y-$h*$scale, $scale );

	$y -= $h * $scale;
    }
    crosshairs( $gfx, $x, $y, "blue" );
}

$pdf->save($output);

################ Subroutines ################

sub crosshairs ( $gfx, $x, $y, $col = "black" ) {
    for ( $gfx  ) {
	$_->save;
	$_->line_width(0.1);
	$_->stroke_color($col);
	$_->move($x-20,$y);
	$_->hline($x+20);
	$_->stroke;
	$_->move($x,$y+20);
	$_->vline($y-20);
	$_->stroke;
	$_->restore;
    }
}

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
		     'output=s' => \$output,
		     'program=s' => \$prog,
		     'grid:i'	=> \$grid,
		     'builder'	=> sub { $api = "PDF::Builder";
					 push( @INC, $ENV{HOME}."/src/PDF-Builder/lib" );
					 },
		     'api=s'	=> \$api,
		     'ws!'	=> \$wstokens,
		     'ident'	=> \$ident,
		     'verbose+'	=> \$verbose,
		     'quiet'	=> sub { $verbose = 0 },
		     'trace'	=> \$trace,
		     'help|?'	=> \$help,
		     'debug+'	=> \$debug,
		    ) or $help )
    {
	app_usage(2);
    }
    app_ident() if $ident;
    $grid = 5 if defined($grid) && $grid < 5;
}

sub app_ident {
    print STDERR ("This is $my_package [$my_name $my_version]\n");
}

sub app_usage {
    my ($exit) = @_;
    app_ident();
    print STDERR <<EndOfUsage;
Usage: $0 [options] [svg-file ...]
   --output=XXX		PDF output file name
   --program=XXX	generates a perl program (single SVG only)
   --api=XXX		uses PDF API (PDF::API2 (default) or PDF::Builder)
   --builder		short for --api=PDF::Builder
   --grid=N             provides a grid with spacing N
   --nows               ignore whitespace tokens
   --ident		shows identification
   --help		shows a brief help message and exits
   --verbose		provides more verbose information
   --quiet		runs as silently as possible
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}

