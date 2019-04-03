package Serge::Sync::Plugin::TranslationService::command;
use parent Serge::Sync::Plugin::Base::TranslationService, Serge::Interface::SysCmdRunner;

use strict;

use Serge::Util qw(subst_macros);

sub name {
    return 'Universal command-based synchronization plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    # this flag will be set to undef by Command/sync.pm
    # when `--force` flag is passed down to `serge pull-ts` or `serge push-ts`
    $self->{optimizations} = 1;

    # TODO: support global `--dry-run` flag
    $self->{dry_run} = undef;

    $self->merge_schema({
        executable => 'STRING',
        force_pull_command => 'STRING',
        force_push_command => 'STRING',
        pull_command => 'STRING',
        push_command => 'STRING',
        lang_format => 'STRING',
        lang_separator => 'STRING',
    });

    # -------------------------------------------------
    # Pootle defaults:
    # -------------------------------------------------
    # # extra parameter: `project` (required)

    # executable => 'pootle' # or '/path/to/manage_py'
    # force_pull_command => '%EXECUTABLE% sync_stores --overwrite --project=%PROJECT% --skip-missing %LANGUAGES%'
    # force_push_command => '%EXECUTABLE% update_stores --force --project=%PROJECT% %LANGUAGES%'
    # pull_command => '%EXECUTABLE% sync_stores --project=%PROJECT% --skip-missing %LANGUAGES%'
    # push_command => '%EXECUTABLE% update_stores --project=%PROJECT% %LANGUAGES%'
    # lang_format => '--language=%LOCALE%'
    # lang_separator => ' '

    # -------------------------------------------------
    # Zing defaults:
    # -------------------------------------------------
    # # extra parameter: `project` (required)

    # executable => 'zing'
    # force_pull_command => '%EXECUTABLE% sync_stores --overwrite --project=%PROJECT% --skip-missing %LANGUAGES%'
    # force_push_command => '%EXECUTABLE% update_stores --force --project=%PROJECT% %LANGUAGES%'
    # pull_command => '%EXECUTABLE% sync_stores --project=%PROJECT% --skip-missing %LANGUAGES%'
    # push_command => '%EXECUTABLE% update_stores --project=%PROJECT% %LANGUAGES%'
    # lang_format => '--language=%LOCALE%'
    # lang_separator => ' '

    # -------------------------------------------------
    # Abstract SergeCAT defaults:
    # -------------------------------------------------
    # # extra parameter: `project` (required)

    # my $common_params = '--project=%PROJECT% %LANGUAGES%';

    # executable => 'serge-cat',
    # force_pull_command => "%EXECUTABLE% pull --force $common_params",
    # force_push_command => "%EXECUTABLE% push --force $common_params",
    # pull_command => "%EXECUTABLE% pull $common_params",
    # push_command => "%EXECUTABLE% push $common_params",

    # lang_format => '--language=%LOCALE%',
    # lang_separator => ' ',

    # -------------------------------------------------
    # Smartcat defaults:
    # -------------------------------------------------
    # my $common_params = '--token_id=%TOKEN_ID% '.
    #                     '--project_id=%PROJECT_ID% '.
    #                     '--workdir=%WORKDIR% '.
    #                     '--token=%TOKEN% '.
    #                     '--log=%LOGFILE% '.
    #                     '%LANGUAGES%'

    # executable => 'smartcat-cli'

    # pull_command => '%EXECUTABLE% pull '.
    #                 $common_params

    # push_command => '%EXECUTABLE% push '.
    #                 '--disassemble-algorithm-name="Serge.io PO" '.
    #                 $common_params

    # lang_format => '--language=%LOCALE%'
    # lang_separator => ' '
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    $self->{data}->{executable} = subst_macros($self->{data}->{executable});
    $self->{data}->{force_pull_command} = subst_macros($self->{data}->{force_pull_command});
    $self->{data}->{force_push_command} = subst_macros($self->{data}->{force_push_command});
    $self->{data}->{pull_command} = subst_macros($self->{data}->{pull_command});
    $self->{data}->{push_command} = subst_macros($self->{data}->{push_command});
    #$self->{data}->{lang_format} = "%LANG%" unless defined $self->{data}->{lang_format};
    #$self->{data}->{lang_separator} = "," unless defined $self->{data}->{lang_separator};

    die "'executable' not defined" if $self->{data}->{executable} eq '';
    die "'pull_command' not defined" if $self->{data}->{pull_command} eq '';
    die "'push_command' not defined" if $self->{data}->{push_command} eq '';
    #die "'lang_format' not defined" if $self->{data}->{lang_format} eq '';
    #die "'pull_command' doesn't have the %LANGUAGES% macro" unless $self->{data}->{pull_command} ~= m/%LANGUAGES%/;
    #die "'push_command' doesn't have the %LANGUAGES% macro" unless $self->{data}->{push_command} ~= m/%LANGUAGES%/;

    $self->{data}->{force_pull_command} = $self->{data}->{pull_command} unless defined $self->{data}->{force_pull_command};
    $self->{data}->{force_push_command} = $self->{data}->{push_command} unless defined $self->{data}->{force_push_command};
}

sub run_command {
    my ($self, $command, $langs) = @_;

    my @out_langs;
    if ($langs) {
        foreach my $lang (sort @$langs) {
            # format lang according to lang_format
            #FIXME: ???: push @out_langs, subst_macros($self->{data}->{lang_format}, $lang???);
        }
    }

    # format the command according to command_format
    my $params = $self->{data}->{params} || {};
    $params->{EXECUTABLE} = $self->{data}->{executable};
    $params->{LANGUAGES} = join($self->{data}->{lang_separator}, @out_langs);

    # TODO: pass extra params to subst_macros()
    #FIXME: ???: $command = subst_macros($command, $params???);

    if ($self->{dry_run}) {
        print "DRY_RUN: $command\n";
        return;
    }
    print "Running '$command'...\n";
    $self->run_cmd($command);
}

sub pull_ts {
    my ($self, $langs) = @_;

    $self->run_command($self->{data}->{pull_command}, $langs);
}

sub push_ts {
    my ($self, $langs) = @_;

    $self->run_command($self->{data}->{push_command}, $langs);
}

1;