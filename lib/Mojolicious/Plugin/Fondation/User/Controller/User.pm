package Mojolicious::Plugin::Fondation::User::Controller::User;

# ABSTRACT: REST controller for User CRUD via DBIx::Class::Async

use Mojo::Base 'Mojolicious::Plugin::Fondation::Controller::Base', -signatures;

# List all users (GET /api/User)
sub list ($self) {
    $self->render_later;
    $self->model('user')->search({})->all->on_done(sub {
        my $users = shift;
        my @data  = map { _to_data($_) } @$users;
        $self->render(openapi => \@data);
    })->on_fail(sub { $self->_render_error(shift) })->retain;
}

# Create a user (POST /api/User)
sub create ($self) {
    $self = $self->valid_input or return;
    $self->render_later;
    my $json = $self->req->json;
    $self->model('user')->create($json)->on_done(sub {
        my $user = shift;
        my $data = _to_data($user);
        $self->res->headers->location($self->url_for('read_user', id => $data->{id}));
        $self->render(status => 201, openapi => $data);

        $self->notify_user({
            type  => 'info',
            title => $self->l('User created'),
            body  => sprintf($self->l("User '%s' has been created."), $data->{username} // ''),
        });
    })->on_fail(sub { $self->_render_error(shift) })->retain;
}

# Read a user by ID (GET /api/User/:id)
sub read ($self) {
    $self = $self->valid_input or return;
    $self->render_later;
    my $id = $self->param('id');
    $self->model('user')->find($id)->on_done(sub {
        my $user = shift;
        if ($user) {
            $self->render(openapi => _to_data($user));
        }
        else {
            $self->render(status => 404, openapi =>
                { errors => [{ message => 'Not found', path => '/' }] });
        }
    })->on_fail(sub { $self->_render_error(shift) })->retain;
}

# Update a user (PUT /api/User/:id)
sub update ($self) {
    $self = $self->valid_input or return;
    $self->render_later;
    my $id        = $self->param('id');
    my $json      = $self->req->json;
    my $group_ids = delete $json->{groups};

    # Empty password means "don't change password"
    delete $json->{password} if defined $json->{password} && $json->{password} !~ /\S/;

    $self->model('user')->find($id)->on_done(sub {
        my $user = shift;
        unless ($user) {
            $self->render(status => 404, openapi =>
                { errors => [{ message => 'Not found', path => '/' }] });
            return;
        }
        $user->update($json)->on_done(sub {
            my $updated = shift;
            my $data    = _to_data($updated);
            $self->render(openapi => $data);

            # TODO: sync user-group associations once a groups table exists
            # $self->_sync_user_groups($id, $group_ids)
            #     if $group_ids;

            $self->notify_user({
                type  => 'info',
                title => $self->l('User updated'),
                body  => sprintf($self->l("User '%s' has been updated."), $data->{username} // ''),
            });
        })->on_fail(sub { $self->_render_error(shift) })->retain;
    })->on_fail(sub { $self->_render_error(shift) })->retain;
}

# Delete a user (DELETE /api/User/:id)
sub delete ($self) {
    $self = $self->valid_input or return;
    $self->render_later;
    my $id = $self->param('id');
    $self->model('user')->find($id)->on_done(sub {
        my $user = shift;
        unless ($user) {
            $self->render(status => 404, openapi =>
                { errors => [{ message => 'Not found', path => '/' }] });
            return;
        }
        my $username = $user->username;
        $user->delete->on_done(sub {
            $self->notify_user({
                type  => 'warning',
                title => $self->l('User deleted'),
                body  => sprintf($self->l("User '%s' has been deleted."), $username // ''),
            });
            $self->render(status => 204, openapi => {});
        })->on_fail(sub { $self->_render_error(shift) })->retain;
    })->on_fail(sub { $self->_render_error(shift) })->retain;
}

# ────────────────────────────────────────────────────────────────────────────
# Private helpers
# ────────────────────────────────────────────────────────────────────────────

sub _render_error ($self, $err) {
    $self->render(status => 500, openapi =>
        { errors => [{ message => "$err", path => '/' }] });
}

sub _to_data ($row) {
    my $data = { $row->get_columns };
    delete $data->{password};

    # Serialize DateTime objects to ISO 8601 strings
    for my $key (keys %$data) {
        my $val = $data->{$key};
        if (ref $val && eval { $val->isa('DateTime') }) {
            $data->{$key} = $val->iso8601;
        }
    }

    return $data;
}

1;
