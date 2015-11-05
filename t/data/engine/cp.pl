# Helper platform-independent copy tool
# Usage: `perl cp.pl source_file destination_file`

use strict;
use File::Copy;

my ($src, $dst) = @ARGV;
die "Source file '$src' not found" unless -f $src;
copy($src, $dst) or die "Copy failed: $!";