package Serge::Engine::Plugin::completeness;
use parent Serge::Plugin::Base::Callback;

use strict;
use Serge::Mail;
use Serge::Util qw(xml_escape_strref);

sub name {
    return 'Generate/update/delete files based on their translation completeness';
}

sub init {
    my $self = shift;

    $self->{allowed_files} = {};
    $self->{created_files} = {};
    $self->{deleted_files} = {};

    $self->SUPER::init(@_);

    $self->merge_schema({
        create_threshold   => 'STRING',
        update_threshold   => 'STRING',

        bypass_languages   => 'ARRAY',

        save_incomplete_to => 'STRING',

        can_delete         => 'BOOLEAN',

        email_from         => 'STRING',
        email_to           => 'ARRAY',
        email_subject      => 'STRING',
    });

    $self->add({
        can_generate_localized_file => \&can_generate_localized_file,
        after_save_localized_file => \&after_save_localized_file,
        after_job => \&report_new_files,
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    # By default, if no parameters are provided, 'create_threshold' is set to 1,
    # 'update_threshold' is set to 0, and 'can_delete' is undefined.
    # This means that a file will never be created unless it is 100% complete;
    # once it has been created, it will always be updated no matter what its
    # current completeness ratio is (even if it drops to zero), and it will never
    # be deleted.
    #
    # If 'can_detete' is set to a true value, the file will be deleted if it
    # completeness ratio will be equal or less than update_threshold value

    my $create_threshold = $self->{data}->{create_threshold} = exists $self->{data}->{create_threshold} ? $self->{data}->{create_threshold} + 0 : 1;
    my $update_threshold = $self->{data}->{update_threshold} = exists $self->{data}->{update_threshold} ? $self->{data}->{update_threshold} + 0 : 0;

    die "ERROR: create_threshold must be in [0..1] range" if $create_threshold < 0 or $create_threshold > 1;
    die "ERROR: update_threshold must be in [0..1] range" if $update_threshold < 0 or $update_threshold > 1;
    die "ERROR: update_threshold must be less or equal to create_threshold" if $update_threshold > $create_threshold;

    print "WARNING: data->email_from not defined. Will skip sending any reports.\n" unless $self->{data}->{email_from};
    print "WARNING: data->email_to not defined. Will skip sending any reports.\n" unless $self->{data}->{email_to};

    $self->{bypass_languages} = {};
    if (defined $self->{data}->{bypass_languages}) {
        map {
            $self->{bypass_languages}->{$_} = 1;
        } @{$self->{data}->{bypass_languages}};
    }
}

# public static method
sub make_key {
    my ($file, $lang) = @_;
    return $lang."\001".$file;
}

sub can_generate_localized_file {
    my ($self, $phase, $file, $lang, $strref) = @_;

    # skip checks and allow file generation if the language
    # is in `bypass_languages` list
    return 1 if exists $self->{bypass_languages}->{$lang};

    my $file_id = $self->{parent}->{engine}->{db}->get_file_id($self->{parent}->{db_namespace}, $self->{parent}->{id}, $file, 1); # 1=no_create

    # sanity check: if the file is unknown, do not create it
    if (!$file_id) {
        print "WARNING: file is not registered in the database\n";
        return 0;
    }

    my $fullpath = $self->{parent}->{engine}->get_full_output_path($file, $lang); # get for the default output dir

    my $can_generate = $self->_check_can_generate($file_id, $fullpath, $file, $lang, $strref);
    return 1 if $can_generate;

    if ($self->{data}->{save_incomplete_to}) {
        # save the file information for rewriting purposes
        my $newpath = $self->{parent}->{engine}->get_full_output_path($file, $lang, $self->{data}->{save_incomplete_to});
        $self->{parent}->{engine}->set_full_output_path($file, $lang, $newpath); # set for the default output dir
        return 1; # can generate (under the new name)
    }

    return 0; # can't generate
}

sub _check_can_generate {
    my ($self, $file_id, $fullpath, $file, $lang, $strref) = @_;

    # source language is always 100% translated
    return 1 if $lang eq $self->{parent}->{source_language};

    my $create_threshold = $self->{data}->{create_threshold};
    my $update_threshold = $self->{data}->{update_threshold};
    my $can_delete = $self->{data}->{can_delete};

    my $total = $self->{parent}->{engine}->{ts_items_count}->{"$file_id:$lang"};

    if (-f $fullpath) {
        # file exists, check against delete_ratio and update_ratio

        # get the value from the database only if necessary
        my $ratio = $self->{parent}->{engine}->{db}->get_file_completeness_ratio($file_id, $lang, $total) if $can_delete or $update_threshold > 0;
        print "[completeness]::[_check_can_generate] existing file, file_id=$file_id, lang=$lang, total=$total, ratio=$ratio, can_delete=$can_delete, update_threshold=$update_threshold\n" if $self->{parent}->{debug};

        if ($can_delete and $ratio <= $update_threshold) {
            print "Deleting the file $fullpath as it's completeness ratio ($ratio) <= threshold ($update_threshold)\n";
            unlink $fullpath or print "WARNING: Failed to delete the file $fullpath: $!\n";
            $self->{deleted_files}->{$fullpath} = 1;
            return 0;
        }

        return $ratio >= $update_threshold ? 1 : 0;

    } else {
        # file doesn't exist, check against create_ratio

        # get the value from the database only if necessary
        my $ratio = $self->{parent}->{engine}->{db}->get_file_completeness_ratio($file_id, $lang, $total) if $create_threshold > 0;
        print "[completeness]::[_check_can_generate] new file, file_id=$file_id, lang=$lang, total=$total, ratio=$ratio, can_delete=$can_delete, create_threshold=$create_threshold\n" if $self->{parent}->{debug};

        if ($ratio >= $create_threshold) {
            # file is not created just yet, but is blessed for creation by this plugin,
            # so monitor if the file is actually created (at 'after_save_localized_file' phase),
            # and only then add it to the list of created ones
            $self->{allowed_files}->{make_key($file, $lang)} = $fullpath;
            return 1;
        } else {
            return 0;
        }
    }

}

sub after_save_localized_file {
    my ($self, $phase, $file, $lang) = @_;

    my $key = make_key($file, $lang);

    # check if this file was actually something allowed for generation by our plugin
    # and only then add its full path to the report
    if (exists $self->{allowed_files}->{$key}) {
        $self->{created_files}->{$self->{allowed_files}->{$key}} = 1;
    }
}

sub report_new_files {
    my ($self, $phase) = @_;

    if (!$self->{data}->{email_from} || !$self->{data}->{email_to}) {
        $self->{allowed_files} = {};
        $self->{created_files} = {};
        $self->{deleted_files} = {};
        return;
    }

    my $create_threshold = $self->{data}->{create_threshold};
    my $update_threshold = $self->{data}->{update_threshold};

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: ');

    my $created_text;
    foreach my $key (sort keys %{$self->{created_files}}) {
        xml_escape_strref(\$key);
        $created_text .= "<li style='color: green'>$key</li>\n";
    }
    if ($created_text) {
        $email_subject .= ' New files created';
        $created_text = qq|
<p>The following files were created as their completeness ratio reached $create_threshold:</p>

<ol>
$created_text
</ol>
|;
    }

    my $deleted_text;
    foreach my $key (sort keys %{$self->{deleted_files}}) {
        xml_escape_strref(\$key);
        $deleted_text .= "<li style='color: red'>$key</li>\n";
    }
    if ($deleted_text) {
        $email_subject .= ',' if ($created_text);
        $email_subject .= ' Stale files removed';
        $deleted_text = qq|
<p>The following files were removed as their completeness ratio dropped below $update_threshold:</p>

<ol>
$deleted_text
</ol>
|;
    }

    $self->{allowed_files} = {};
    $self->{created_files} = {};
    $self->{deleted_files} = {};

    if ($created_text or $deleted_text) {
        my $text = qq|
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
</head>
<body style="font-family: sans-serif; font-size: 120%">

<p># This is an automatically generated message.</p>

$created_text

$deleted_text

</body>
</html>
|;

        Serge::Mail::send_html_message(
            $self->{data}->{email_from}, # from
            $self->{data}->{email_to}, # to (list)
            $email_subject, # subject
            $text # message body
        );
    }

}

1;