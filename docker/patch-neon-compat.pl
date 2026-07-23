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

# --- Patch 1: rewrite SL::DBConnect::_connect for Neon ----------------------
# Inject TLS + the SNI-fallback endpoint + a generous connect_timeout into the
# DSN, and retry the connection so a Neon scale-to-zero cold start (the compute
# waking from suspend) is tolerated instead of surfacing as an error. All
# self-gating on *.neon.tech, so a normal/local PostgreSQL is untouched.
{
    my $file = '/opt/kivitendo-erp/SL/DBConnect.pm';
    my $src  = slurp($file);

    if ($src =~ /Neon scale-to-zero/) {
        print "SL::DBConnect Neon _connect patch: already present\n";
    } else {
        my $new_connect = <<'PERL';
sub _connect {
  my ($self, @args) = @_;

  # Neon: inject TLS, the SNI-fallback endpoint (bullseye libpq predates SNI),
  # and a generous connect_timeout straight into the DSN.
  my $is_neon = defined $args[0] && $args[0] =~ m/host=([A-Za-z0-9._-]*\.neon\.tech)/;
  if ($is_neon) {
    (my $endpoint = $1) =~ s/\..*//;
    $args[0] .= ";sslmode=require"            unless $args[0] =~ /sslmode=/;
    $args[0] .= ";options=endpoint=$endpoint" unless $args[0] =~ /options=/;
    $args[0] .= ";connect_timeout=20"         unless $args[0] =~ /connect_timeout=/;
  }

  my $do_connect = sub {
    return DBI->connect(@args) unless $::lx_office_conf{debug} && $::lx_office_conf{debug}->{dbix_log4perl};

    require Log::Log4perl;
    require DBIx::Log4perl;

    my $filename =  $::lxdebug->file;
    my $config   =  $::lx_office_conf{debug}->{dbix_log4perl_config};
    $config      =~ s/LXDEBUGFILE/${filename}/g;

    Log::Log4perl->init(\$config);
    return DBIx::Log4perl->connect(@args);
  };

  return $do_connect->() unless $is_neon;

  # Neon scale-to-zero: the compute may be suspended and take several seconds to
  # wake. Retry a handful of times so a cold start is tolerated, not thrown.
  # Do NOT retry permanent errors (missing database/role, auth failure) — those
  # are definitive answers, e.g. the auth database not existing before setup.
  my ($dbh, $err);
  for my $try (1 .. 5) {
    $dbh = eval { $do_connect->() };
    # $@ is only set when RaiseError dies; DBI->connect otherwise returns undef
    # and reports via $DBI::errstr. Use both so permanent errors are detected.
    $err = $@ || $DBI::errstr || '';
    last if $dbh;
    last if $err =~ /does not exist|authentication failed|no pg_hba|role ".*" does not/i;
    $::lxdebug->message(0, "Neon DB connect attempt $try failed, retrying in 3s: $err") if $::lxdebug;
    sleep 3;
  }
  die $@ if !$dbh && $@;   # preserve RaiseError-vs-undef semantics for callers
  return $dbh;
}
PERL
        chomp $new_connect;
        $src =~ s{^sub _connect \{.*?^\}$}{$new_connect}sm
            or die "SL::DBConnect Neon _connect patch: _connect sub not found\n";
        spew($file, $src);
        print "SL::DBConnect Neon _connect patch: applied\n";
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

# --- Patch 5: evict dead cached handles after a Neon cold start -------------
# SL::DBConnect::Cache->get reuses a cached handle as long as DBI marks it
# {Active}. But after Neon scales to zero the compute drops the connection
# server-side while DBI still thinks it is Active, so the stale handle gets
# reused and the next query fails with "no connection to the server". For Neon
# hosts, ping the cached handle and evict it if it is really dead, so connect()
# falls through to a fresh (retrying) _connect. Gated on *.neon.tech.
{
    my $file = '/opt/kivitendo-erp/SL/DBConnect/Cache.pm';
    my $src  = slurp($file);

    if ($src =~ /Neon.*ping/s) {
        print "SL::DBConnect::Cache Neon ping patch: already present\n";
    } else {
        my $replacement = <<'PERL';
  # Neon scale-to-zero: ping so a server-side-dropped handle is evicted, not reused.
  my $is_neon = defined $args[0] && $args[0] =~ /\.neon\.tech/;
  if (!$dbh->{Active} || ($dbh && $is_neon && !eval { $dbh->ping })) {
PERL
        chomp $replacement;
        $src =~ s{^  if \(!\$dbh->\{Active\}\) \{$}{$replacement}m
            or die "SL::DBConnect::Cache Neon ping patch: get() guard not found\n";
        spew($file, $src);
        print "SL::DBConnect::Cache Neon ping patch: applied\n";
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

# --- Patch 6: heal SL::Auth's cached handle after a Neon cold start ---------
# SL::Auth caches its own $self->{dbh} and dbconnect() returns it directly,
# bypassing SL::DBConnect::Cache (and its ping). Long-lived FCGI workers
# (FcgidMinProcessesPerClass keeps some alive indefinitely) therefore reuse a
# handle that Neon dropped when it scaled to zero, and the next auth/session
# query fails with "no connection to the server". For Neon hosts, ping the
# cached handle and drop it if dead so dbconnect() reconnects. Gated on
# *.neon.tech, so a normal/local PostgreSQL is untouched.
{
    my $file = '/opt/kivitendo-erp/SL/Auth.pm';
    my $src  = slurp($file);

    if ($src =~ /\$self->\{dbh\}->ping/) {
        print "SL::Auth::dbconnect Neon ping patch: already present\n";
    } else {
        my $replacement = <<'PERL';
  if ($self->{dbh}) {
    # Neon scale-to-zero: the cached auth handle may be dead after the compute
    # suspended (DBI still marks it Active); ping and drop it so we reconnect.
    my $auth_host = $self->{DB_config} ? ($self->{DB_config}->{host} // '') : '';
    return $self->{dbh} if $auth_host !~ /\.neon\.tech/ || eval { $self->{dbh}->ping };
    eval { $self->{dbh}->disconnect };
    delete $self->{dbh};
  }
PERL
        chomp $replacement;
        $src =~ s{  if \(\$self->\{dbh\}\) \{\n    return \$self->\{dbh\};\n  \}}{$replacement}
            or die "SL::Auth::dbconnect Neon ping patch: cached-dbh guard not found\n";
        spew($file, $src);
        print "SL::Auth::dbconnect Neon ping patch: applied\n";
    }
}

# --- Patch 7: create the AUTH database from template0 on Neon ---------------
# SL::Auth::create_database (admin "create auth database" step) uses the
# db_template value from the form, which defaults to template1. On Neon
# template1 always has a live session, so CREATE DATABASE ... TEMPLATE template1
# fails. Force template0 for Neon hosts (same reasoning as patch 4 for client
# databases). Gated on *.neon.tech.
{
    my $file = '/opt/kivitendo-erp/SL/Auth.pm';
    my $src  = slurp($file);

    if ($src =~ /Neon: force template0/) {
        print "SL::Auth::create_database template0 patch: already present\n";
    } else {
        my $replacement = <<'PERL';
  $params{template} = 'template0'   # Neon: force template0 (template1 is busy)
    if $cfg->{host} && $cfg->{host} =~ /\.neon\.tech/;

  my $dsn = 'dbi:Pg:dbname=template1;host=' . $cfg->{host};
PERL
        chomp $replacement;
        $src =~ s{  my \$dsn = 'dbi:Pg:dbname=template1;host=' \. \$cfg->\{host\};}{$replacement}
            or die "SL::Auth::create_database template0 patch: create_database DSN not found\n";
        spew($file, $src);
        print "SL::Auth::create_database template0 patch: applied\n";
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
