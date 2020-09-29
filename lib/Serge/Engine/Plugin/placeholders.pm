package Serge::Engine::Plugin::placeholders;
use parent Serge::Plugin::Base::Callback;

use strict;
use warnings;

use Serge::Util qw(is_flag_set set_flags);

our $LANG = 'test';
our $LANGID = 0xffff;

sub name {
    return 'Mark up and protect placeholders';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        matches => 'ARRAY',
    });

    $self->add({
        rewrite_source => \&rewrite_source,
        rewrite_translation => \&rewrite_translation,
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    die "`matches` parameter is not specified" unless exists $self->{data}->{matches};

    $self->{matches_regex} = join('|', @{$self->{data}->{matches}});
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # always tie to these phases
    set_flags($phases, 'rewrite_source', 'rewrite_translation');
}

sub subst_placeholder {
    my ($context, $text) = @_;
    my $key = $context->{text_to_key}->{$text};
    if (!defined $key) {
        $context->{counter}++;
        $key = "<".$context->{counter}.">";
        $context->{key_to_text}->{$key} = $text;
        $context->{text_to_key}->{$text} = $key;
        push @{$context->{sorted_keys}}, $key;
    }
    return $key;
}

sub rewrite_source {
    my ($self, $phase, $file, $lang, $strref, $hintref, $context) = @_;

    print "\t::rewrite_source before : $$strref\n" if $self->{parent}->{debug};

    $context = {} unless $context;
    my $ctx = $context->{placeholders} = {
        counter => 0,
        key_to_text => {},
        text_to_key => {},
        sorted_keys => []
    };

    my $regex = $self->{matches_regex};
    my $eval_line = "\$\$strref =~ s/($regex)/subst_placeholder(\$ctx, \$1)/sge;";
    eval($eval_line);
    die "eval() failed on: '$eval_line'\n$@" if $@;

    foreach my $key (@{$ctx->{sorted_keys}}) {
        my $text = $ctx->{key_to_text}->{$key};
        $$hintref .= "\n$key = $text";
    }

    print "\t::rewrite_source after  : $$strref\n" if $self->{parent}->{debug};
}

sub rewrite_translation {
    my ($self, $phase, $file, $lang, $strref, $context) = @_;

    return if !defined $context || !exists $context->{placeholders};

    print "\t::rewrite_translation before : $$strref\n" if $self->{parent}->{debug};

    my $r = $context->{placeholders}->{key_to_text};
    $$strref =~ s/(<\d+>)/$r->{$1}/sge;

    print "\t::rewrite_translation after  : $$strref\n" if $self->{parent}->{debug};
}

1;