package Serge::DB;

use strict;

no warnings qw(uninitialized);

use DBI;
use Digest::MD5 qw(md5);
use Encode qw(encode_utf8);
use File::Basename;
use utf8;

our $DEBUG = $ENV{CI} ne ''; # use debug mode from under CI environment to ensure better coverage

my $DBD_PARAMS = {
    'SQLite' => {
        'options' => {
            'sqlite_unicode' => 1,
        },
        'do' => 'PRAGMA cache_size = 10000', # 10 MB of cache instead of default 2 MB
        'begin_transaction_stmt' => 'BEGIN',
    },

    'SQLite_pre_1_26_06' => {
        'options' => {
            'unicode' => 1, # old version of DBD::SQLite used 'unicode' instead of 'sqlite_unicode'
        },
        'do' => 'PRAGMA cache_size = 10000', # 10 MB of cache instead of default 2 MB
        'begin_transaction_stmt' => 'BEGIN',
    },

    'mysql' => {
        'options' => {
            'mysql_enable_utf8mb4' => 1,
            'mysql_bind_type_guessing' => 1,
        },
        'begin_transaction_stmt' => 'START TRANSACTION',
    },

    'Pg' => { # Postgres
        'options' => {
            'pg_enable_utf8' => 1,
        },
        'begin_transaction_stmt' => 'BEGIN',
    }
};

#
# Initialize object
#
sub new {
    my ($class) = @_;

    my $self = {
        dbh => undef,
        prepare_cache => {},
        transaction_opened => undef,
        dsn => {},
    };

    bless $self, $class;
    return $self;
}

sub open {
    my ($self, $source, $username, $password) = @_;

    $self->close if $self->{dbh}; # close previous connection

    if ($ENV{SERGE_NO_TRANSACTIONS}) {
        print "SERGE_NO_TRANSACTIONS is ON\n" if $DEBUG;
    }

    if ($source =~ m/^DBI:(.*?):/) {
        my $type = $1;
        my $schema_filename = dirname(__FILE__).'/'.lc($type).'_schema.sql';

        if ($type eq 'SQLite') {
            eval('use DBD::SQLite 1.26_06');
            $type = 'SQLite_pre_1_26_06' if $@;
        }

        # expand '~/' in file path to the value of $ENV{HOME}
        # See https://github.com/evernote/serge/issues/1
        $source =~ s!^(DBI:SQLite:dbname=)~/(.*)$!$1.$ENV{HOME}.'/'.$2!se;

        if (exists $DBD_PARAMS->{$type}) {
            $self->{params} = $DBD_PARAMS->{$type};

            $self->{dbh} = DBI->connect(
                $source, $username, $password,
                $self->{params}->{options}
            ) or die "Can't connect to the database [$source]: $!\n";

            # execute driver-specific statements, if any
            my $query = $self->{params}->{do};
            map $self->execute($_), split(';', $query) if ($query ne '');

            # test if 'files' table exists. If it's not,
            # consider this a new database and run schema SQL
            # to generate the initial structure
            if (scalar($self->{dbh}->tables('%', '%', 'files', 'TABLE')) == 0) {
                print "Initializing the database...\n";

                open(SQL, $schema_filename) or die "Can't open schema file $schema_filename: $!\n";
                my $sql = join('', <SQL>);
                close(SQL);

                # remove block comments
                $sql =~ s/\/\*.*?\*\///sg;

                # remove last ;
                $sql =~ s/;\s+$//s;

                # normalize line breaks
                $sql =~ s/\n{2,}/\n/sg;

                # execute each statement individually
                map $self->execute($_), split(';', $sql);
            }
        } else {
            die "Unknown database driver: '$type'\n";
        }
    } else {
        die "Incorrect data source format: '$source'\n";
    }

    return $self->{dbh};
}

sub begin_transaction {
    my ($self) = @_;
    my $sqlquery = $self->{params}->{begin_transaction_stmt};
    print "[DB] $sqlquery\n" if $DEBUG;
    $self->execute($sqlquery);
    $self->{transaction_opened} = undef;
}

sub commit_transaction {
    my ($self) = @_;
    return unless $self->{transaction_opened};
    my $sqlquery = 'COMMIT';
    print "[DB] $sqlquery\n" if $DEBUG;
    $self->execute($sqlquery);
    $self->{transaction_opened} = undef;
}

sub close {
    my ($self) = @_;
    if ($self->{dbh}) {
        $self->commit_transaction;
        $self->{dbh}->disconnect;
        $self->{dbh} = undef;
    }

    $self->{prepare_cache} = {};
}

sub execute {
    my ($self, $statement) = @_;

    $self->{dbh}->do($statement) || die "Can't execute statement [$statement]: $!\n";
}

sub get_usn {
    my ($self) = @_;
    # even if run from multiple clients, this will create a new row with a unique primary key (column: 'usn')
    $self->execute("INSERT INTO usn (dummy) VALUES (1)");
    my $usn = $self->{dbh}->last_insert_id(undef, undef, 'usn', 'usn');
    # we no longer need the inserted record
    $self->execute("DELETE FROM usn");
    return $usn;
}

sub get_highest_translation_usn_for_file_lang {
    my ($self, $file_id, $lang) = @_;

    $self->_check_file_id($file_id) if $DEBUG;

    my $sqlquery =
        "SELECT MAX(t.usn) AS n FROM translations t ".
        "JOIN items i ON i.id = t.item_id ".
        "JOIN files f ON f.id = i.file_id ".
        "WHERE f.id = ? ".
        "AND t.language = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $file_id) || die $sth->errstr;
    $sth->bind_param(2, $lang) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    die "file_id [$file_id] is invalid" unless $hr;
    return $hr->{n} + 0;
}

sub get_highest_item_usn_for_file {
    my ($self, $file_id) = @_;

    $self->_check_file_id($file_id) if $DEBUG;

    my $sqlquery =
        "SELECT MAX(i.usn) AS n FROM items i ".
        "JOIN files f ON f.id = i.file_id ".
        "WHERE f.id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $file_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    die "file_id [$file_id] is invalid" unless $hr;
    return $hr->{n} + 0;
}

sub get_highest_string_usn_for_file {
    my ($self, $file_id) = @_;

    $self->_check_file_id($file_id) if $DEBUG;

    my $sqlquery =
        "SELECT MAX(s.usn) AS n FROM items i ".
        "JOIN strings s ON s.id = i.string_id ".
        "JOIN files f ON f.id = i.file_id ".
        "WHERE f.id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $file_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    die "file_id [$file_id] is invalid" unless $hr;
    return $hr->{n} + 0;
}

sub get_highest_usn_for_file_lang {
    my ($self, $file_id, $lang) = @_;

    my $t_usn = $self->get_highest_translation_usn_for_file_lang($file_id, $lang);
    my $i_usn = $self->get_highest_item_usn_for_file($file_id);
    my $s_usn = $self->get_highest_string_usn_for_file($file_id);

    my $result = $t_usn;
    $result = $i_usn if $i_usn > $result;
    $result = $s_usn if $s_usn > $result;

    return $result;
}

sub prepare {
    my ($self, $sqlquery) = @_;

    my $key = md5($sqlquery);
    return $self->{prepare_cache}->{$key} if exists $self->{prepare_cache}->{$key};

    if (!$self->{transaction_opened} && !$ENV{SERGE_NO_TRANSACTIONS} && $sqlquery =~ m/^(INSERT|UPDATE|DELETE) /i) {
        $self->begin_transaction;
        print "Prepare query: [$sqlquery]\n" if $DEBUG;
        $self->{transaction_opened} = 1;
    }

    my $sth = $self->{dbh}->prepare($sqlquery) || die "Query: [$sqlquery], error: ".$self->{dbh}->errstr;
    $self->{prepare_cache}->{$key} = $sth;

    return $sth;
}

sub _check_file_id {
    my ($self, $file_id) = @_;

    # sanity check for provided file_id

    die "file_id is null" unless $file_id;

    my $sqlquery =
        "SELECT id ".
        "FROM files ".
        "WHERE id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $file_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    die "file_id [$file_id] is invalid" unless $hr;
}

sub _check_string_id {
    my ($self, $string_id) = @_;

    # sanity check for provided string_id

    die "string_id is null" unless $string_id;

    my $sqlquery =
        "SELECT id ".
        "FROM strings ".
        "WHERE id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $string_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    die "string_id [$string_id] is invalid" unless $hr;
}

sub _check_item_id {
    my ($self, $item_id) = @_;

    # sanity check for provided item_id

    die "item_id is null" unless $item_id;

    my $sqlquery =
        "SELECT id ".
        "FROM items ".
        "WHERE id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $item_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    die "item_id [$item_id] is invalid" unless $hr;
}

sub _check_translation_id {
    my ($self, $translation_id) = @_;

    # sanity check for provided item_id

    die "translation_id is null" unless $translation_id;

    my $sqlquery =
        "SELECT id ".
        "FROM translations ".
        "WHERE id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $translation_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    die "translation_id [$translation_id] is invalid" unless $hr;
}

sub _check_property_id {
    my ($self, $property_id) = @_;

    # sanity check for provided property_id

    die "property_id is null" unless $property_id;

    my $sqlquery =
        "SELECT id ".
        "FROM properties ".
        "WHERE id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $property_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    die "property_id [$property_id] is invalid" unless $hr;
}

sub get_string_id {
    my ($self, $string, $context, $nocreate) = @_;

    utf8::upgrade($string) if defined $string;
    $context = undef if ($context eq ''); # normalizing string
    utf8::upgrade($context) if defined $context; # to avoid converting undef to ''

    my $context_sql = $context ? 'AND context = ?' : 'AND context IS NULL';

    my $sqlquery =
        "SELECT id ".
        "FROM strings ".
        "WHERE string = ? ".
        "$context_sql";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $string) || die $sth->errstr;
    if ($context) {
        $sth->bind_param(2, $context) || die $sth->errstr;
    }
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    return $hr->{id} if $hr;

    return undef if $nocreate;

    # insert a new record and return its id

    return $self->_write_props('strings', undef, {
        string => $string,
        context => $context,
        skip => 0,
    }, 1); # insert mode

}

sub _write_props {
    my ($self, $table, $id, $props, $insert_mode) = @_;

    if ($DEBUG) {
        print "::DB::_write_props ($table, $id)\n";
        use Data::Dumper;
        print Dumper($props);
    }

    die "ERROR: _write_props: table is not defined\n" unless $table;
    die "ERROR: _write_props: id is not defined\n" unless $id or $insert_mode;

    my @insert_params_sql;
    my @insert_values_sql;
    my @update_params_sql;
    my @params;

    # for a certain set of tables, also update their usn field with each insert/update
    if ($table =~ m/^(files|items|strings|translations)$/) {
        $props->{usn} = $self->get_usn;
    }

    foreach my $key (keys %$props) {
        my $value = $props->{$key};
        if (defined $value) {
            if ($insert_mode) {
                push @insert_params_sql, $key;
                push @insert_values_sql, '?';
            } else {
                push @update_params_sql, "$key = ?";
            }

            utf8::upgrade($value);
            push @params, $value;
        } else {
            if ($insert_mode) {
                push @insert_params_sql, $key;
                push @insert_values_sql, 'NULL';
            } else {
                push @update_params_sql, "$key = NULL";
            }
        }
    }

    return if ((@insert_params_sql + @update_params_sql) == 0); # no props to insert/update

    my $sqlquery;
    if ($insert_mode) {
        my $insert_params_sql_str = join(', ', @insert_params_sql);
        my $insert_values_sql_str = join(', ', @insert_values_sql);
        $sqlquery =
            "INSERT INTO $table ".
            "($insert_params_sql_str) ".
            "VALUES ($insert_values_sql_str)";
    } else {
        my $update_params_sql_str = join(', ', @update_params_sql);
        $sqlquery =
            "UPDATE $table ".
            "SET $update_params_sql_str ".
            "WHERE id = ?";

        # the last parameter to bind is the row id (WHERE id = ?)
        push @params, $id;
    }

    if ($DEBUG) {
        print "==> $sqlquery" . ($id ? " [id: $id]" : '') . "\n" .
              "with params: ('" . join("','", @params) . "')\n";
    }

    my $sth = $self->prepare($sqlquery);

    # bind all params

    for (my $i = 0; $i <= $#params; $i++) {
        $sth->bind_param($i + 1, $params[$i]) || die $sth->errstr;
    }
    $sth->execute || die $sth->errstr;
    $sth->finish;
    $sth = undef;

    $id = $self->{dbh}->last_insert_id(undef, undef, $table, 'id') if $insert_mode;

    return $id;
}

sub _read_props {
    my ($self, $table, $id) = @_;

    my $sqlquery =
        "SELECT * ".
        "FROM $table ".
        "WHERE id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    return $hr;
}

sub update_string_props {
    my ($self, $string_id, $props) = @_;

    $self->_check_string_id($string_id) if $DEBUG;

    $self->_write_props('strings', $string_id, $props);
}

sub get_string_props {
    my ($self, $string_id) = @_;

    $self->_check_string_id($string_id) if $DEBUG;

    return $self->_read_props('strings', $string_id);
}

sub update_item_props {
    my ($self, $item_id, $props) = @_;

    $self->_check_item_id($item_id) if $DEBUG;

    $self->_write_props('items', $item_id, $props);
}

sub get_item_props {
    my ($self, $item_id) = @_;

    $self->_check_item_id($item_id) if $DEBUG;

    return $self->_read_props('items', $item_id);
}

sub update_file_props {
    my ($self, $file_id, $props) = @_;

    $self->_check_file_id($file_id) if $DEBUG;

    $self->_write_props('files', $file_id, $props);
}

sub get_file_props {
    my ($self, $file_id) = @_;

    $self->_check_file_id($file_id) if $DEBUG;

    return $self->_read_props('files', $file_id);
}

sub update_translation_props {
    my ($self, $translation_id, $props) = @_;

    $self->_check_translation_id($translation_id) if $DEBUG;

    $self->_write_props('translations', $translation_id, $props);
}

sub get_translation_props {
    my ($self, $translation_id) = @_;

    $self->_check_translation_id($translation_id) if $DEBUG;

    return $self->_read_props('translations', $translation_id);
}

sub update_property_props {
    my ($self, $property_id, $props) = @_;

    $self->_check_property_id($property_id) if $DEBUG;

    $self->_write_props('properties', $property_id, $props);
}

sub get_property_props {
    my ($self, $property_id) = @_;

    $self->_check_property_id($property_id) if $DEBUG;

    return $self->_read_props('properties', $property_id);
}

sub get_file_id {
    my ($self, $namespace, $job, $path, $nocreate) = @_;

    utf8::upgrade($namespace) if defined $namespace;
    utf8::upgrade($job) if defined $job;
    utf8::upgrade($path) if defined $path;

    my $sqlquery =
        "SELECT id ".
        "FROM files ".
        "WHERE namespace = ? AND path = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $namespace) || die $sth->errstr;
    $sth->bind_param(2, $path) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    return $hr->{id} if $hr;

    return undef if $nocreate;

    # insert a new record and return its id

    return $self->_write_props('files', undef, {
        job => $job,
        namespace => $namespace,
        path => $path,
    }, 1); # insert mode

}

sub get_item_id {
    my ($self, $file_id, $string_id, $hint, $nocreate) = @_;

    $self->_check_file_id($file_id) if $DEBUG;
    $self->_check_string_id($string_id) if $DEBUG;

    $hint = undef if $hint eq '';

    # getting item_id if the row exists

    my $sqlquery =
        "SELECT id ".
        "FROM items ".
        "WHERE file_id = ? AND string_id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $file_id) || die $sth->errstr;
    $sth->bind_param(2, $string_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    return $hr->{id} if $hr;

    return undef if $nocreate;

    # insert a new record and return its id

    return $self->_write_props('items', undef, {
        file_id => $file_id,
        string_id => $string_id,
        hint => $hint,
    }, 1); # insert mode

}

sub get_property_id {
    my ($self, $property, $value, $nocreate) = @_;

    # getting property_id if the row exists

    my $sqlquery =
        "SELECT id, value ".
        "FROM properties ".
        "WHERE property = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $property) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    return $hr->{id} if $hr;

    return undef if $nocreate;

    # insert a new record and return its id

    return $self->_write_props('properties', undef, {
        property => $property,
        value => $value,
    }, 1); # insert mode

}

sub get_property {
    my ($self, $property) = @_;

    my $property_id = $self->get_property_id($property, undef, 1); # do not create

    return unless $property_id;

    my $props = $self->get_property_props($property_id);
    return $props->{value};
}

sub set_property {
    my ($self, $property, $value) = @_;

    my $property_id = $self->get_property_id($property, $value); # create if necessary
    $self->update_property_props($property_id, {
        value => $value
    });
}

sub get_translation_id {
    my ($self, $item_id, $lang, $string, $fuzzy, $comment, $merge, $nocreate) = @_;

    $self->_check_item_id($item_id) if $DEBUG;

    $string = undef if $string eq '';
    $comment = undef if $comment eq '';
    $fuzzy = $fuzzy ? 1 : 0;
    $merge = $merge ? 1 : 0;

    # getting item_id if the row exists

    my $sqlquery =
        "SELECT id ".
        "FROM translations ".
        "WHERE item_id = ? AND language = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $item_id) || die $sth->errstr;
    $sth->bind_param(2, $lang) || die $sth->errstr;
    $sth->execute || die $sth->errstr;
    my $hr = $sth->fetchrow_hashref();
    $sth->finish;
    $sth = undef;
    return $hr->{id} if $hr;

    return undef if $nocreate;

    # insert a new record and return its id

    return $self->_write_props('translations', undef, {
        item_id => $item_id,
        language => $lang,
        string => $string,
        fuzzy => $fuzzy,
        comment => $comment,
        merge => $merge,
    }, 1); # insert mode

}

sub get_all_items_for_file {
    my ($self, $file_id) = @_;

    $self->_check_file_id($file_id) if $DEBUG;

    my $sqlquery =
        "SELECT id, orphaned ".
        "FROM items ".
        "WHERE file_id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $file_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;

    my %items;
    while (my $hr = $sth->fetchrow_hashref()) {
        $items{$hr->{id}} = $hr->{orphaned};
    }
    $sth->finish;
    $sth = undef;

    return \%items;
}

sub get_file_completeness_ratio {
    my ($self, $file_id, $lang, $total) = @_;

    $self->_check_file_id($file_id) if $DEBUG;

    if (!defined $total) {
        print "Total number of items wasn't passed, getting from DB\n" if $DEBUG;
        my $sqlquery =
            "SELECT COUNT(*) FROM items ".

            "JOIN strings ".
            "ON strings.id = items.string_id ".

            "WHERE items.orphaned = 0 ".
            "AND strings.skip = 0 ".
            "AND items.file_id = ?";
        my $sth = $self->prepare($sqlquery);
        $sth->bind_param(1, $file_id) || die $sth->errstr;
        $sth->execute || die $sth->errstr;

        my $row = $sth->fetchrow_arrayref();
        $total = $row->[0];
        $sth->finish;
        $sth = undef;
    }

    # empty files are 'fully translated'
    return 1 if $total == 0;

    my $sqlquery =
        "SELECT COUNT(*) FROM items ".

        "JOIN strings ".
        "ON strings.id = items.string_id ".

        "JOIN translations ".
        "ON translations.item_id = items.id ".
        "AND translations.language = ? ".
        "AND translations.fuzzy = 0 ".

        "WHERE items.orphaned = 0 ".
        "AND strings.skip = 0 ".
        "AND items.file_id = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $lang) || die $sth->errstr;
    $sth->bind_param(2, $file_id) || die $sth->errstr;
    $sth->execute || die $sth->errstr;

    my $row = $sth->fetchrow_arrayref();
    my $translated = $row->[0];
    $sth->finish;
    $sth = undef;

    return $translated / $total;
}

sub get_all_files_for_job {
    my ($self, $namespace, $job) = @_;

    my $sqlquery =
        "SELECT id, path, orphaned ".
        "FROM files ".
        "WHERE namespace = ? ".
        "AND job = ?";
    my $sth = $self->prepare($sqlquery);
    $sth->bind_param(1, $namespace) || die $sth->errstr;
    $sth->bind_param(2, $job) || die $sth->errstr;
    $sth->execute || die $sth->errstr;

    my %items;
    while (my $hr = $sth->fetchrow_hashref()) {
        $items{$hr->{path}} = {
            id => $hr->{id},
            orphaned => $hr->{orphaned}
        };
    }
    $sth->finish;
    $sth = undef;

    return \%items;
}

1;