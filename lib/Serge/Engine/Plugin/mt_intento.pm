package Serge::Engine::Plugin::mt_intento;
use parent Serge::Engine::Plugin::Base::MT;
use parent Serge::Plugin::Base::HTTP;

use strict;
use warnings;

use JSON::XS qw(decode_json encode_json);

use Serge::Util qw(subst_macros);

sub name {
    return 'Intento MT provider';
}

sub init {
    my ($self) = @_;

    Serge::Engine::Plugin::Base::MT::init(@_);
    Serge::Plugin::Base::HTTP::init(@_);

    $self->merge_schema({
        api_key          => 'STRING',
        provider         => 'STRING',
        provider_api_key => 'STRING',
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    map {
        $self->{data}->{$_} = subst_macros($self->{data}->{$_});
    } qw(api_key proivder provider_api_key);

    die "'api_key' not defined" if $self->{data}->{api_key} eq '';
}

sub mt_get_translation {
    my ($self, $src_lang, $target_lang, $s) = @_;

    my $url = "https://api.inten.to/ai/text/translate";

    my $header = [
        apikey => $self->{data}->{api_key}
    ];

    my $body = {
        context => {
            from => $src_lang,
            to   => $target_lang,
            text => $s
        }
    };

    my $provider = $self->{data}->{provider};
    if (defined $provider) {
        $body->{service} = {
            provider => $provider
        };

        if (defined $self->{data}->{provider_api_key}) {
            $body->{service}->{auth} = {
                $provider => [
                    {
                        key => $self->{data}->{provider_api_key}
                    }
                ]
            }
        }
    }

    my ($code, $content) = $self->http_post($url, $header, encode_json($body));

    if ($code != 200) {
        print "[mt_intento] code: [$code]\n";
        print "[mt_intento] content: [$content]\n";
        return undef;
    }

    my $response = decode_json($content);
    return $response->{results}->[0];
}

1;