use strict;
use warnings;
use Test::More;
use Mojo::Base -signatures;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use Mojolicious;
use Cwd 'abs_path';
use lib abs_path("$FindBin::Bin/lib");  # absolute for forked workers
use File::Temp qw(tempdir);

my $tmpdir = tempdir(CLEANUP => 1);

# Build app with Fondation + DBIx::Async + User
my $app = Mojolicious->new;
$app->moniker('UserTest');
$app->log->level('fatal');

$app->config->{'Fondation'} = {
    dependencies => [
        {
            'Fondation::Model::DBIx::Async' => {
                backends => [
                    main => {
                        dsn          => "dbi:SQLite:dbname=$tmpdir/test.db",
                        schema_class => 'TestUserSchema',
                        workers      => 1,
                    },
                ],
                models => {
                    user => { source => 'users', backend => 'main' },
                },
            },
        },
        'Fondation::User',
    ],
};

$app->plugin('Fondation');

# Action::DBIx auto-discovers Result classes under plugin namespaces,
# but register_source() is silently skipped on the class in
# DBIx::Class::Async::Schema v1.0.4 — known bug.
# Workaround: register on the native schema class before workers fork.
require TestUserSchema;
require Mojolicious::Plugin::Fondation::User::Schema::Result::User;
TestUserSchema->register_source('users',
    Mojolicious::Plugin::Fondation::User::Schema::Result::User
        ->result_source_instance);
TestUserSchema->register_class('User',
    'Mojolicious::Plugin::Fondation::User::Schema::Result::User');

# Deploy the users table
my $c = $app->build_controller;
my $schema = $c->schema;
$schema->deploy->get;

my $rs = $c->model('user');
isa_ok($rs, 'DBIx::Class::Async::ResultSet', 'model helper returns ResultSet');

# --- CRUD via model helper ---

# Create
my $created = $schema->await($rs->create({
    username => 'alice',
    email    => 'alice@example.com',
    password => 'secret123',
}));
ok($created->id, 'create works');
is($created->username, 'alice', 'create sets username');

# Read (find)
my $found = $schema->await($rs->find($created->id));
is($found->username, 'alice', 'find returns correct user');
is($found->email,    'alice@example.com', 'find returns email');

# Search
my $results = $schema->await($rs->search({ username => 'alice' })->all);
is(scalar @$results, 1, 'search finds one');

# Update
$schema->await($found->update({ username => 'alice2' }));
my $updated = $schema->await($rs->find($created->id));
is($updated->username, 'alice2', 'update changes username');

# Delete
$schema->await($found->delete);
my $gone = $schema->await($rs->find($created->id));
is($gone, undef, 'delete removes user');

done_testing;
