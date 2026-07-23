#!/usr/bin/perl
# Build-time patches that make kivitendo work with Neon serverless Postgres.
# Both are minimal and safe for a normal/local PostgreSQL too.
#
# 1) SL::DBConnect::_connect — inject the Neon connection requirements straight
#    into the DSN (kivitendo builds DSNs without them and relies on libpq env
#    vars, which mod_fcgid does not pass to its workers):
#      * sslmode=require        -> Neon mandates TLS
#      * options=endpoint=<id>  -> SNI fallback for libpq < 14 (bullseye ships 13)
#    Self-gating on *.neon.tech hosts, so it is inert for local PostgreSQL.
#
# 2) SL::DBUtils::role_is_superuser — accept CREATEDB as sufficient. kivitendo's
#    "create dataset" UI gates on a real Postgres superuser (usesuper), but Neon
#    never grants one. Creating the client database only needs CREATEDB (verified:
#    neondb_owner creates the DB and loads the full base schema fine), so we treat
#    "usesuper OR usecreatedb" as privileged. A real superuser still passes.
use strict;
use warnings;

# --- Patch 1: DSN injection in SL::DBConnect::_connect ----------------------
{
    my $file = '/opt/kivitendo-erp/SL/DBConnect.pm';
    my $src  = slurp($file);

    if ($src =~ /options=endpoint/) {
        print "SL::DBConnect DSN patch: already present\n";
    } else {
        my $inject = <<'PERL';

  # Neon: inject TLS + SNI-fallback endpoint straight into the DSN.
  if (defined $args[0] && $args[0] =~ m/host=([A-Za-z0-9._-]*\.neon\.tech)/) {
    (my $endpoint = $1) =~ s/\..*//;
    $args[0] .= ";sslmode=require"            unless $args[0] =~ /sslmode=/;
    $args[0] .= ";options=endpoint=$endpoint" unless $args[0] =~ /options=/;
  }
PERL
        # Inline replacement so $1 (the captured signature) and $inject both
        # interpolate correctly.
        $src =~ s{(sub _connect \{\n\s*my \(\$self, \@args\) = \@_;\n)}{$1$inject}
            or die "SL::DBConnect DSN patch: _connect signature not found\n";
        spew($file, $src);
        print "SL::DBConnect DSN patch: applied\n";
    }
}

# --- Patch 2: accept CREATEDB as "superuser" for dataset creation ----------
{
    my $file = '/opt/kivitendo-erp/SL/DBUtils.pm';
    my $src  = slurp($file);

    if ($src =~ /usesuper OR usecreatedb/) {
        print "SL::DBUtils::role_is_superuser CREATEDB patch: already present\n";
    } else {
        $src =~ s{SELECT usesuper FROM pg_user WHERE usename = \?}
                 {SELECT usesuper OR usecreatedb FROM pg_user WHERE usename = ?}
            or die "SL::DBUtils::role_is_superuser CREATEDB patch: query not found\n";
        spew($file, $src);
        print "SL::DBUtils::role_is_superuser CREATEDB patch: applied\n";
    }
}

# --- Patch 4: create client DBs from template0, not template1 --------------
# kivitendo copies the client DB from $dbdefault (default: template1). On Neon
# template1 always has a live session, so "CREATE DATABASE ... TEMPLATE
# template1" fails with "source database is being accessed by other users", the
# DB is never created, and the next step reports 'database ... does not exist'.
# template0 (connections disabled) is always a valid template — this is also
# what kivitendo's own auth-DB creation already uses. The CREATE is still issued
# on a connection to $dbdefault, only the TEMPLATE source changes.
{
    my $file = '/opt/kivitendo-erp/SL/User.pm';
    my $src  = slurp($file);

    if ($src =~ /TEMPLATE = template0/) {
        print "SL::User dbcreate template0 patch: already present\n";
    } else {
        $src =~ s{push \@dboptions, "TEMPLATE = \$dbdefault";}
                 {push \@dboptions, "TEMPLATE = template0";}
            or die "SL::User dbcreate template0 patch: line not found\n";
        spew($file, $src);
        print "SL::User dbcreate template0 patch: applied\n";
    }
}

# --- Patch 3: route the "test connection" through SL::DBConnect -------------
# action_test_database_connectivity uses DBI->connect directly, bypassing the
# SL::DBConnect::_connect chokepoint (and thus the Neon DSN injection above).
# Route it through SL::DBConnect->connect instead (already imported there).
{
    my $file = '/opt/kivitendo-erp/SL/Controller/Admin.pm';
    my $src  = slurp($file);

    if ($src =~ /SL::DBConnect->connect\(\$dbconnect, \$cfg\{dbuser\}/) {
        print "Admin.pm test-connection routing patch: already present\n";
    } else {
        # Must pass the options hashref (get_options) as the 4th arg, otherwise
        # SL::DBConnect::Cache misaligns initial_sql into the options slot.
        $src =~ s{DBI->connect\(\$dbconnect, \$cfg\{dbuser\}, \$cfg\{dbpasswd\}\)}
                 {SL::DBConnect->connect(\$dbconnect, \$cfg{dbuser}, \$cfg{dbpasswd}, SL::DBConnect->get_options)}
            or die "Admin.pm test-connection routing patch: DBI->connect call not found\n";
        spew($file, $src);
        print "Admin.pm test-connection routing patch: applied\n";
    }
}

sub slurp {
    my ($file) = @_;
    open my $fh, '<', $file or die "open $file: $!";
    local $/;
    my $data = <$fh>;
    close $fh;
    return $data;
}

sub spew {
    my ($file, $data) = @_;
    open my $fh, '>', $file or die "write $file: $!";
    print $fh $data;
    close $fh;
}
