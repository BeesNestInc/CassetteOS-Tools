-- ストアドプロシージャ専用のユーザーを作成（passswordなし）
CREATE ROLE db_admin_user WITH LOGIN;

-- このユーザーにはスーパーユーザー権限を付与しない
REVOKE ALL ON SCHEMA public FROM db_admin_user;

-- ストアドプロシージャ
CREATE OR REPLACE FUNCTION create_docker_app_user(username TEXT, userpass TEXT) RETURNS VOID AS $$
BEGIN
  -- ユーザーが存在しない場合にのみ作成
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = username) THEN
    EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L CREATEDB;', username, userpass);
    RAISE NOTICE 'User % created.', username;
  ELSE
    RAISE NOTICE 'User % already exists.', username;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 関数の所有者（作成者）の権限を確認
ALTER FUNCTION create_docker_app_user(TEXT, TEXT) OWNER TO postgres;

-- 実行権限をdb_admin_userに付与
GRANT EXECUTE ON FUNCTION create_docker_app_user(TEXT, TEXT) TO db_admin_user;
REVOKE EXECUTE ON FUNCTION create_docker_app_user(TEXT, TEXT) FROM PUBLIC;