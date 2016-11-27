package Track::Model::User;

use Mojo::Base -base;

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
      face is not null as has_face,
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

sub get_password {
  my ($self, $username) = @_;
  my $sql = 'select password from users where username=?';
  my $res = $self->pg->db->query($sql, $username)->hash || {};
  return $res->{password};
}

1;

