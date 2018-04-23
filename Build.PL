use 5.010_001;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name              => 'Serge',
    license                  => 'perl',
    dist_author              => 'Igor Afanasyev <igor.afanasyev@gmail.com>',
    dist_version_from        => 'lib/Serge.pm',
    release_status           => 'stable',
    configure_requires       => {
        'Module::Build'      => 0,
    },
    build_requires           => {
        'File::Copy::Recursive' => 0,
        'IO::String'         => 0,
        'Test::More'         => '0.94',
        'Text::CSV_XS'       => 0,
        'Text::Diff'         => 0,
    },
    requires => {
        'perl'               => '5.10.0',
        'Authen::SASL'       => 0,
        'Config::Neat'       => '1.302',
        'DBD::SQLite'        => 0,
        'JSON'               => 0,
        'JSON::XS'           => 0,
        'MIME::Lite'         => 0,
        'Net::SMTP::SSL'     => 0,
        'XML::Parser'        => 0,
        'XML::Parser::Style::IxTree' => 0,
        'XML::Twig'          => 0,
        'YAML::XS'           => 0,
    },
    recommends => {
        'IO::String'         => 0,
        'Text::CSV_XS'       => 0,
    },
    add_to_cleanup           => ['Serge-*', 'Makefile.PL', 'MYMETA.*', 'META.*', 'MANIFEST.bak', 'MANIFEST'],
    create_makefile_pl       => 'traditional',
    doc_files => {
        # dependencies for generated HTML documentation
        'doc/html/media/favicon.ico'    => 'doc/html/media/favicon.ico',
        'doc/html/media/logo.svg'       => 'doc/html/media/logo.svg',
        'doc/html/media/pod.css'        => 'doc/html/media/pod.css',
        # documentation source files
        'doc/pod/serge-clean-ts.pod'    => 'doc/pod/serge-clean-ts.pod',
        'doc/pod/serge-gendocs.pod'     => 'doc/pod/serge-gendocs.pod',
        'doc/pod/serge-help.pod'        => 'doc/pod/serge-help.pod',
        'doc/pod/serge-import.pod'      => 'doc/pod/serge-import.pod',
        'doc/pod/serge-localize.pod'    => 'doc/pod/serge-localize.pod',
        'doc/pod/serge-pull-ts.pod'     => 'doc/pod/serge-pull-ts.pod',
        'doc/pod/serge-pull.pod'        => 'doc/pod/serge-pull.pod',
        'doc/pod/serge-push-ts.pod'     => 'doc/pod/serge-push-ts.pod',
        'doc/pod/serge-push.pod'        => 'doc/pod/serge-push.pod',
        'doc/pod/serge-sync.pod'        => 'doc/pod/serge-sync.pod',
        'doc/pod/serge-test-parser.pod' => 'doc/pod/serge-test-parser.pod',
        'doc/pod/serge.pod'             => 'doc/pod/serge.pod',
    },
);

if (not $builder->install_path('doc')) {
    if ($builder->install_base) {
        $builder->install_path(doc => $builder->install_base.'/doc');
    } elsif ($builder->installdirs eq 'site') {
        $builder->install_path(doc => '/usr/local/share/serge/doc');
    } elsif ($builder->installdirs eq 'vendor') {
        $builder->install_path(doc => '/usr/share/serge/doc');
    }
}

# copy lib/**/.serge and lib/**/.sql files to blib and the install directory
$builder->add_build_element('serge');
$builder->add_build_element('sql');

# process documentation files (see `doc_files` above)
$builder->add_build_element('doc');

$builder->create_build_script();
