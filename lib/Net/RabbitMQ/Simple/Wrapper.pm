package Net::RabbitMQ::Simple::Wrapper;

use Moose;
use Net::RabbitMQ;
use Moose::Util::TypeConstraints;
use MooseX::Method::Signatures;
use Carp qw/ confess /;
use namespace::autoclean;

has conn => (
    is => 'rw', 
    isa => 'Object'
);

has hostname => (
    is => 'rw', 
    isa => 'Str', 
    default => 'localhost',
);

has user => (is => 'rw', isa => 'Str', default => 'guest');
has password => (is => 'rw', isa => 'Str', default => 'guest');
has vhost => (is => 'rw', isa => 'Str', default => '/');
has channel_max => (is => 'rw', isa => 'Int', default => 0);
has frame_max => (is => 'rw', isa =>  'Int', default => 131072);
has heartbeat => (is => 'rw', isa => 'Int', default => 0);

# validates from rabbitfoot
method _validate_vhost {
    Carp::confess("vhost has length > 255") if 255 < length($self->vhost)
        || $self->vhost !~ m{^[a-zA-Z0-9/\-_]+$};
}

method _check_shortstr ($arg) {
    Carp::confess($self->arg . "has length > 255") if 255 < length($self->$arg)
        || $self->$arg !~ m{^[a-zA-Z0-9-_.:]+$};
}

method _validate_routing_key {
    return if !$self->routing_key;
    Carp::confess('routing_key has length > 255') 
        if 255 < length($self->routing_key);
}

# connect 
method connect {
    my $mq = Net::RabbitMQ->new();
    $self->_validate_vhost;
    $mq->connect($self->hostname,
        {
        user => $self->user,
        password => $self->password,
        vhost => $self->vhost,
        channel_max => $self->channel_max,
        frame_max => $self->frame_max,
        hearbeat => $self->heartbeat
        });
    $self->conn($mq) ? 0 : 1;
}

# channel options
has channel => (is => 'rw', isa => 'Int', default => 1);

after channel => sub {
    my ($self, $argv) = @_;
    $self->conn->channel_open($argv) if $argv;
};

# exchange options
enum 'Exchange' => qw/direct topic fanout headers/;
has exchange_type => (is => 'rw', isa => 'Exchange', default => 'direct');
has exchange_name => (is => 'rw', isa => 'Str');

after exchange_name => sub {
    my ($self, $argv) = @_;
    $self->_check_shortstr('exchange_name') if $argv;
};

method exchange_declare (Str $exchange_name, %props) {
    $self->exchange_name($exchange_name);
    
    $props{type} = $self->exchange_type if !defined($props{type});
    $self->exchange_type($props{type});

    $self->conn->exchange_declare(
        $self->channel, $self->exchange_name, { %props } );
}

# queue
has 'queue_name' => (is => 'rw', isa => 'Str');
has 'routing_key' => (is => 'rw', isa => 'Str', default => '#');

after 'routing_key' => sub {
    my ($self, $argv) = shift;
    $self->_validate_routing_key if $argv;
};

method queue_declare (Str $queue_name = '', %props) {
    $self->queue_name($queue_name);
    $self->conn->queue_declare($self->channel, $queue_name, { %props });
}

method queue_bind (Str $routing_key = '#') {
    $routing_key ||= $self->routing_key;
    $self->routing_key($routing_key);
    $self->conn->queue_bind($self->channel, $self->queue_name,
        $self->exchange_name, $routing_key);
}

method queue_unbind (Str $routing_key = '#') {
    $self->conn->queue_unbind($self->channel, $self->queue_name,
                $self->exchange_name, $routing_key);
}

# publish
has 'body' => (is => 'rw', isa => 'Str');
has 'mandatory' => (is => 'rw', isa => 'Bool', default => 0);
has 'immediate' => (is => 'rw', isa => 'Bool', default => 0);

method publish ($body, %props) {
    
    $self->conn->publish($self->channel, $self->routing_key, $body,
        {
            exchange => $self->exchange_name,
            mandatory => $self->mandatory,
            immediate => $self->immediate,
        },
        {
            %props
        }
    );

}

# consume and get.
has 'consumer_tag' => (is => 'rw', isa => 'Str', default => 'absent');
has 'no_local' => (is => 'rw', isa => 'Bool', default => 0);
has 'no_ack' => (is => 'rw', isa => 'Bool', default => 1);
has 'exclusive' => (is => 'rw', isa => 'Bool', default => 0);

for my $item (qw/consume get/) {
    method "$item" (%props) {
        # for ack option
        $props{no_ack} = $self->no_ack if !defined($props{no_ack});
        # todo: check if the channel is open.
        $self->conn->$item($self->channel, $self->queue_name, { %props });
    }
}

method purge ($purge) {
    $self->conn->purge($self->channel, $purge);
}

method ack ($tag) {
    $self->conn->ack($self->channel, $tag);
}

method exchange_delete ($exchange, %props) {
#    $self->conn->exchange_delete($self->channel, $exchange, { %props });
}

method tx () {
    $self->conn->tx_select($self->channel);
}

method rollback() {
    $self->conn->tx_rollback($self->channel);
}

method commit() {
    $self->conn->tx_commit($self->channel);
}

for my $item (qw/recv disconnect/) {
    method "$item" () {
        $self->conn->$item();
    }
}


1;

