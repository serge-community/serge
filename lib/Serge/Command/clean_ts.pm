package Serge::Command::clean_ts;
use parent Serge::Command;

use utf8;
no utf8;

use File::Basename;
use File::Find qw(finddepth);
use Getopt::Long;
use Serge::Config;
use Serge::Engine::Processor;
use Serge::ScanTSFiles;
use Serge::Util;

sub get_commands {
    return {
        'clean-ts' => {need_config => 1, handler => \&run, info => 'Delete orphaned translation files'},
    }
}

sub init {
    my ($self, $command) = @_;

    $self->SUPER::init($command);

    GetOptions(
        "ts-dir|ts-dirs=s"  => \$self->{ts_directories},
        "dry-run"    => \$self->{dry_run},
        "for-each:s" => \$self->{for_each},
    ) or die "Failed to parse some command-line parameters.";
}

sub validate_data {
    my ($self, $command) = @_;

    $self->SUPER::validate_data($command);

    if ($self->{for_each} and $self->{for_each} !~ m/\[PATH\]/) {
        die "--for-each parameter must include the '[PATH]' placeholder";
    }
}

sub run {
    my ($self, $command) = @_;

    print "*** DRY RUN ***\n" if $self->{dry_run};
    print "Run command: $for_each\n" if $self->{for_each};

    my @confs = $self->{parent}->get_config_files;

    my $scanner = Serge::ScanTSFiles->new();

    my %ts_directories;

    foreach (@confs) {
        my $config = $self->{parent}->get_config_object($_);
        $config->chdir;
        my $processor = Serge::Engine::Processor->new($scanner, $config);
        $processor->run();
    }

    if ($self->{ts_directories}) {
        my @dirs = split(/,/, $self->{ts_directories});
        map {
            my $path = $_;
            $path = abspath(normalize_path($path));
            $ts_directories{$path} = 1;
        } @dirs;
    } else {
        %ts_directories = %{$scanner->{ts_directories}};
    }

    if ($self->{ts_directories}) {
        print "\nUsing explicitly specified translation directories:\n";
    } else {
        print "\nFound translation directories:\n";
    }
    foreach (sort keys %ts_directories) {
        print "\t$_\n";
        if (!-d) {
            print "\t\tWARNING: Directory $_ doesn't exist\n";
        }
    }

    print "\nScanning translation files...";
    my @ts_files;

    my $wanted = sub {
        my $name = $File::Find::name;
        if ($^O !~ /MSWin32/) { # assume we are on Unix if not on Windows
            utf8::decode($name); # assume UTF8 filenames
        }
        push @ts_files, $name if (-f $_ && /\.po$/); # TODO: refactor; file extensions should not be hard-coded
    };

    foreach my $dir (sort keys %ts_directories) {
        finddepth({wanted => $wanted, follow => 1}, $dir);
    }
    $n = scalar(@ts_files);
    print " $n files found\n\n";
    print "Nothing to do.\n" and exit(1) unless $n;

    my $n = 0;
    foreach (@ts_files) {
        if (!exists $scanner->{known_files}->{$_}) {
            $n++;
            if ($self->{dry_run}) {
                print "\tORPHANED: $_\n";
            } else {
                unlink($_) or die "Failed to delete file $_: $!\n";
                print "\tDELETED: $_\n";

                if ($self->{for_each}) {
                    my $cmd = $self->{for_each};
                    $cmd =~ s/\[PATH\]/$_/g;
                    system($cmd);
                }

                my $dir = dirname($_);
                while (is_dir_empty($dir)) {
                    rmdir($dir) or die "Failed to remove empty directory $dir: $!\n";
                    print "\tDELETED: $dir\n";

                    if ($self->{for_each}) {
                        my $cmd = $self->{for_each};
                        $cmd =~ s/\[PATH\]/$dir/g;
                        system($cmd);
                    }

                    $dir = dirname($dir); # get parent
                }
            }
        }
    }

    if ($n > 0) {
        if ($self->{dry_run}) {
              print "$n orphaned translation files found.\n";
            } else {
              print "$n orphaned translation files were deleted.\n";
            }
    } else {
        print "No orphaned translation files were found.\n";
    }

    return 0;
}

sub is_dir_empty {
    my $dir = shift;

    opendir(my $h, $dir) or die "Failed to open directory $dir: $!\n";

    while (defined (my $entry = readdir($h))) {
        return undef unless $entry eq '.' or $entry eq '..';
    }
    return 1;
}

1;
