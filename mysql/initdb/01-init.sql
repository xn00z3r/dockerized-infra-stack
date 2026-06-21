-- =============================================================================
-- 01-init.sql — MySQL Initialization
-- File ini STATIC — tidak berisi credentials
-- Di-commit ke git
--
-- Dieksekusi SEKALI saat data directory kosong
-- Untuk menambah database/user project, tambahkan file baru (02-myapp.sql, dst)
-- =============================================================================

-- Database default tersedia untuk project development
CREATE DATABASE IF NOT EXISTS `default_db`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Informational
SELECT 'MySQL initialized successfully' AS status;
