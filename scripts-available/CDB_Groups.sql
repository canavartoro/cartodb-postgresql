-- Creates a new group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_CreateGroup(group_name text)
    RETURNS VOID AS $$
DECLARE
    group_role TEXT;
BEGIN
    group_role := cartodb._CDB_Group_GroupRole(group_name);
    PERFORM cartodb._CDB_Group_CreateGroup_API(current_database(), group_name, group_role);
    EXECUTE 'CREATE ROLE "' || group_role || '" NOLOGIN;';
END
$$ LANGUAGE PLPGSQL VOLATILE;

-- Drops group and everything that role owns
-- TODO: LIMITATION: in order to drop a role all its owned objects must be dropped before.
-- Right now this is done with DROP OWNED, which can only be done by a superadmin.
-- Not even the role creator can drop the role and the objects it owns.
-- All group owned objects by the group are permissions.
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_DropGroup(group_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    PERFORM cartodb._CDB_Group_DropGroup_API(current_database(), group_name);
    EXECUTE 'DROP OWNED BY "' || cdb_group_role || '"';
    EXECUTE 'DROP ROLE IF EXISTS "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

-- Renames a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_RenameGroup(old_group_name text, new_group_name text)
    RETURNS VOID AS $$
BEGIN
    EXECUTE 'ALTER ROLE "' || cartodb._CDB_Group_GroupRole(old_group_name) || '" RENAME TO "' || cartodb._CDB_Group_GroupRole(new_group_name) || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

-- Adds a user to a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_AddMember(group_name text, username text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
    cdb_user_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    cdb_user_role := cartodb._CDB_User_RoleFromUsername(username);
    EXECUTE 'GRANT "' || cdb_group_role || '" TO "' || cdb_user_role || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

-- Removes a user from a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_RemoveMember(group_name text, username text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
    cdb_user_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    cdb_user_role := cartodb._CDB_User_RoleFromUsername(username);
    EXECUTE 'REVOKE "' || cdb_group_role || '" FROM "' || cdb_user_role || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

-- Grants table read permission to a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_Table_GrantRead(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    EXECUTE 'GRANT USAGE ON SCHEMA "' || username || '" TO "' || cdb_group_role || '"';
    EXECUTE 'GRANT SELECT ON TABLE "' || username || '"."' || table_name || '" TO "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

-- Grants table write permission to a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_Table_GrantReadWrite(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    EXECUTE 'GRANT USAGE ON SCHEMA "' || username || '" TO "' || cdb_group_role || '"';
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "' || username || '"."' || table_name || '" TO "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

-- Revokes all permissions on a table from a group
CREATE OR REPLACE
FUNCTION cartodb.CDB_Group_Table_RevokeAll(group_name text, username text, table_name text)
    RETURNS VOID AS $$
DECLARE
    cdb_group_role TEXT;
BEGIN
    cdb_group_role := cartodb._CDB_Group_GroupRole(group_name);
    EXECUTE 'REVOKE ALL ON TABLE "' || username || '"."' || table_name || '" FROM "' || cdb_group_role || '"';
END
$$ LANGUAGE PLPGSQL VOLATILE;

-----------------------
-- Private functions
-----------------------
-- Given a group name returns a role. group_name must be a valid PostgreSQL idenfifier. See http://www.postgresql.org/docs/9.2/static/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS
CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_GroupRole(group_name text)
    RETURNS TEXT AS $$
DECLARE
    group_role TEXT;
    prefix TEXT;
    max_length constant INTEGER := 63;
BEGIN
    IF group_name !~ '^[a-zA-Z_][a-zA-Z0-9_]*$'
    THEN
        RAISE EXCEPTION 'Group name (%) must be a valid identifier. See http://www.postgresql.org/docs/9.2/static/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS', group_name;
    END IF;
    prefix = cartodb._CDB_Group_ShortDatabaseName() || '_g_';
    group_role := prefix || group_name;
    IF LENGTH(group_role) > max_length
    THEN
        RAISE EXCEPTION 'Group name must be shorter. It can''t have more than % characters, but it is longer (%): %', max_length - LENGTH(prefix), length(group_name), group_name;
    END IF;
    RETURN group_role;
END
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Returns the first owner of the schema matching username. Organization user schemas must have one only owner.
CREATE OR REPLACE
FUNCTION cartodb._CDB_User_RoleFromUsername(username text)
    RETURNS TEXT AS $$
DECLARE
    user_role TEXT;
BEGIN
    -- This was preferred, but non-superadmins won't get results
    --EXECUTE 'SELECT SCHEMA_OWNER FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = $1 LIMIT 1' INTO user_role USING username;
    EXECUTE 'SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = $1;' INTO user_role USING username;
    RETURN user_role;
END
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Database names are too long, we need a shorter version for composing role names
CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_ShortDatabaseName()
    RETURNS TEXT AS $$
DECLARE
    short_database_name TEXT;
BEGIN
    EXECUTE 'SELECT md5(current_database())' INTO short_database_name;
    RETURN short_database_name;
END
$$ LANGUAGE PLPGSQL IMMUTABLE;
