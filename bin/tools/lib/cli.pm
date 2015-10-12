package cli;

use strict;

use Getopt::Long qw(:config pass_through);
use Pod::Usage;

sub provide_help {
    my $man = 0;
    my $help = 0;
    GetOptions('help|?' => \$help, 'man' => \$man);

    # for --help option, show basic usage info and exit
    pod2usage(-verbose => 1, -exitstatus => 0) if $help;

    # for --man option, show the full POD documentation and exit
    pod2usage(-verbose => 2, -exitstatus => 0, -noperldoc => 1) if $man;
}

sub error {
  my ($message, $exitstatus) = @_;
  $exitstatus = 1 unless defined $exitstatus;
  # show message+synopsis and exit
  pod2usage(-message => $message."\n", -verbose => 0, -exitstatus => $exitstatus);
}

provide_help;

1;