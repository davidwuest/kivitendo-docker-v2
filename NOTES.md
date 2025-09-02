# Neon Kivitendo Notes

./scripts/dbupgrade2_tool.pl --apply=ALL --user=david --dbuser=neondb_owner --client=1

./scripts/dbupgrade2_tool.pl --applied --user=david --dbuser=neondb_owner --client=1

./scripts/dbupgrade2_tool.pl --unapplied --user=david --dbuser=neondb_owner --client=1

./scripts/dbupgrade2_tool.pl --help

./scripts/dbupgrade2_tool.pl --test-utf8 --dbname=erp --dbhost=ep-dry-bush-a2nrx8pg-pooler.eu-central-1.aws.neon.tech --dbport=5432 --dbuser=neondb_owner --dbpassword=npg_ZG9ocXmO2DQy


perl t/000setup_database.t

perl t/test.pl

t/test.pl t/000setup_database.t

## Activate pg_trgm by running the CREATE EXTENSION statement in your Postgres client

CREATE EXTENSION IF NOT EXISTS pg_trgm;


GRANT dbadmin TO neon_superuser;