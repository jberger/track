package Track::Controller::WebSocket;

use Mojo::Base 'Mojolicious::Controller';

sub socket {
  my $c = shift;
  $c->inactivity_timeout(3600);

  my $multiplex = $c->multiplex;
  my $pubsub = $c->pg->pubsub;

  my %topics;

  $multiplex->on(subscribe => sub {
    my ($multiplex, $topic) = @_;
    return $multiplex->send_error($topic => 'Already subscribed') if $topics{$topic};
    my $cb = $pubsub->listen($topic => sub {
      my ($pubsub, $payload) = @_;
      $multiplex->send($topic, $payload);
    });
    $topics{$topic} = $cb;
    $multiplex->send_status($topic, 1);
  });

  $multiplex->on(message => sub {
    my ($multiplex, $topic, $payload) = @_;
    $pubsub->notify($topic, $payload);
  });

  $multiplex->on(unsubscribe => sub {
    my ($multiplex, $topic) = @_;
    return unless my $cb = delete $topics{$topic};
    $pubsub->unlisten($topic => $cb);
    $multiplex->send_status($topic, 0);
  });

  $multiplex->on(finish => sub {
    $pubsub->unlisten($_ => $topics{$_}) for keys %topics;
  });
}

1;

