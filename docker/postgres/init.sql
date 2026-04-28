-- ANTOPS Self-Hosted Database Initialization
-- This script initializes extensions and basic configuration

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pgcrypto for password hashing support
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Set timezone to UTC
SET timezone = 'UTC';

-- Create application database user (if not already created by POSTGRES_USER)
-- This is handled by Docker environment variables, but we ensure proper permissions

GRANT ALL PRIVILEGES ON DATABASE antops TO antops;
