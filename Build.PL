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
        'Test::More'         => '0.94',
        'File::Copy::Recursive' => 0,
    },
    requires => {
        'Authen::SASL'       => 0,
        'Config::Neat'       => '1.204',
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
    add_to_cleanup           => ['Serge-*', 'Makefile.PL', 'MYMETA.*', 'META.*', 'MANIFEST.bak', 'MANIFEST'],
    create_makefile_pl       => 'traditional',
);

$builder->create_build_script();
