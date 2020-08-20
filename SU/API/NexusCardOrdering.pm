package SU::API::NexusCardOrdering;

use strict;
use warnings;

use Date::Parse;
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use POSIX qw(strftime);
use URI::Escape;

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

    my $days_to_look_back = 7;
    my $time              = time();
    $self->{lookback} = strftime(
                                 "%Y-%m-%d",
                                 localtime(
                                     $time - (60 * 60 * 24 * $days_to_look_back)
                                 )
                                );

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

    my $content;
    if ($self->{res}->code == 204)
    {
        $content = "{}";
    }
    else
    {
        $content = $self->{res}->content;
    }
    my $json_result;
    eval {
        $json_result = decode_json($content);
    };

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

    my $code = $self->request_code;
    if ($code == 201)
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

sub _fetch_orderids
{

    my ($self) = @_;

    my $date = $self->{lookback};

    my $page  = 1;
    my $count = 0;
    my $foundCount;
    $self->{orders} = undef;

    while ()
    {
        my $response = $self->do_request("GET", "order/list",
                                         "createdDate=$date&page=$page");

        my $code = $self->request_code;
        if ($code == 404)
        {
            warn "No orders found from $date";
            $self->{orders} = {};
        }
        elsif ($code != 200)
        {
            die "unknown response code $code"
        }

        my $maxPage = $response->{maxPage};
        if (!$maxPage)
        {
            die "maxPage is missing";
        }
        my $orders = $response->{orders};
        if (!$orders)
        {
            die "order is missing";
        }

        for my $order (@$orders)
        {
            my $CustomersUniqueID = $order->{CustomersUniqueID};
            my $orderId           = $order->{orderId};
            if ($CustomersUniqueID && $orderId)
            {
                $self->{orders}->{$CustomersUniqueID}->{orderId} = $orderId;
            }
        }

        if ($maxPage == $page)
        {
            last;
        }
        $page++;
    }
    $self->{fetched_orderids} = 1;
}

sub get_orderid
{
    my ($self, $id) = @_;

    if (!$self->{fetched_orderids})
    {
        $self->_fetch_orderids();
    }
    my $orderId = $self->{orders}->{$id}->{orderId};
    return $orderId;
}

sub get_order
{
    my ($self, $id) = @_;

    my $response = $self->do_request("GET", "order/$id");

    my $code = $self->request_code;
    if ($code == 404)
    {
        warn "No orders not found";
        return undef;
    }
    elsif ($code != 200)
    {
        die "unknown response code $code"
    }
    return $response;
}

sub set_lookback
{
    my ($self, $date) = @_;

    $self->{lookback}         = $date;
    $self->{fetched_orderids} = undef;
    $self->{orders}           = {};
    return;
}

sub logout
{
    my ($self) = @_;
    $self->{token} = undef;
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
    return $self->{token};
}

sub login_status
{
    my ($self) = @_;
    return $self->{login_status};
}

sub DESTROY
{
    my ($self) = @_;
    if ($self->{ua} && $self->{token})
    {
        $self->logout();
    }
    elsif ($self->{token})
    {
        warn "Automatic logout failed";
    }
}

1;
