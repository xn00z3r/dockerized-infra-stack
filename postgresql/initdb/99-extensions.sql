-- =============================================================================
-- 99-extensions.sql — PostgreSQL Extensions untuk GitLab
-- File ini STATIC (tidak berisi credentials) — di-commit ke git
--
-- Dieksekusi setelah 01-gitlab.sql (urutan alphanumerik)
-- Dijalankan sebagai superuser (POSTGRES_USER)
--
-- PENTING: Menggunakan \c gitlabdb literal
-- Jika GITLAB_DB_NAME diubah dari 'gitlabdb', file ini HARUS diupdate manual
-- =============================================================================

\c gitlabdb

-- Extensions yang dibutuhkan GitLab CE
CREATE EXTENSION IF NOT EXISTS pg_trgm;      -- Full-text search di GitLab
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- Index untuk exclusion constraints
CREATE EXTENSION IF NOT EXISTS plpgsql;      -- Procedural language (biasanya sudah ada)
