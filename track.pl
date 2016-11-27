use Mojolicious::Lite;

use Mojo::Pg;

plugin Config => {
  defaults => {
    pg => 'postgresql://user:pass@/track',
    google_api_key => 'your-google-api-key',
  },
};

plugin 'ACME';
plugin 'Bcrypt';

helper pg => sub {
  my $c = shift;
  state $pg = Mojo::Pg->new($c->config->{pg});
  my $file = $c->app->home->rel_file('track.sql');
  $pg->migrations->name('track')->from_file($file);
  return $pg;
};

helper migrate => sub { shift->pg->migrations->migrate(@_ ? shift : ()) };

helper depends => sub {
  my ($c, $template) = @_;
  return if $c->stash->{'track.depends'}{$template}++;
  return $c->include($template);
};

helper add_user => sub {
  my ($c, $full, $user, $pass) = @_;
  my $enc = $c->bcrypt($pass);
  $c->pg->db->query(<<'  SQL', $full, $user, $enc)->hash->{id};
    insert into users (name, username, password)
    values (?, ?, ?)
    returning id
  SQL
};

helper get_user => sub {
  my $c = shift;
  my $opts = ref $_[-1] ? pop : {};
  return undef
    unless my $username = shift || $c->session('username');
  my $cols = 'id, name, username, password';
  $cols .= ', face' if $opts->{face};
  $c->pg->db->query("select $cols from users where username=?", $username)->hash;
};

helper get_user_location => sub {
  my $c = shift;
  return undef
    unless my $user = shift || $c->get_user;
  my $sql = <<'  SQL';
    select data
    from data
    where user_id=?
    order by sent desc
    limit 1
  SQL
  ($c->pg->db->query($sql, $user->{id})->expand->hash || {})->{data};
};

helper authenticate => sub {
  my ($c, $username, $password, $opts) = @_;
  return undef unless my $user = $c->get_user($username, $opts);
  return undef unless $user->{password};
  return undef unless $c->bcrypt_validate($password, $user->{password});
  return $user;
};

helper path => sub {
  my ($c, $user) = @_;
  my $sql = <<'  SQL';
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
};

my $r = app->routes;
$r->any([qw/GET POST/] => '/login' => sub {
  my $c = shift;
  my $username = $c->param('username');
  return $c->render('login') if $c->req->method eq 'GET' || !$username;
  return $c->render('login') unless my $user = $c->authenticate($username, $c->param('password'));
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

my $api = $r->under(
  '/api' => sub {
    my $c = shift;
    my $user;
    if (my $username = $c->session->{username}) {
      $user = $c->get_user($username);
    } else {
      my $url = $c->req->url->to_abs;
      $user = $c->authenticate($url->username, $url->password);
    }

    unless ($user) {
      $c->render(json => {error => 'Not Authorized'}, status => 400);
      return 0;
    }

    delete $user->{password};
    $c->stash(user => $user);
    return 1;
  }
);

$api->post('/' => sub {
  my $c = shift;
  my $user = $c->stash->{user};
  if (my $json = $c->req->json || {}) {
    $c->pg->db->query(<<'    SQL', $user->{id}, @{$json}{qw/_type tst/}, {json => $json});
      insert into data (user_id, type, sent, data)
      values (?, ?, to_timestamp(?), ?)
    SQL
  }
  $c->render(json => []);
});

$api->get('/user' => sub {
  my $c = shift;
  my $user = $c->stash->{user};
  $user->{location} = $c->get_user_location($user);
  $c->render(json => $user);
});

app->start;

