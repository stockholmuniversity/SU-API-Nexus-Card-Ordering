package SU::API::NexusCardOrdering;

use strict;
use warnings;

use HTTP::Request;
use JSON;
use LWP::UserAgent;
use URI::Escape;
use Date::Parse;

sub new
{
    my $class = shift;
    my $self = {
                user_id   => shift,
                layout_id => shift,
               };

    $self->{url}          = "https://cards-api.nexusgroup.com";
    $self->{ua}           = LWP::UserAgent->new;
    $self->{login_status} = "not logged in";

    bless $self, $class;
    return $self;
}

sub do_request
{
    my ($self, $method, $uri, $params, $data) = @_;

    my $now_inc_margin = time + 100;
    if (   ($now_inc_margin >= $self->{valid_until})
        && ($self->{valid_until} != 0))
    {
        warn
          "Token are about to expire(or has expired), need to fetch a fresh one.";
        my $token = $self->login($self->{username}, $self->{password});
        if (!$token)
        {
            warn "Couldn't fetch token, better exit here.";
            exit 1;
        }
    }

    my $request_url;
    $request_url = "$self->{url}/${uri}";

    if ($params)
    {
        $params      = encode_params($params);
        $request_url = "$self->{url}/${uri}?$params";
    }

    my $req;
    $req = HTTP::Request->new($method => $request_url);

    if ($data)
    {
        $data = to_json($data);
        $req->content($data);
    }
    $self->{res} = $self->{ua}->request($req);

    if (!$self->{res}->is_success)
    {
        return undef;
    }
    my $content;
    if ($self->{res}->code == 204)
    {
        $content = "{}";
    }
    else
    {
        $content = $self->{res}->content;
    }
    my $json_result = decode_json($content);

    if ($json_result)
    {
        return $json_result;
    }
    return undef;
}

sub encode_params
{
    my $filter = $_[0];
    my @filter_array;
    my @encoded_uri_array;

    if ($filter =~ /&/)
    {
        @filter_array = split('&', $filter);
    }
    else
    {
        @filter_array = $filter;
    }
    for (@filter_array)
    {
        if ($_ =~ /=/)
        {
            my ($argument, $value) = split("=", $_);
            push(@encoded_uri_array,
                 join("=", uri_escape($argument), uri_escape($value)));
        }
        else
        {
            push(@encoded_uri_array, uri_escape($_));
        }
    }
    return join("&", @encoded_uri_array);
}

sub login
{
    my ($self, $username, $password) = @_;

    $self->{ua}->default_header('Content-Type' => "application/json");
    $self->{username}    = $username;
    $self->{password}    = $password;
    $self->{valid_until} = 0;

    my $data = {"username" => $username, "password" => $password};

    my $response = $self->do_request("POST", "login", "", $data);

    if ($self->request_code == 201)
    {
        $self->{login_status} = "login successful";
        $self->{token}        = $response->{token};
        $self->{valid_until}  = str2time($response->{validUntil});
        $self->{ua}->default_header('Content-Type' => "application/json",
                                    'X-Auth-Token' => "Bearer $self->{token}");
    }
    else
    {
        $self->{login_status} =
          "unknown status line: " . $self->{res}->status_line;
        return undef;
    }
    return $self->{token};
}

sub logout
{
    my ($self) = @_;
    $self->{access_token} = undef;
}

sub request_code
{
    my ($self) = @_;
    return $self->{res}->code;
}

sub request_status_line
{
    my ($self) = @_;
    return $self->{res}->status_line;
}

sub logged_in
{
    my ($self) = @_;
    return $self->{access_token};
}

sub login_status
{
    my ($self) = @_;
    return $self->{login_status};
}

sub DESTROY
{
    my ($self) = @_;
    if ($self->{ua} && $self->{access_token})
    {
        $self->logout();
    }
    elsif ($self->{access_token})
    {
        warn "Automatic logout failed";
    }
}

1;
