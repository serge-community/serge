package Serge::Engine::Job;
use parent Serge::Interface::PluginHost;

use strict;

no warnings qw(uninitialized);

use Data::Dumper;
use Serge::Util qw(subst_macros generate_hash is_flag_set);

#
# Initialize object
#
sub new {
    my ($class, $data, $engine, $base_dir) = @_;

    die "data not provided" unless $data;

    my $self = $data;
    bless $self, $class;

    # expand environment variables before calculating the job hash
    $self->expand_env_vars;

    # calculate hash before we add additional calculated fields and bless
    # the data
    my $dumper = Data::Dumper->new([$data]);
    $self->{hash} = generate_hash($dumper->Terse(1)->Deepcopy(1)->Indent(0)->Dump);

    # convert paths relative to the config path to absolute ones
    $self->expand_paths;

    $self->{engine} = $engine if $engine;
    $self->{base_dir} = $base_dir if $base_dir;

    $self->{debug} = $engine->{debug} if $engine;

    # Check job config validity

    die "job has an empty 'id' property" if $self->{id} eq '';
    die "job has an empty 'db_source' property" if $self->{db_source} eq '';
    die "job has an empty 'db_namespace' property" if $self->{db_namespace} eq '';

    if (!exists $self->{destination_languages} or scalar(@{$self->{destination_languages}}) == 0) {
        die "the list of destination languages is empty";
    }

    if (scalar @{$self->{destination_languages}} > 1) {
        if ($self->{ts_file_path} !~ m/%(LANG|LOCALE|CULTURE|LANGNAME|LANGID)(:\w+)*%/) {
            die "when there's more than one destination language, 'ts_file_path' should have %LANG%, %LOCALE%, %CULTURE%, %LANGNAME%, or %LANGID% macro defined";
        }

        if ($self->{output_lang_files} && ($self->{output_file_path} !~ m/%(LANG|LOCALE|CULTURE|LANGNAME|LANGID)(:\w+)*%/)) {
            die "when there's more than one destination language, 'output_file_path' should have %LANG%, %LOCALE%, %CULTURE%, %LANGNAME%, or %LANGID% macro defined";
        }
    }

    # load parser plugin

    $self->{parser_object} = $self->load_plugin_and_register_callbacks($self->{parser});

    my $plugin_name = $self->{parser}->{plugin};
    my $class = ref $self->{parser_object};
    $self->{plugin_version} = $plugin_name.'.'.eval('$'.$class.'::VERSION');

    # load serializer plugin

    # for backward compatibility, a missing `serializer` job config section
    # means 'use `serialize_po` plugin with default settings'
    my $plugin_name = 'serialize_po';
    if (exists $self->{serializer}) {
        $self->{serializer_object} = $self->load_plugin_and_register_callbacks($self->{serializer});
        $plugin_name = $self->{serializer}->{plugin};
    } else {
        $self->{serializer_object} = $self->load_plugin_and_register_callbacks({plugin => $plugin_name});
    }
    my $class = ref $self->{serializer_object};
    $self->{serializer_version} = $plugin_name.'.'.eval('$'.$class.'::VERSION');

    # load callback plugins

    map {
        $self->load_plugin_and_register_callbacks($_);
    } @{$self->{callback_plugins}};

    return $self;
}

sub expand_env_vars {
    my ($self) = @_;

    map {
        if (exists $self->{$_}) {
            $self->{$_} = subst_macros($self->{$_});
        }
    } qw(
        db_source db_username db_password db_namespace
        source_dir ts_file_path output_file_path source_ts_file_path
    );
}

sub expand_paths {
    my ($self) = @_;

    map {
        if (exists $self->{$_}) {
            $self->{$_} = $self->abspath($self->{$_});
        }
    } qw(source_dir ts_file_path output_file_path source_ts_file_path);
}

sub load_plugin_and_register_callbacks {
    my ($self, $node) = @_;

    my $plugin = $node->{plugin};

    my $p = $self->load_plugin_from_node('Serge::Engine::Plugin', $node);

    my @phases = $p->get_phases;

    # if specific phase was specified, limit to this specific phase
    if (exists $node->{phase}) {
        # check the validity of phase names
        my $used_phases = {};
        map {
            die "phase '$_' specified twice" if exists $used_phases->{$_};
            die "phase '$_' is not supported by '$node->{plugin}' plugin" unless is_flag_set(\@phases, $_);
            $used_phases->{$_} = 1;
        } @{$node->{phase}};

        @phases = @{$node->{phase}};
    }

    $p->adjust_phases(\@phases);

    foreach my $phase (@phases) {
        # Deprecation notice
        if ($phase eq 'before_update_database_from_ts_file') {
            print "WARNING: 'before_update_database_from_ts_file' phase name is deprecated; use 'before_update_database_from_ts_files' instead\n";
        }

        my $a = $self->{callback_phases}->{$phase};
        $self->{callback_phases}->{$phase} = $a = [] unless defined $a;
        push @$a, $p;
    }

    return $p;
}

sub has_callbacks {
    my ($self, $phase) = @_;
    return exists $self->{callback_phases}->{$phase};
}

sub run_callbacks {
    my ($self, $phase, @params) = @_;

    if ($self->has_callbacks($phase)) {
        print "::phase '$phase' has callbacks, running...\n" if $self->{debug};

        my @result;

        foreach my $p (@{$self->{callback_phases}->{$phase}}) {
            my @res = $p->callback($phase, @params);
            print "::plugin '".ref($p)."' returned [".join(',', @res)."]\n" if $self->{debug};
            push @result, @res;
        }
        return @result;
    } else {
        print "::phase '$phase' has no callbacks defined\n" if $self->{debug};
    }
    return; # return nothing
}

sub get_hash {
    my ($self) = @_;
    return $self->{hash};
}

sub abspath {
    my ($self, $path) = @_;

    return Serge::Util::abspath($self->{base_dir}, $path);
}

sub get_full_ts_file_path {
    my ($self, $file, $lang) = @_;

    my $ts_file_path = $self->{ts_file_path};

    if ($lang eq $self->{source_language} and exists $self->{source_ts_file_path}) {
        $ts_file_path = $self->{source_ts_file_path};
    }

    return subst_macros($ts_file_path, $file, $lang, $self->{source_language});
}

sub render_full_output_path {
    my ($self, $path, $file, $lang) = @_;

    # get the relative file path sans the source_path_prefix
    # note that this would be a virtual path that might have been changed
    # in rewrite_path callback
    my $prefix = $self->{source_path_prefix};
    $file =~ s/^\Q$prefix\E// if $prefix;

    my $r = $self->{output_lang_rewrite};
    $lang = $r->{$lang} if exists($r->{$lang});

    return subst_macros($path, $file, $lang, $self->{source_language});
}

sub gather_similar_languages_for_lang {
    my ($self, $lang) = @_;

    my %out;
    if (exists $self->{similar_languages}) {
        foreach my $rule (@{$self->{similar_languages}}) {
            if ($rule->{destination} eq $lang) {
                map { $out{$_} = 1 } @{$rule->{source}};
            }
        }
    }
    return keys %out;
}

1;