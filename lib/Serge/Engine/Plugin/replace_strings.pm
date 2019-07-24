package Serge::Engine::Plugin::replace_strings;
use parent Serge::Engine::Plugin::if;

use strict;

no warnings qw(uninitialized);

use Serge::Util qw(subst_macros_strref);

sub name {
    return 'Generic string replacement plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        replace => {'' => 'LIST',
            '*'        => 'ARRAY'
        },
        if => {
            '*' => {
                then => {
                    replace => {'' => 'LIST',
                        '*'        => 'ARRAY'
                    },
                },
            },
        },
    });

    $self->add({
        after_load_file => \&check,
        before_save_localized_file => \&check,
        rewrite_source => \&check,
        rewrite_translation => \&check,
        rewrite_path => \&rewrite_path,
        rewrite_relative_output_file_path => \&rewrite_path,
        rewrite_absolute_output_file_path => \&rewrite_path,
        rewrite_relative_ts_file_path => \&rewrite_path,
        rewrite_absolute_ts_file_path => \&rewrite_path
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    die "'replace' parameter is not specified and no 'if' blocks found" if !exists $self->{data}->{if} && !$self->{data}->{replace};

    if (exists $self->{data}->{if}) {
        foreach my $block (@{$self->{data}->{if}}) {
            die "'replace' parameter is not specified inside if/then block" if !$block->{then}->{replace};
        }
    }
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # this plugin makes sense only when applied to a single phase
    # (in addition to 'before_job' phase inherited from Serge::Engine::Plugin::if plugin)
    die "This plugin needs to be attached to only one phase at a time" unless @$phases == 2;
}

sub process_then_block {
    my ($self, $phase, $block, $file, $lang, $strref) = @_;

    #print "::process_then_block(), phase=[$phase], block=[$block], file=[$file], lang=[$lang], strref=[$strref]\n";

    my $rules = $block->{replace};
    foreach my $rule (@$rules) {
        my ($from, $to, $modifiers) = @$rule;

        my $output_lang = $lang;
        my $r = $self->{parent}->{output_lang_rewrite};
        $output_lang = $r->{$lang} if defined $r && exists($r->{$lang});

        subst_macros_strref(\$from, $file, $output_lang);
        subst_macros_strref(\$to, $file, $output_lang);

        my $eval_line = "\$\$strref =~ s/$from/$to/$modifiers;";
        eval($eval_line);
        die "eval() failed on: '$eval_line'\n$@" if $@;
    }

    return (shift @_)->SUPER::process_then_block(@_);
}

sub check {
    my $self = shift;
    return $self->SUPER::check(@_);
}

sub rewrite_path {
    my ($self, $phase, $path, $lang) = @_;
    $self->SUPER::check($phase, $path, $lang, \$path);
    return $path;
}

1;