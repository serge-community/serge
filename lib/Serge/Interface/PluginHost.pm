package Serge::Interface::PluginHost;

use strict;

sub load_plugin {
    my ($self, $class, $data) = @_;

    print "Loading plugin: $class\n" if $self->{debug};

    my $p;
    eval('use '.$class.'; $p = '.$class.'->new($self);');
    die "Can't create instance for plugin '$class': $@" if $@;
    print "Created plugin instance: '".$p->name."'\n" if $self->{debug};

    $p->{debug} = 1 if $self->{debug};

    $p->init($data);
    eval {
        $p->validate_data;
    };
    die "Data validation failed for plugin '$class': $@" if $@;

    return $p;
}

sub load_plugin_from_node {
    my ($self, $class_prefix, $node) = @_;
    die "'plugin' parameter missing" unless exists $node->{plugin};

    # if plugin name has '::', treat it as a full class name and don't expand it;
    # otherwise, prepend the provided class prefix to form a full class name

    # also allow for '::classname' syntax to indicate that no implicit prefix
    # should be added (and leading '::' will be removed)

    my $class = $node->{plugin};
    $class = $class_prefix.'::'.$class if ($class_prefix ne '' && $class !~ m/::/);

    # remove the leading '::'
    $class =~ s/^:://;

    return $self->load_plugin($class, $node->{data} || {});
}

1;