/*
Translation database schema
*/
ALTER DATABASE COLLATE utf8_bin;

DROP TABLE IF EXISTS usn;
CREATE TABLE usn (
  usn INTEGER PRIMARY KEY AUTO_INCREMENT NOT NULL,
  dummy BOOLEAN NOT NULL
);

DROP TABLE IF EXISTS files;
CREATE TABLE files (
  id INTEGER PRIMARY KEY AUTO_INCREMENT NOT NULL,
  usn INTEGER DEFAULT 0 NOT NULL,
  job TEXT NOT NULL,
  namespace TEXT NOT NULL,
  path TEXT NOT NULL,
  orphaned BOOLEAN NOT NULL DEFAULT 0
);

DROP TABLE IF EXISTS strings;
CREATE TABLE strings (
  id INTEGER PRIMARY KEY AUTO_INCREMENT NOT NULL,
  usn INTEGER DEFAULT 0 NOT NULL,
  string TEXT NOT NULL,
  context TEXT,
  skip BOOLEAN NOT NULL DEFAULT 0
);

DROP TABLE IF EXISTS items;
CREATE TABLE items (
  id INTEGER PRIMARY KEY AUTO_INCREMENT NOT NULL,
  usn INTEGER DEFAULT 0 NOT NULL,
  file_id INTEGER NOT NULL,
  string_id INTEGER NOT NULL,
  hint TEXT NULL,
  comment TEXT NULL,
  orphaned BOOLEAN NOT NULL DEFAULT 0
);

DROP TABLE IF EXISTS translations;
CREATE TABLE translations (
  id INTEGER PRIMARY KEY AUTO_INCREMENT NOT NULL,
  usn INTEGER DEFAULT 0 NOT NULL,
  item_id INTEGER NOT NULL,
  language VARCHAR(16) NOT NULL,
  string TEXT NULL,
  comment TEXT NULL,
  fuzzy BOOLEAN NOT NULL DEFAULT 0,
  merge BOOLEAN NOT NULL DEFAULT 0
);

DROP TABLE IF EXISTS properties;
CREATE TABLE properties (
  id INTEGER PRIMARY KEY AUTO_INCREMENT NOT NULL,
  property VARCHAR(128) NOT NULL,
  value TEXT NOT NULL
);

CREATE UNIQUE INDEX items_file_id_string_id ON items (
  file_id ASC,
  string_id ASC
);

/* // not supported on MySQL
CREATE UNIQUE INDEX strings_string_context ON strings (
  string ASC,
  context ASC
);
*/

CREATE UNIQUE INDEX properties_property ON properties (
  property ASC
);

CREATE UNIQUE INDEX translations_item_id_language ON translations (
  item_id ASC,
  language ASC
);

CREATE INDEX files_usn ON files (
  usn ASC
);

CREATE INDEX strings_usn ON strings (
  usn ASC
);

CREATE INDEX items_usn ON items (
  usn ASC
);

CREATE INDEX translations_usn ON translations (
  usn ASC
);
