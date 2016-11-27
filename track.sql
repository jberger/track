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

