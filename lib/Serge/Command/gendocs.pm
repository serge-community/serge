package Serge::Command::gendocs;
use parent Serge::Command;

use strict;

use File::Basename;
use File::Find qw(find);
use File::Spec::Functions qw(rel2abs abs2rel catfile splitdir);
use Serge::Pod;

sub get_commands {
    return {
        gendocs => {handler => \&run, info => 'Rebuild HTML from POD docs'},
    }
}

sub run {
    my ($self, $command) = @_;

    my $pod = Serge::Pod->new();

    my $pod_root = $pod->{pod_root};

    my @podfiles;

    print "Scanning .pod files in '$pod_root'...";
    find(sub {
        push @podfiles, catfile($File::Find::name) if (-f $_ && /\.pod$/);
    }, $pod_root);

    my $n = scalar(@podfiles);
    print " $n files found\n";

    foreach my $podfile (@podfiles) {
        my $command = abs2rel($podfile, $pod_root);
        $command =~ s/\.pod$//;

        my $htmlfile = $pod->save_html($command, $podfile);
        print "Saved $htmlfile\n";
    }

    return 0;
}

1;