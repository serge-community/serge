package Serge::Engine::Plugin::parse_rc;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'Windows .RC parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text;

    # Finding translatable strings in file

    my $menu;
    my $dialog;
    my $stringtable;
    my $blocklevel = 0;
    my $idstr;

    foreach my $line (split(/\n/, $$textref)) {
        my $norm_line = $line;

        my $hint;
        my $orig_str;
        my $translated_str;

        # normalize line

        $norm_line =~ s/^[\t ]+//g;
        $norm_line =~ s/[\t ]+$//g;
        $norm_line =~ s/[\t ]+/ /g;
        $norm_line =~ s/^(.*?)\/\/.*$/$1/g; # get rid of comments

        $menu = 1 if ($norm_line =~ m/ MENU$/);
        $dialog = 1 if ($norm_line =~ m/^\w+ (DIALOG|DIALOGEX) /);
        $stringtable = 1 if ($norm_line eq 'STRINGTABLE');
        $blocklevel++ if ($norm_line eq 'BEGIN');
        if ($norm_line eq 'END') {
            $blocklevel--;
            if ($blocklevel == 0) {
                $menu = undef;
                $dialog = undef;
                $stringtable = undef;
            }
        }

        print "$line\n" if $self->{parent}->{debug};
        print "[m=$menu,d=$dialog,s=$stringtable,b=$blocklevel]\n" if $self->{parent}->{debug};
        print "[$norm_line]\n" if $self->{parent}->{debug};

        # DIALOG header contents
        if ($dialog && !$blocklevel) {

            if ($line =~ m/^[\t ]*(CAPTION)[\t ]+"((.*?("")*)*?)"/) {
                $hint = $1;
                $orig_str = $2;
            }

        # MENU and DIALOGEX BEGIN...END block contents
        } elsif (($menu || $dialog) && $blocklevel) {
            if ($line =~ m/^[\t ]*(\w+)[\t ]+"((.*?("")*)*?)"(,[\t ]*(\w+)){0,1}/) {
                $hint = $6 ? "$1 $6" : $1;
                $orig_str = $2;
            }

        # STRINGTABLE BEGIN...END block contents
        } elsif ($stringtable && $blocklevel) {
            if ($line =~ m/^[\t ]*(\w+)[\t ]+"((.*?("")*)*?)"/) { # test for one-line string definitions
                $hint = $1;
                $orig_str = $2;
            } elsif ($line =~ m/^[\t ]*(\w+)[\t ]*(\/\/.*)*$/) { # test for the first line (id) of the two-line string definitions
                $idstr = $1;
            } elsif ($idstr && ($line =~ /^[\t ]*"((.*?("")*)*?)"/)) { # test for the second line (string) of the two-line string definitions
                $hint = $idstr;
                $orig_str = $1;
            } else {
                $idstr = undef;
            }
        }

        if ($orig_str) {
            my $str = $orig_str;
            $str =~ s/""/"/g;
            $translated_str = &$callbackref($str, undef, $hint, undef, $lang);
        }

        if ($lang) {
            $translated_str =~ s/"/""/g;
            $translated_str =~ s/\n/\\n/g;
            $line =~ s/\Q"$orig_str"\E/"$translated_str"/;
            $translated_text .= $line."\n";
        }
    }

    return $translated_text;
}

1;