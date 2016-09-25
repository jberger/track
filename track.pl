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

helper migrate => sub { shift->pg->migrations->from_data->migrate };

helper add_user => sub {
  my ($c, $full, $user, $pass) = @_;
  my $enc = $c->bcrypt($pass);
  $c->pg->db->query(<<'  SQL', $full, $user, $enc)->hash->{id};
    insert into users (fullname, username, password)
    values (?, ?, ?)
    returning id
  SQL
};

helper get_user => sub {
  my ($c, $user) = @_;
  $c->pg->db->query('select * from users where username=?', $user)->hash;
};

post '/' => sub {
  my $c = shift;
  my $json = $c->req->json || {};
  if (my $tid = $json->{tid}) {
    $c->pg->db->query(<<'    SQL', $tid, $json->{tst}, $json);
      insert into data (tid, sent, data)
      values (?, ?, ?)
    SQL
  }
  $c->render(json => []);
};

get '/' => 'map';

app->start;

__DATA__

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
      var map, bounds;
      var myLatLng   = {lat: -25.363, lng: 131.044};
      var yourLatLng = {lat: -25.463, lng: 131.144};

      function addMarker(pos, title) {
        if (!map) return;
        var marker = new google.maps.Marker({
          map: map,
          position: pos,
          'title': title,
        });
        bounds.extend(pos);
        map.fitBounds(bounds);
      }

      function initMap() {
        map = new google.maps.Map(document.getElementById('map'), {});
        bounds = new google.maps.LatLngBounds();

        addMarker(myLatLng, 'Me');
        addMarker(yourLatLng, 'You');
      }
    </script>
    <script src="https://maps.googleapis.com/maps/api/js?key=<%== $c->app->config->{google_api_key}  %>&callback=initMap"
    async defer></script>
  </body>
</html>

@@ migrations

-- 1 up

create table users (
  id bigserial primary key,
  username text not null unique,
  fullname text not null,
  password text not null,
  tid text
);

create table data (
  id bigserial primary key,
  tid text not null,
  received timestamp with time zone not null default current_timestamp,
  sent timestamp with time zone not null,
  data jsonb
);

-- 1 down

drop table if exists users;
drop table if exists data;

