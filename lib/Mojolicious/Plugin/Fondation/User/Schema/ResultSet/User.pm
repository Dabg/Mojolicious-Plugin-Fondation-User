package Mojolicious::Plugin::Fondation::User::Schema::ResultSet::User;
# ABSTRACT: DBIx::Class ResultSet class for users table

use base 'DBIx::Class::ResultSet';

use strict;
use warnings;
use DateTime;

# Example of useful method: active users (if you add an 'active' field)
sub active {
    shift->search({ active => 1 });
}

# Example: users created today
sub created_today {
    my $self = shift;
    my $today = DateTime->today->strftime('%Y-%m-%d');
    return $self->search({
        created_at => { '>=' => $today, '<' => DateTime->today->add( days => 1 )->strftime('%Y-%m-%d') },
    });
}

# Example: search by email or username (case insensitive)
sub search_by_login {
    my ($self, $login) = @_;
    return $self->search([
        { username => { -like => "%$login%" } },
        { email    => { -like => "%$login%" } },
    ]);
}

# Example: latest registered user (sorted by created_at DESC)
sub latest {
    shift->search(undef, { order_by => { -desc => 'created_at' }, rows => 10 });
}

1;
