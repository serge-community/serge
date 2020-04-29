package Serge::Plugin::Base::HTTP;

use strict;

use HTTP::Request;
use LWP::UserAgent;
use URI::Escape;

use Serge;

sub init {
    my $self = shift;

    $self->{ua} = LWP::UserAgent->new(
        agent => "Serge/$Serge::VERSION (https://serge.io)",
        cookie_jar => {},
    );
}

sub http_request {
    my ($self, $method, $url, $header, $content) = @_;

    my $request = HTTP::Request->new($method => $url, $header, $content);
    $request->header('Content-length' => length($content) || 0);

    my $response = $self->{ua}->request($request);
    my $content  = $response->decoded_content();
    my $code = $response->code();
    return ($code, $content);
}

sub http_get {
    my ($self, $url, $header) = @_;
    return $self->http_request('GET', $url, $header);
}

sub http_post {
    my ($self, $url, $header, $content) = @_;
    return $self->http_request('POST', $url, $header, $content);
}

# static method
sub make_url {
    my ($base_url, $params) = @_;
    my $query = escape_query_params($params);
    return ($query ne '') ? $base_url.'?'.$query : $base_url;
}

# static method
sub escape_query_params {
    my $h = shift;
    my @pairs;
    for my $key (sort keys %$h) {
        push @pairs, uri_escape($key)."=".uri_escape($h->{$key});
    }
    return join "&", @pairs;
}

1;