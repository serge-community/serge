package Serge::Engine::Plugin::mt_google;
use parent Serge::Engine::Plugin::Base::MT;
use parent Serge::Plugin::Base::HTTP;

use strict;
use warnings;

use JSON::XS qw(decode_json);

use Serge::Util qw(subst_macros);

sub name {
    return 'Google Cloud Translation provider';
}

sub init {
    my ($self) = @_;

    Serge::Engine::Plugin::Base::MT::init(@_);
    Serge::Plugin::Base::HTTP::init(@_);

    $self->merge_schema({
        api_key => 'STRING',
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    $self->{data}->{api_key} = subst_macros($self->{data}->{api_key});

    die "'api_key' not defined" if $self->{data}->{api_key} eq '';
}

sub mt_get_translation {
    my ($self, $src_lang, $target_lang, $s) = @_;

    my $url = Serge::Plugin::Base::HTTP::make_url(
        "https://translation.googleapis.com/language/translate/v2",
        {
            source => $src_lang,
            target => $target_lang,
            q      => $s,
            format => 'html',
            key    => $self->{data}->{api_key},
        }
    );

    my ($code, $content) = $self->http_post($url);

    if ($code != 200) {
        print "[mt_google] code: [$code]\n";
        print "[mt_google] content: [$content]\n";
        return undef;
    }

    my $response = decode_json($content);
    return $response->{data}->{translations}->[0]->{translatedText};
}

1;