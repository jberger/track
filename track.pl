use Mojolicious::Lite;

use Mojo::Pg;

plugin Config => {
  defaults => {
    pg => 'postgresql://user:pass@/track',
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

app->start;

__DATA__

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

