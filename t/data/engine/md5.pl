# Helper platform-independent MD5 hash calculation tool
# Usage: `perl md5.pl <source_file`

use strict;
use Digest::MD5 qw(md5_hex);

print md5_hex(join('', <STDIN>));
