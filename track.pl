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

helper pg => sub { state $pg = Mojo::Pg->new(shift->config->{pg}) };

helper migrate => sub { shift->pg->migrations->from_data->migrate(@_ ? shift : ()) };

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
  return undef unless $c->bcrypt_validate($password, $user->{password});
  return $user;
};

any [qw/GET POST/] => '/login' => sub {
  my $c = shift;
  my $username = $c->param('username');
  return $c->render('login') if $c->req->method eq 'GET' || !$username;
  return $c->render('login') unless my $user = $c->authenticate($username, $c->param('password'));
  $c->session(username => $username);
  $c->redirect_to('map');
};

# web
group {
  under sub {
    my $c = shift;
    return 1 if $c->session('username');
    $c->redirect_to('login');
    return 0;
  };

  get '/' => 'map';
};

# api

under '/api' => sub {
  return 1;
};

post '/' => sub {
  my $c = shift;
  my $url = $c->req->url->to_abs;
  return $c->render(json => {error => 'Not Authorized'}, status => 400)
    unless my $user = $c->authenticate($url->username, $url->password);
  if (my $json = $c->req->json || {}) {
    $c->pg->db->query(<<'    SQL', $user->{id}, @{$json}{qw/_type tst/}, {json => $json});
      insert into data (user_id, type, sent, data)
      values (?, ?, to_timestamp(?), ?)
    SQL
  }
  $c->render(json => []);
};


app->start;

__DATA__

@@ login.html.ep

% title 'Please log in';

<!DOCTYPE html>
<html>
  <head>
    <title><%= title %></title>
    %= stylesheet 'https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css'
  </head>
  <body>
    <div class="container">
      <h2><%= title %></h2>
      <form method="POST" action="/login">
        <div class="form-group">
          <label for="username">Email address</label>
          <input type="text" class="form-control" id="username" name="username" placeholder="Username">
        </div>
        <div class="form-group">
          <label for="password">Password</label>
          <input type="password" class="form-control" id="password" name="password" placeholder="Password">
        </div>
        <button type="submit" class="btn btn-default">Submit</button>
      </form>
    </div>
  </body>
</html>

@@ map.html.ep

<!DOCTYPE html>
<html>
  <head>
    <title>Simple Map</title>
    <meta name="viewport" content="initial-scale=1.0">
    <meta charset="utf-8">
    <style>
      html, body {
        height: 100%;
        margin: 0;
        padding: 0;
      }
      #map {
        height: 100%;
      }
    </style>
  </head>
  <body>
    <div id="map"></div>
    <script>
      var map;
      % my $user = get_user;
      var user = <%== Mojo::JSON::to_json $user %>;
      var loc = <%== Mojo::JSON::to_json get_user_location $user %>;
      var myLatLng = {lat: loc.lat, lng: loc.lon};
      var markers = [];

      function addMarker(pos, title) {
        if (!map) return;
        var marker = new google.maps.Marker({
          map: map,
          position: pos,
          label: title,
          'title': title,
        });
        markers.push(marker);
        return marker;
      }

      function fitBounds() {
        var bounds = new google.maps.LatLngBounds();
        _.each(markers, function(marker) {
          bounds.extend(marker.getPosition());
        });
        map.fitBounds(bounds);
      }

      function initMap() {
        map = new google.maps.Map(document.getElementById('map'), {});

        addMarker(myLatLng, loc.tid);
        fitBounds();
      }
    </script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.16.1/lodash.min.js"></script>
    <script src="https://maps.googleapis.com/maps/api/js?key=<%== $c->app->config->{google_api_key}  %>&callback=initMap"
    async defer></script>
  </body>
</html>

@@ migrations

-- 1 up

create table users (
  id bigserial primary key,
  username text not null unique,
  name text not null,
  password text not null,
  face bytea
);

create table data (
  id bigserial primary key,
  user_id bigint references users on delete cascade,
  received timestamp with time zone not null default current_timestamp,
  sent timestamp with time zone,
  type text not null,
  data jsonb
);

-- 1 down

drop table if exists users;
drop table if exists data;

