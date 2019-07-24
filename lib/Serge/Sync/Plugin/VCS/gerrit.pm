package Serge::Sync::Plugin::VCS::gerrit;
use parent Serge::Sync::Plugin::VCS::git;

use strict;

use Config::Neat::Schema;

sub name {
    return 'Gerrit sync plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        user => 'STRING'
    });
}

sub _update_message {
    my ($self, $message) = @_;

    # Gerrit requires a unique 'Change-Id: xxxxxxxxxxxxxxxxxxxxxxxx' line
    # to be appended to a commit message, otherwise it will reject the commit
    # Change-Id is a 40-char random hex string, prefixed with 'I'

    my $id = 'I';

    eval('use Crypt::Random qw(makerandom_octet); use Digest::MD5 qw(md5_hex);');
    if ($@) {
        # Crypt::Random not found, using built-in rand() function
        my @hexchars = (0..9, 'a'..'f');
        $id .= $hexchars[rand @hexchars] for 1..40;
    } else {
        $id .= md5_hex(makerandom_octet(Size => 256, Strength => 1)). # 32 chars
               substr(md5_hex(makerandom_octet(Size => 256, Strength => 1)), 0, 8); # 8 chars
    }

    return "$message\nChange-Id: $id";
}

sub _push {
    my ($self, $local_path, $remote_path, $message) = @_;

    ($remote_path, my $branch) = $self->split_remote_path_branch($remote_path);

    my $email = $self->{data}->{email};
    my $user = $self->{data}->{user};

    # these checks are not strictly needed after $self->{schema}->validate() call
    # and are left here temporarily
    die "User email not provided\n" unless $email;
    die "Username not provided\n" unless $user;

    # get remote server hostname/port

    my $url = $self->run_in($local_path, 'git config --get remote.origin.url 2>&1', 1); #1:capture

    my ($host, $port);
    if ($url =~ m|^ssh://((.*?)@)?(.+?)(:(\d+))?/|) {
        $host = $3;
        $port = $5;
    } else {
        die "Remote 'origin' not set for this repository or not recognized.\nURL: '$url'\n";
    }

    $port = 29418 unless $port;

    # push changes to Gerrit server, then self-verify and self-approve them

    print "Pushing changes to Gerrit into branch '$branch' as user '$user' to reviewer <$email>...\n";

    my $cmd = qq|git push $self->{data}->{push_params} --porcelain --quiet --receive-pack="git receive-pack --reviewer=$email" origin HEAD:refs/for/$branch 2>&1|;
    my $output = $self->run_in($local_path, $cmd, 1); #1:capture

    if ($output =~ m/\Q[remote rejected] (no new changes)\E/) {
        print "Nothing to push.\n";
        return;
    }

    my $ok;
    my @changes;

    while ($output =~ m|https://\S+/(\d+)|g) {
        push @changes, $1;
        $ok = 1;
    }

    if (!$ok) {
        die "Error: can't parse the server response:\n$output\n";
    }

    my $total = scalar(@changes);
    my $n = 0;
    foreach my $id (@changes) {
        $n++;
        print "Automatically reviewing change $id [$n of $total]...\n";

        my $cmd = qq|ssh -p $port $user\@$host "gerrit review --verified +1 --code-review +2 --submit $id,1" 2>&1|;
        my $output = $self->run_in($local_path, $cmd, 1); #1:capture

        if ($output) {
            print $output;
        }
    }
}

1;