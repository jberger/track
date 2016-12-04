package Track;

use Mojo::Base 'Mojolicious';

use Mojo::JSON;
use Mojo::Pg;

sub startup {
  my $app = shift;

  $app->plugin(Config => {
    defaults => {
      pg => 'postgresql://user:pass@/track',
      google_api_key => 'your-google-api-key',
    },
  });

  $app->plugin('ACME');
  $app->plugin('Bcrypt');
  $app->plugin('Multiplex');
  $app->plugin('Track::Plugin::Model');

  $app->helper(pg => sub {
    my $c = shift;
    state $pg = Mojo::Pg->new($c->config->{pg});
    my $file = $c->app->home->rel_file('track.sql');
    $pg->migrations->name('track')->from_file($file);
    return $pg;
  });

  $app->helper(migrate => sub {
    my $m = shift->pg->migrations;
    $m->name('track')->from_file('track.sql');
    $m->migrate(@_ ? shift : ());
  });

  $app->helper(depends => sub {
    my ($c, $template) = @_;
    return if $c->stash->{'track.depends'}{$template}++;
    return $c->include($template);
  });

  $app->helper(add_user => sub {
    my ($c, $full, $user, $pass) = @_;
    my $enc = $c->bcrypt($pass);
    $c->pg->db->query(<<'    SQL', $full, $user, $enc)->hash->{id};
      insert into users (name, username, password)
      values (?, ?, ?)
      returning id
    SQL
  });

  $app->helper(authenticate => sub {
    my ($c, $username, $password, $opts) = @_;
    return undef unless my $found = $c->model->user->get_password($username);
    return undef unless $c->bcrypt_validate($password, $found);
    return 1;
  });

  $app->helper(path => sub {
    my ($c, $user) = @_;
    my $sql = <<'    SQL';
      select json_agg(row_to_json(t)) as path
      from (
        select
          (data->>'lat')::numeric as lat,
          (data->>'lon')::numeric as lng
        from data
        where
          user_id=?
          and type='location'
        order by sent
      ) t;
    SQL
    return $c->pg->db->query($sql, $user->{id})->expand->hash->{path};
  });

  ## Routes

  my $r = $app->routes;
  $r->any([qw/GET POST/] => '/login' => sub {
    my $c = shift;
    my $username = $c->param('username');
    return $c->render('login') if $c->req->method eq 'GET' || !$username;
    return $c->render('login') unless $c->authenticate($username, $c->param('password'));
    $c->session(username => $username);
    $c->redirect_to('/');
  });

  # web

  my $web = $r->under(sub {
    my $c = shift;
    return 1 if $c->session('username');
    $c->redirect_to('login');
    return 0;
  });

  $web->get('/' => 'dashboard');
  $web->get('/map' => 'map');

  # api

  my $api = $r->under('/api' => sub {
    my $c = shift;
    my ($username, $valid);
    if ($c->session->{username}) {
      $username = $c->session->{username};
      $valid = 1;
    } else {
      my $url = $c->req->url->to_abs;
      $valid = $c->authenticate($url->username, $url->password);
      $username = $url->username if $valid;
    }
    my $user = $valid ? $c->model->user->get_one({username => $username}) : undef;

    unless ($user) {
      $c->render(json => {error => 'Not Authorized'}, status => 400);
      return 0;
    }

    delete $user->{password};
    $c->stash(user => $user);
    return 1;
  });

  $api->post('/' => sub {
    my $c = shift;
    my $user = $c->stash->{user};
    if (my $json = $c->req->json || {}) {
      $c->pg->db->query(<<'      SQL', $user->{id}, @{$json}{qw/_type tst/}, {json => $json});
        insert into data (user_id, type, sent, data)
        values (?, ?, to_timestamp(?), ?)
      SQL
      $user->{location} = $json;
      $c->pg->pubsub->notify("users.$user->{username}", Mojo::JSON::encode_json $user);
    }

    $c->render(json => []);
  });

  $api->get('/user' => sub {
    my $c = shift;
    my $user = $c->stash->{user};
    $c->render(json => $user);
  });

  $api->websocket('/multiplex')->to('WebSocket#socket')->name('multiplex');

}

1;

