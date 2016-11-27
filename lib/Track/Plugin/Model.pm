package Track::Plugin::Model;

use Mojo::Base 'Mojolicious::Plugin';

use Track::Model::User;

sub register {
  my ($plugin, $app, $conf) = @_;
  $app->helper('model.user' => sub { _build('Track::Model::User', @_) });
}

sub _build {
  my ($class, $c, @args) = @_;
  return $class->new(
    pg => $c->app->pg,
    @args == 1 ? %{$args[0]} : @args,
  );
}

1;

