package Serge::Engine::Plugin::segmenter;
use parent Serge::Plugin::Base::Callback;

use strict;

use Serge::Util qw(set_flag);

# See https://metacpan.org/source/CAPOEIRAB/Lingua-Sentence-1.100/share
# for the list of supproted language codes
my @lingua_sentence_languages = qw(ca cs da de el en es fi fr hu is it lt lv nl pl pt ro ru sk sl sv);
my $default_langauge = 'en';

sub name {
    return 'Break paragraphs into individually translated sentences.';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        split_single_breaks => 'BOOLEAN',
        split_regex         => 'STRING',
        split_sentences     => 'BOOLEAN',
    });

    $self->add({
        segment_source => \&segment_source
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    if ($self->{data}->{split_sentences}) {
        eval('use Lingua::Sentence;');
        die "ERROR: To use the segmenter plugin, please install Lingua::Sentence module (run 'cpan Lingua::Sentence')\n" if $@;

        my %supported;
        @supported{@lingua_sentence_languages} = @lingua_sentence_languages;

        my $source_lang = $self->{parent}->{source_language};
        if (!exists $supported{$source_lang}) {
            print "WARNING: Unsupported Lingua::Sentence language: $source_lang. Will use a default one ($default_langauge)\n";
            $source_lang = $default_langauge;
        }
        $self->{splitter} = Lingua::Sentence->new($source_lang);
    }

    my $re = $self->{data}->{split_regex};
    if ($re ne '') {
        $re = qr/($re)/; # compile regex
    } elsif ($self->{data}->{split_single_breaks}) {
        $re = qr/(\n+)/s;
    } else {
        $re = qr/(^\n|\n{2,}|\n$)/s;
    }
    $self->{split_re} = $re;
}

sub adjust_phases {
    my ($self, $phases) = @_;

    # always tie to 'segment_source' phase
    set_flag($phases, 'segment_source');
}

sub segment_source {
    my ($self, $phase, $source_string) = @_;

    # split into chunks by line breaks, including interleaved splitters, e.g.
    # <text> <split string> <text> <split string> <text> ...
    my @chunks = split($self->{split_re}, $source_string);

    my $is_splitter = undef;
    @chunks = map {
        my @out;
        if ($is_splitter) {
            @out = ($_); # return splitter as is
        } elsif ($_ =~ m/^\s+$/) {
            # for whitespace-only strings, return whitespace as is,
            # as otherwise the sentence-based segmenter
            # will return incorrect results
            @out = ($_);
        } else {
            # if we have an extra splitter, return the array
            if ($self->{data}->{split_sentences}) {
                my @sentences = map {
                    ($_, ' '); # return sentence and a splitter (single space)
                } $self->{splitter}->split_array($_);
                pop @sentences; # remove the trailing splitter space
                @out = @sentences; # return the list
            } else {
                @out = ($_); # return string as is
            }
        }
        $is_splitter = !$is_splitter;
        @out; # return (evaluate the block to this array)
    } @chunks;

    return @chunks;
}

1;