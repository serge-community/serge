package Serge::Engine::Plugin::if;
use parent Serge::Plugin::Base::Callback;

use strict;

use Serge::Util qw(set_flag);

# if multiple 'if' blocks are provided, at least one of them must match:
#   result = (block1 || block2 || block3 || ...)
# Note that 'if' block contains 'set_flag'/'remove_flag' directives,
# it will always be processed, even if the previous if block already
# evaluates to a 'true' value

# Within any 'if' block, all provided statements must match:
#   blockN = (statement1 && statement2 && statement3 && ...)

# Within a statement, multiple positive options (*_matches) are treated like this:
#   statementN = (option1 || option2 || option3 || ...)

# Within a statement, multiple negative options (*_doesnt_match) are treated like this:
#   statementN = !(option1 || option2 || option3 || ...)
# which is equivalent to:
#   statementN = (!option1 && !option2 && !option3 && ...)

sub name {
    return 'Generic "if" plugin that implements conditionals and flag checking/setting. See "process_if" for a plugin that uses this functionality';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        if => {''                    => 'LIST',

            '*' => {
                file_matches         => 'ARRAY',
                file_doesnt_match    => 'ARRAY',

                lang_matches         => 'ARRAY',
                lang_doesnt_match    => 'ARRAY',

                content_matches      => 'ARRAY',
                content_doesnt_match => 'ARRAY',

                comment_matches      => 'ARRAY',
                comment_doesnt_match => 'ARRAY',

                has_flag             => 'ARRAY',
                has_no_flag          => 'ARRAY',
                has_all_flags        => 'ARRAY',

                then => {
                    set_flag         => 'ARRAY',
                    remove_flag      => 'ARRAY',
                    return           => 'BOOLEAN',
                },
            },
        },
    });

    $self->add({
        before_job => \&before_job,
        after_load_file => \&check,
        after_load_source_file_for_processing => \&after_load_source_file_for_processing,
        before_save_localized_file => \&check,
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    if (exists $self->{data}->{if}) {
        foreach my $block (@{$self->{data}->{if}}) {
            die "'then' block is not specified" if !exists $block->{then};
        }
    }
}

sub adjust_phases {
    my ($self, $phases) = @_;

    # always tie to 'before_job' phase
    set_flag($phases, 'before_job');
}

sub before_job {
    my ($self) = @_;

    # clear flags for each job
    my $job = $self->{parent};
    $job->{plugin_data} = {} unless exists $job->{plugin_data};
    $job->{plugin_data}->{check_if} = {} unless exists $job->{plugin_data}->{check_if};
    $job->{plugin_data}->{check_if}->{flags} = {};
}

sub after_load_source_file_for_processing {
    my ($self, $phase, $file, $strref) = @_;

    $self->check($phase, $file, undef, $strref);
}

sub flags {
    my $self = shift;
    return $self->{parent}->{plugin_data}->{check_if}->{flags};
}

sub check {
    my ($self, $phase, $file, $lang, $strref, $commentref, @extra_params) = @_;

    if (!exists $self->{data}->{if}) {
        my $result = $self->process_then_block($phase, $self->{data}, $file, $lang, $strref, $commentref, @extra_params);
        return $result if defined $result; # return result if the block returns 1 or 0; continue if it returns undef
        return 1;
    }

    foreach my $block (@{$self->{data}->{if}}) {
        if ($self->check_block($phase, $block, $file, $lang, $strref, $commentref)) {
            my $result = $self->process_then_block($phase, $block->{then}, $file, $lang, $strref, $commentref, @extra_params);
            return $result if defined $result; # return result if the block returns 1 or 0; continue if it returns undef
        }
    }

    return 0;
}

sub check_block {
    my ($self, $phase, $block, $file, $lang, $strref, $commentref) = @_;

    if ($self->{parent}->{debug}) {
        print "[if]::check_block('$phase', '$file', '$lang', ".
              #(defined $strref ? '[content], ' : '-- no content --, ').
              #(defined $commentref ? '[comment]' : '-- no comment --').
              (defined $strref ? "'$$strref', " : '-- no content --, ').
              (defined $commentref ? "'$$commentref'" : '-- no comment --').
              ")\n";

        print "[if]::check_block; current flags for '$self->{parent}->{engine}->{current_file_rel}': ",
              join(', ', sort keys %{$self->flags->{$self->{parent}->{engine}->{current_file_rel}}}), "\n";
    }

    # Sanity checks. Some phases don't provide language, content or comment to match against

    die "'lang_matches' parameter is specified for a phase '$phase' that doesn't provide lang" if (exists $block->{lang_matches} && !defined $lang);
    die "'lang_doesnt_match' parameter is specified for a phase '$phase' that doesn't provide lang" if (exists $block->{lang_doesnt_match} && !defined $lang);

    die "'content_matches' parameter is specified for a phase '$phase' that doesn't provide content" if (exists $block->{content_matches} && !defined $strref);
    die "'content_doesnt_match' parameter is specified for a phase '$phase' that doesn't provide content" if (exists $block->{content_doesnt_match} && !defined $strref);

    die "'comment_matches' parameter is specified for a phase '$phase' that doesn't provide comment" if (exists $block->{comment_matches} && !defined $commentref);
    die "'comment_doesnt_match' parameter is specified for a phase '$phase' that doesn't provide comment" if (exists $block->{comment_doesnt_match} && !defined $commentref);

    return 0 unless $self->_check_statement($block->{file_matches},         1,     $file);
    return 0 unless $self->_check_statement($block->{file_doesnt_match},    undef, $file);

    return 0 unless $self->_check_statement($block->{lang_matches},         1,     $lang);
    return 0 unless $self->_check_statement($block->{lang_doesnt_match},    undef, $lang);

    return 0 unless $self->_check_statement($block->{content_matches},      1,     $$strref);
    return 0 unless $self->_check_statement($block->{content_doesnt_match}, undef, $$strref);

    return 0 unless $self->_check_statement($block->{comment_matches},      1,     $$commentref);
    return 0 unless $self->_check_statement($block->{comment_doesnt_match}, undef, $$commentref);

    return 0 unless $self->_check_flag($block->{has_flag},             1);
    return 0 unless $self->_check_flag($block->{has_no_flag},          undef);

    return 0 unless $self->_check_has_all_flags($block->{has_all_flags});

    return 1;
}

sub _check_statement {
    my ($self, $ruleset, $positive, $value) = @_;

    return 1 unless defined $ruleset;

    foreach my $rule (@$ruleset) {
        if ($value =~ m/$rule/s) {
            return $positive;
        }
    }
    return !$positive;
}

sub _check_flag {
    my ($self, $flagset, $positive) = @_;

    return 1 unless defined $flagset;
    my $f = $self->flags->{$self->{parent}->{engine}->{current_file_rel}} || {};

    foreach my $flag (@$flagset) {
        if (exists $f->{$flag}) {
            return $positive;
        }
    }
    return !$positive;
}

sub _check_has_all_flags {
    my ($self, $flagset) = @_;

    return 1 unless defined $flagset;

    my $f = $self->flags->{$self->{parent}->{engine}->{current_file_rel}} || {};

    foreach my $flag (@$flagset) {
        if (!exists $f->{$flag}) {
            return 0;
        }
    }
    return 1;
}

sub process_then_block {
    my ($self, $phase, $block, $file, $lang, $strref, $commentref) = @_;

    my $flags = $self->flags;

    # deal with flags only when set_flag/remove_flag directives are defined
    if (exists $block->{set_flag} || exists $block->{remove_flag}) {
        my $key = $self->{parent}->{engine}->{current_file_rel};
        $flags->{$key} = {} unless exists $flags->{$key};

        if (exists $block->{set_flag}) {
            foreach my $value (@{$block->{set_flag}}) {
                $flags->{$key}->{$value} = 1;
            }
        }

        if (exists $block->{remove_flag}) {
            foreach my $value (@{$block->{remove_flag}}) {
                delete $flags->{$key}->{$value};
            }
        }
    }

    if (exists $block->{return}) {
        return $block->{return} ? 1 : 0;
    }

    return undef;
}

1;