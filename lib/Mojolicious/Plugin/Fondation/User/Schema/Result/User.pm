package Mojolicious::Plugin::Fondation::User::Schema::Result::User;

# ABSTRACT: DBIx::Class Result class for users table

use strict;
use warnings;

use base 'DBIx::Class::Core';
use Crypt::Passphrase;

__PACKAGE__->load_components(qw/TimeStamp Core/);

# Password hashing — runs in the worker process before INSERT/UPDATE
my $PASSPHRASE = Crypt::Passphrase->new(
    encoder => {
        module  => 'Argon2',
        time    => 3,
        memory  => 64 * 1024,
        threads => 4,
    },
);

sub _hash_password {
    my ($password) = @_;
    return $PASSPHRASE->hash_password($password);
}

__PACKAGE__->table('users');

__PACKAGE__->add_columns(
    id => { data_type => 'integer', is_auto_increment => 1, is_nullable => 0 },
    # → readOnly + description auto via règles globales

    username => {
        data_type   => 'varchar',
        size        => 100,
        is_nullable => 0,
        extra       => {
            openapi => {   # ← optionnel, ici on surcharge juste un peu
                minLength   => 4,                    # au lieu de 3 global
                pattern     => '^[a-zA-Z0-9_-]{4,}$',
            }
        },
    },

    email => { data_type => 'varchar', size => 255, is_nullable => 0 },
    # → format: email + example auto

    password => { data_type => 'varchar', size => 255, is_nullable => 0 },
    # → writeOnly + minLength + format auto

    created_at => { data_type => 'datetime', is_nullable => 0, set_on_create => 1, set_on_update => 1  },
    # → readOnly auto

    updated_at => { data_type => 'datetime', is_nullable => 0, set_on_create => 1, set_on_update => 1 },
    # idem

    active => {
        data_type     => 'integer',
        default_value => 1,
        extra         => {
            openapi => {
                required => 0,   # ← explicitement pas required en API
            }
        },
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint([qw(username email)]);
__PACKAGE__->resultset_class('Mojolicious::Plugin::Fondation::User::Schema::ResultSet::User');

# Hash password automatically on create
sub insert {
    my $self = shift;
    if ($self->password && $self->is_column_changed('password')) {
        $self->password($self->_hash_password($self->password));
    }
    $self->next::method(@_);
}

# Hash password automatically on update (when password column is changed)
sub update {
    my $self = shift;
    my $upd = {@_};
    if (exists $upd->{password} && $upd->{password}) {
        $upd->{password} = $self->_hash_password($upd->{password});
    }
    $self->next::method($upd);
}

1;
