package Track::Model::User;

use Mojo::Base -base;

use Mojo::JSON;

has pg => sub { die 'pg instance is required' };

sub get_one {
  my ($self, $opts) = @_;
  my (@args, @where);

  if ($opts->{user_id}) {
    push @args, $opts->{user_id};
    push @where, 'id=?';
  } elsif ($opts->{username}) {
    push @args, $opts->{username};
    push @where, 'username=?';
  }

  my $sql = <<'  SQL';
    select
      id,
      name,
      username,
      to_json(face is not null) as has_face,
      (
        select data
        from data
        where user_id = users.id
        order by sent desc
        limit 1
      ) as location
    from users
  SQL
  $sql .= ' where ' . join(' and ', @where) if @where;

  $self->pg->db->query($sql, @args)->expand->hash;
}

sub update_location {
  my ($self, $user, $location) = @_;

  my @args = ($user->{id}, @{$location}{qw/_type tst/}, {json => $location});
  my $success = !!$self->pg->db->query(<<'  SQL', @args)->rows;
    insert into data (user_id, type, sent, data)
    values (?, ?, to_timestamp(?), ?)
  SQL
  $user->{location} = $location;
  $self->pg->pubsub->notify("users.$user->{username}", Mojo::JSON::encode_json $user);
  return $success;
}

sub get_password {
  my ($self, $username) = @_;
  my $sql = 'select password from users where username=?';
  my $res = $self->pg->db->query($sql, $username)->hash || {};
  return $res->{password};
}

sub get_path {
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
}


1;

