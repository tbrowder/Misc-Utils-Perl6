#!/usr/bin/env perl6

# standard for self-documenting a program
#------------------------------------------------------------------------------
# Program create-md.p6
# Purpose : Create markdown documentation for programs in a github repository
# Help    : Yes

use Getopt::Std;
use Misc::Utils;

my $max-line-length = 78;

##### option handling ##############################
my %opts; # Getopts::Std requires this (name it anything you want)
# ensure we have a var for each option
my ($mfil, $bdir, $odir, $nofold, $debug, $verbose);
my $usage = "Usage: $*PROGRAM -m <file> | -b <bin dir> | -h [-d <odir>, -N, -M <max>, -D]";
sub usage() {
   print qq:to/END/;
   $usage

   Reads the input module (or program files in the bin dir) and
   extracts properly formatted comments into markdown files describing
   the subs and other objects contained therein.  Output files are
   created in the output directory (-d <dir>) if entered, or the
   current directory otherwise.

   Subroutine signature lines are folded into a nice format for the
   markdown files unless the user uses the -N (no-fold) option.  The
   -M <max> option specifies a user-desired maximum line length for
   folding.  The signature is output as a code block.

   In program files, the comments are folded into lines no longer than
   the maximum line length.  If the program has a help option (-h),
   the result of that command will be added to the output as a code
   block.

   See the lib/Misc and bin directories for a module file and a program with the
   known formats.  The markdown files in the docs directory in this
   repository were created with this program from those files.

   Modes (select one only):

     -m <module file>
     -b <bin directory>
     -h help

   Options:

     -d <output directory>    default: current directory
     -M <max line length>     default: $max-line-length

     -N do NOT format or modify sub signature lines to max length
     -v verbose
     -D debug
   END

   #say %opts.perl;

   exit;
}

# provide a short msg if no args
if !@*ARGS.elems {
    say $usage;
    exit;
}

# collect the options
getopts(
    'hDvN' ~ 'b:m:d:M:',  # option string (':' following an arg means a value for the arg is required)
    %opts,
    @*ARGS
);

# help overrides all
usage() if %opts<h>;

# set options
$odir            = %opts<d> ?? %opts<d> !! '';
$max-line-length = %opts<M> if %opts<M>;
$debug           = True if %opts<D>;
$verbose         = True if %opts<v>;
$nofold          = True if %opts<N>;
$bdir            = %opts<b> ?? %opts<b> !! '';
$mfil            = %opts<m> ?? %opts<m> !! '';

# check mandatory args
if !($mfil || $bdir) {
    say "ERROR: No mode was selected.";
    say $usage;
    exit;
}
elsif $mfil && $bdir {
    say "ERROR: Multiple modes were selected.";
    say $usage;
    exit;
}
##### end option handling ##########################

# aliases
my $modfil = $mfil;
my $tgtdir = $odir;
my $bindir = $bdir;

# the following two hashes have values for the leading
# markdown code for the key parts
my %kw = [
    # subroutines
    'Subroutine' => '###',
    'Purpose'    => '-',
    'Params'     => '-',
    'Returns'    => '-',

    'title:'     => '#',
    'file:'      => '',
];

my %kwp = [
    # programs
    'Program'    => '###',
    'Purpose'    => '-',
    'Help'       => '',
];

say %kw.perl if $debug;
say %kwp.perl if $debug;

# HANDLE SUBROUTINES =================================================
my %mdfils;
if $modfil {
    create-subs-md($modfil);
    say %mdfils.perl if $debug;

    my @ofils;
    for %mdfils.keys -> $f is copy {
	# distinguish between file base name and path
	my $of = $f;
	$of = $tgtdir ~ '/' ~ $of if $tgtdir;
	my $fh = open $of, :w;

	$fh.say: %mdfils{$f}<title>;

	my %hs = %(%mdfils{$f}<subs>);
	my @subs = %hs.keys.sort;

        # need to make a TOC
        create-toc-md($fh, 'Contents', @subs, 3, :add-link(True));

	for @subs -> $s {
            say "sub: $s" if $debug;
            my @lines = @(%hs{$s});
            for @lines -> $line {
		$fh.say: $line;
            }
	}
	$fh.close;
        @ofils.push($of);
    }

    my $s = @ofils.elems > 1 ?? 's' !! '';
    say "see output file$s:";
    say "  $_" for @ofils;

}

# HANDLE BINARY PROGS =================================================
my %binfils;
if $bindir {
    create-bin-md($bindir);
    say %binfils.perl if $debug;

    # distinguish between file base name and path
    my $of = 'PROGRAMS.md';
    $of = $tgtdir ~ '/' ~ $of if $tgtdir;
    my $fh = open $of, :w;

    my $title = '# Programs';
    $fh.say: $title;

    my @progs = %binfils.keys.sort;
    # need to make a TOC
    create-toc-md($fh, 'Contents', @progs, 1, :add-link(True));

    for @progs -> $p {
        say "program: $p" if $debug;
        my @lines = @(%binfils{$p});
        for @lines -> $line {
            $fh.say: $line;
        }
    }

    $fh.close;
    say "see output file '$of'";
}

#### subroutines #####
sub create-bin-md($d) {
    # HANDLES PROGRAMS

    # %h{$program} = @lines;

    my $program; # current program name

    # open the bin directory
    my @fils = $d.IO.dir;
    say "Files in dir '$d':";
    for @fils -> $f {
	# for now assume it's a prog (TODO docs show auto finding files, NOT so)
	my $is-file = $f.f ?? True !! False;
	if !$is-file {
	    say "  '$f' is a directory...skipping";
	    next;
	}
	say "  '$f' is a file...processing";

	# open the program file
        my $program;
	my $fp = open $f;
	for $fp.lines -> $line is copy {
            say $line if $debug;
            next if $line !~~ / \S /; # skip empty lines
            # ensure there is a space following any leading '#'
            $line ~~ s/^ \s* '#' \S /^\# /;
            my @words = $line.words;
            my $nw = @words;

            if $line ~~ /^ \s* '#' / {
		next if $nw < 3;
 		my $kw  = @words[1];
 		my $val = @words[2];
		say "possible keyword '$kw'" if $debug;
		#say "possible keyword '$kw'";
		next if not %kwp{$kw}:exists;
		say "found keyword '$kw'" if $debug;
		# get the actual line to be output
		my $txt = get-kw-line-data(:val(%kwp{$kw}), :$kw, :words(@words[1..*]));
		say "text value: '$txt'" if $debug;
		# next action depends on keyword
		if $kw eq 'Program' {
                    # update the program name
                    $program = $val;
                    # sanity check
                    die "FATAL: File '$f' and prog name '$program' differ" if $f !~~ /$program/;
                    # start a new array
                    %binfils{$program} = [];
                    %binfils{$program}.push($txt);
		}
		else {
                    # all other lines go onto the array
                    %binfils{$program}.push($txt);

                    if $kw eq 'Help' && $val ~~ /:i y/ {
                        # generate the help text
                        say 'Tom: fix this with a sub, add text';
                        %binfils{$program}.push(get-help-lines($f));
                    }
		}
            }

	}

    }

} # create-bin-md

sub get-help-lines($prog) {
    return 'FINISH THE GET HELP SUB';
} # get- help-lines

sub create-subs-md($f) {
    # HANDLES MODULES

    # %h{$fname}<title> = $title
    #           <subs>{$subname} = @lines

    my $fname;   # current output file name
    my $title;   # current title for the file contents
    my $subname; # current sub name

    # open the desired module file
    my $fp = open $f;
    for $fp.lines -> $line is copy {
        say $line if $debug;
        next if $line !~~ / \S /; # skip empty lines
        # ensure there is a space following any leading '#'
        $line ~~ s/^ \s* '#' \S /^\# /;
        my @words = $line.words;
        my $nw = @words;

        if $line ~~ /^ \s* '#' / {
            next if $nw < 3;
 	    my $kw  = @words[1];
 	    my $val = @words[2];
            say "possible keyword '$kw'" if $debug;
            #say "possible keyword '$kw'";
            next if not %kw{$kw}:exists;
            say "found keyword '$kw'" if $debug;
            # get the actual line to be output
            my $txt = get-kw-line-data(:val(%kw{$kw}), :$kw, :words(@words[1..*]));
            say "text value: '$txt'" if $debug;
            # next action depends on keyword
            if $kw eq 'file:' {
                # start a new file
                $fname = $val;
            }
            elsif $kw eq 'title:' {
                # update the title name
                $title = $txt;
                %mdfils{$fname}<title> = $title;
            }
            elsif $kw eq 'Subroutine' {
                # update the subroutine name
                $subname = $val;
                # start a new array
                %mdfils{$fname}<subs>{$subname} = [];
                %mdfils{$fname}<subs>{$subname}.push($txt);
            }
            else {
                # all other lines go onto the array
                %mdfils{$fname}<subs>{$subname}.push($txt);
            }
        }
        elsif $line ~~ /^ sub \s* / {
            # start sub signature
            say "found sub sig '$line'" if $debug;
            my @sublines;
            # get the whole signature
            while $line !~~ / '{' / {
                # not the end of signature
                @sublines.push: $line;
                $line = $fp.get;
                say "next line: $line" if $debug;
            }
            # don't forget the last chunk with the opening curly brace
            say "=== DEBUG last line sub sig: '$line'" if $debug;
	    # first add a closing '}'
            my $idx = rindex $line, '{';
            if !$idx.defined {
                die "FATAL: unable to find an opening '\{' in sub sig line '$line'";
            }
            $line = substr $line, 0, $idx + 1;
            # add closure after the opening curly to indcate the sub block
            $line ~= '#...}';
	    # finally, add to the sublines array
            @sublines.push: $line;

            if $debug {
                say "=== complete sub sig:";
                for @sublines {
                    say $_;
                }
                say "=== end complete sub sig:";
            }

            # tidy the line into two (or more) lines (unless user declines)
            @sublines = fold-sub-lines(@sublines, $subname) if !$nofold;

            # push lines on the current element
            say "DEBUG: sub sig lines" if $debug;
            # need a line to indicate perl 6 code
            %mdfils{$fname}<subs>{$subname}.push: '```perl6';
            for @sublines -> $line {
                %mdfils{$fname}<subs>{$subname}.push: $line;
                say "  line: '$line'" if $debug;
            }
            # need a line to indicate end of perl 6 code
            %mdfils{$fname}<subs>{$subname}.push: '```';
        }
    }
} # create-subs-md

sub fold-sub-lines(@sublines, $subname) returns List {
    # get one long string to start with
    my $sig = normalize-string(join ' ', @sublines);

{
    # error checks
    my $idx = index $sig, ')';
    die "FATAL: unable to find a closing ')' in sub sig '$sig'" if !$idx.defined;
    $idx = index $sig, '{#...}';
    die "FATAL: unable to find ending '\{#...}' in sub sig '$sig'" if !$idx.defined;
    $idx = index $sig, '(';
    die "FATAL: unable to find opening '(' in sub sig '$sig'" if !$idx.defined;
}

    my @lines;

    # ideally we break into two lines after the params ')';
    # note we break regardless of line length at this point
    my ($line1, $last-line) = split-line($sig, ')');
    # indent two spaces on the last line
    $last-line = '  ' ~ $last-line;
    if $last-line.chars > $max-line-length {
        die "UNEXPECTED last line too long: '$last-line'";
    }

    if $line1.chars > $max-line-length {
        my $idx = index $line1, '(';
        my $fold-indent = ' ' x $idx+1;
        my $first-line = True;

        # keep splitting until done
        my @tlines;
        my $s1 = $line1;
        my $s2 = '';

        loop {
            $s2 = split-line-rw($s1, ',', :max-line-length($max-line-length), :rindex(True));
            # $s1 is known good
            #$s1 = $fold-indent ~ $s1 if !$first-line;
            @tlines.push($s1);
            $first-line = False;

            if !$s2 {
                # we're done
                last;
            } 

            # add the standard indent to the opening paren
            $s2 = $fold-indent ~ $s2;
            if $s2.chars <= $max-line-length {
                # we're done
                @tlines.push($s2);
                last;
            }

            # need another split
            $s1 = $s2;
            $s2 = '';
        }
        if $debug {
            say "DEBUG: in sub $subname, @tlines:";
            say "  lines:";
            say "    $_" for @tlines;
        }

        @lines.push($_) for @tlines;
    }
    else {
        @lines.push($line1);
    }

    # don't forget the last line!
    @lines.push($last-line);

    # sanity check
    my ($maxlen, $maxidx) = analyze-line-lengths(@lines);
    if $maxlen > $max-line-length {
        say "WARNING: in sub $subname: maxlen = $maxlen, maxidx = $maxidx";
        say "  lines:";
        say "    $_" for @lines;
    }
    # return the folded lines
    say "NOTE:  sub '$subname' lines were folded" if $verbose;
    return @lines;

}

# candidate for a util module
sub analyze-line-lengths(@lines) returns List {
    # returns:
    #   max line length in the input array
    #   the index of the longest line

    # collect stats
    my $nl = +@lines;
    my %nc;
    my $maxlen = 0;
    my $maxidx = 0;
    my $i = 0;
    for @lines -> $line {
        my $m = $line.chars;
        %nc{$i} = $m;
        if $m > $maxlen {;
            $maxlen = $m;
            $maxidx = $i;
        }
        ++$i;
    }

    return ($maxlen, $maxidx);

} # analyze-line-lengths

# TODO: candidates for a util module
sub normalize-string(Str:D $str is copy) returns Str {
    $str ~~ s:g/ \s ** 2..*/ /;
    return $str;
} # normalize-string
sub normalize-string-rw(Str:D $str is rw) {
    $str ~~ s:g/ \s ** 2..*/ /;
} # normalize-string-rw

sub split-line(Str:D $line is copy, Str:D $brk, UInt :$max-line-length = 78, UInt :$start-pos = 0, Bool :$rindex = False) returns List {
    my $line2 = '';
    return ($line, $line2) if $max-line-length && $line.chars <= $max-line-length;
    
    my $idx;
    if $rindex {
        my $spos = max $start-pos, $max-line-length;
        $idx = $spos ?? rindex $line, $brk, $spos !! rindex $line, $brk;
    }
    else { 
        $idx = $start-pos ?? index $line, $brk, $start-pos !! index $line, $brk;
    }
    if $idx.defined {
        $line2 = substr $line, $idx+1;
        $line  = substr $line, 0, $idx+1;

        $line  .= trim-trailing;
        $line2 .= trim;
    }
    return ($line, $line2);

} # split-line

sub split-line-rw(Str:D $line is rw, Str:D $brk, UInt :$max-line-length = 78, UInt :$start-pos = 0, Bool :$rindex = False) returns Str {
    my $line2 = '';
    return $line2 if $max-line-length && $line.chars <= $max-line-length;
    
    my $idx;
    if $rindex {
        my $spos = max $start-pos, $max-line-length;
        $idx = $spos ?? rindex $line, $brk, $spos !! rindex $line, $brk;
    }
    else { 
        $idx = $start-pos ?? index $line, $brk, $start-pos !! index $line, $brk;
    }
    if $idx.defined {
        $line2 = substr $line, $idx+1;
        $line  = substr $line, 0, $idx+1;

        $line  .= trim-trailing;
        $line2 .= trim;
    }
    return $line2;

} # split-line-rw

sub get-kw-line-data(:$val, :$kw, :@words is copy) returns Str {
    say "TOM FIX THIS TO HANDLE EACH KEYWORD PROPERLY" if $debug;
    say "DEBUG: reduced \@words array" if $debug;
    say @words.perl if $debug;

    my $txt = '';
    given $kw {
        when 'Subroutine' {
            # pass back just the sub name with leading markup
            $txt ~= $val if $val;
            $txt ~= ' ' ~ @words[1];
            # add a leading newline to provide spacing between
            # the preceding subroutine
            $txt = "\n" ~ $txt;
        }
        when 'Purpose'    {
            # pass back all with leading markup
            $txt ~= $val if $val;
            $txt ~= ' ' ~ join ' ', @words;
        }
        when 'Params'     {
            # pass back all with leading markup
            $txt ~= $val if $val;
            $txt ~= ' ' ~ join ' ', @words;
            # need an extra space to prettify the total appearance
            $txt ~~ s/Params/Params /;
        }
        when 'Returns'    {
            # pass back all with leading markup
            $txt ~= $val if $val;
            $txt ~= ' ' ~ join ' ', @words;
        }
        when 'file:'      {
            # don't need anything special
        }
        when 'title:'     {
            # pass back all with leading markup
            $txt ~= $val if $val;
            $txt ~= ' ' ~ join ' ', @words[1..*];
        }
    }

    return $txt;
}

sub create-toc-md($fh, $title, @list is copy, $ncols, :@headings, :@just, :$add-link) {
    my $ne = @list.elems;
    my $nrows = $ne div $ncols;
    ++$nrows if $ne % $ncols; # check for partial columns

    $fh.say: "\n### $title\n";
    if @headings.elems {
        my $nh = @headings.elems;
        my $nj = @just.elems ?? @just.elems !! 0;

        die "FATAL: \$headings.elems ($nh) not equal to \$ncols ($ncols)" if $nh != $ncols;
        die "FATAL: \$just.elems ($nj) not equal to \$ncols ($ncols)" if $nj && $nj != $ncols;

        # need 2 loops
        # column headings
        for @headings -> $h {
            $fh.print: "| $h";
        }
        $fh.say: ' |';

        # the heading separator row
        for 0..^$ncols -> $i {
            my $b = '---';
            if $nj {
                given @just[$i] {
                    when /:i L/ { $b = ':' ~ $b }
                    when /:i C/ {               } # use the default
		    when /:i R/ { $b ~= ':'     }
                }
            }
            $fh.print: "| $b";
        }
        $fh.say: ' |';
    }
    # note that at the moment github markdown requires column headings 
    else {
        # need 2 loops
        # column headings
        for 1..$ncols -> $n {
            $fh.print: "| Col $n";
        }
        $fh.say: ' |';

        # the heading separator row
        for 0..^$ncols -> $i {
            my $b = '---';
            $fh.print: "| $b";
        }
        $fh.say: ' |';
    }

    # add the table content
    for 0..^$nrows {
        for 0..^$ncols {
            my $c = @list.elems ?? @list.shift !! '';
            if $c && $add-link {
                # add the link
                my $link = '#' ~ lc $c;
                $fh.print: "| [$c]($link)";
            }
            else {
                $fh.print: "| $c";
            }
        }
        $fh.say: ' |';
    }
}
