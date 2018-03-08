package Serge::Engine::Plugin::parse_properties;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

# spec: http://java.sun.com/javase/6/docs/api/java/util/Properties.html#load(java.io.Reader)

sub name {
    return 'Java JDK .properties (resource bundle) parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        escaped_quotes => 'BOOLEAN',
    });
}

# TODO:
# - Support ``key = value'' pairs that span multiple lines
# - Better handling of comments

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text;
    my $skip;
    my $context_line;
    my %flags;

    # Finding translatable strings in file

    # Format is:
    #
    #     #.flag
    #     #.flag2=flag 2 value
    #     key = value
    #
    # Special flags are:
    #     `internal` (the string is skipped)
    #     `context` (sets the context for the string)
    #     `comment` (appends a line to the hint message)
    # All other flags are added as hashtags to the hint message

    # Make a copy of the string as we will change it

    my $source_text = $$textref;

    $source_text =~ s/\\\n//sg; # merge multi-line strings

    foreach my $line (split(/\n/, $source_text)) {

        my $hint;
        my $property_key;
        my $context;
        my $orig_str;
        my $translated_str;

        if ($line =~ m/^[\t ]*[\#\!]/) { # a comment line
            my $comment = $line;
            $comment =~ s/^\s+//s; # trim left
            $comment =~ s/\s+$//s; # trim right
            if ($comment =~ m/^#\.([^\s=:]+)([=:](.*))?$/) {
                my $param = $1;
                my $value = $3;
                $flags{$param} = [] unless exists $flags{$param};
                push @{$flags{$param}}, $value;
            }

            # check if there is a special comment line '#.context:string' which will
            # set the context for the next translatable line
            ($line =~ m/^[\t ]*[\#\!]\.context\:(.*?)[\t ]*$/) && ($context_line = $1);

        } else {
            if ($line =~ m/^[\t ]*(.*?[^\\])(?:[\t ]*[=:][\t ]*| )[\t ]*(.*)$/) { # a parameter line
                if (!exists $flags{internal}) {
                    $property_key = $hint = $1;
                    $hint =~ s/[\t ]+$//; # trim from the right
                    $orig_str = $2;

                    # convert value from the array to a string representation
                    # (or `undef` if all array items are undefined)
                    foreach my $key (keys %flags) {
                        my $value = undef;
                        map {
                            $value = 1 if defined $_;
                        } @{$flags{$key}};
                        if (defined $value) {
                            $value = join("\n", @{$flags{$key}});
                            # trim the value and remove blank lines
                            $value =~ s/^\s+//s;
                            $value =~ s/\s+$//s;
                            $value =~ s/\n{2,}$/\n/sg;
                        }
                        # save the value back
                        $flags{$key} = $value;
                    }

                    if (exists $flags{comment}) {
                        $hint .= "\n" if $hint ne '';
                        $hint .= $flags{comment};
                        delete $flags{comment};
                    }

                    if (exists $flags{context}) {
                        $context = $flags{context};
                        delete $flags{context};
                    }

                    # append flags as hashtags
                    my @tags;
                    foreach my $key (sort keys %flags) {
                        my $tag = '#'.$key;
                        $tag .= '='.$flags{$key} if defined $flags{$key};
                        push @tags, $tag;
                    }
                    if (scalar @tags > 0) {
                        $hint .= "\n" if $hint ne '';
                        $hint .= join(' ', @tags);
                    }
                }
            }
            $context_line = undef; # resetting the context line
            undef %flags; # reset the flags hash
        }

        if ($orig_str) {
            my $str = $orig_str;
            # decode \uXXXX
            $str =~ s/\\u([0-9A-Fa-f]{4})/chr(hex($1))/ge;
            $str =~ s/''/'/g; # unescape single quotes (always, disregarding the 'escaped_quotes' parameter)

            $translated_str = &$callbackref($str, $context, $hint, undef, $lang, $property_key);
        }

        if ($lang) {
            # Per prior research: turns out Java/JSP is inconsistent.
            # We can probably say that anything that has {#} will have ''
            # Others will have '
            my $need_escape = $self->{data}->{escaped_quotes} || ($orig_str =~ m/\{\d+\}/);
            if ($need_escape) {
                $translated_str =~ s/'/''/g; # escape single quotes
            }
            $translated_str =~ s/\n/\\n/g;
            $line =~ s/\Q$orig_str\E$/$translated_str/;
            $translated_text .= $line."\n";
        }
    }

    return $translated_text;
}

1;