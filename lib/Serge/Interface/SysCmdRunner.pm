package Serge::Interface::SysCmdRunner;

use strict;

use Cwd;

sub strip_sensitive_info {
    my ($self, $command) = @_;
    $command =~ s/(\-\-password \").+?(\")/$1******$2/;
    return $command;
}

sub run_cmd {
    my ($self, $command, $capture, $ignore_codes) = @_;

    if ($self->{echo_commands}) {
        my $line = $self->strip_sensitive_info($command);
        print "RUN: $line\n";
    }

    my $result;
    if ($capture) {
        $result = `$command`;
        print "\n--------------------\n$result\n--------------------\n" if $self->{echo_output};
    } else {
        system($command); # output will be echoed but not captured
    }
    my $error_code = unpack 'c', pack 'C', $? >> 8; # error code

    if (($error_code > 0) && $ignore_codes && (ref(\$ignore_codes) eq 'SCALAR' || (grep($_ eq $error_code, @$ignore_codes) > 0))) {
        print "Exit code: $error_code (ignored)\n" if $self->{debug};
        $error_code = 0;
    }

    die $result."\nExit code: $error_code; last error: $!\n" if $error_code != 0;

    return $result;
}

sub run_in {
    my ($self, $directory, $command, $capture, $ignore_codes) = @_;

    die "directory parameter shouldn't be empty" if $directory eq '';

    my $result;
    my $curdir = getcwd(); # preserve current directory
    if (chdir($directory)) {
        print "RUN IN: $directory\n" if $self->{echo_commands};
        eval {
            $result = $self->run_cmd($command, $capture, $ignore_codes);
        };
        chdir($curdir); # restore current directory
        die $@ if $@;
    } else {
        die "Failed to chdir to '$directory': $!";
    }
    return $result;
}

1;