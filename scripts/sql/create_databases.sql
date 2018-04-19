set global max_connections=500;

create database if not exists campaigner;
create user if not exists 'campaigner'@'%' identified by 'campaigner';
grant all privileges on `campaigner%`.* to 'campaigner'@'%';

create database if not exists crypt_vault;
create user if not exists 'crypt_vault'@'%' identified by 'crypt_vault';
grant all privileges on `crypt_vault%`.* to 'crypt_vault'@'%';

create database if not exists device_registry;
create user if not exists 'device_registry'@'%' identified by 'device_registry';
grant all privileges on `device_registry%`.* to 'device_registry'@'%';

create database if not exists director;
create user if not exists 'director'@'%' identified by 'director';
grant all privileges on `director%`.* to 'director'@'%';

create database if not exists sota_core;
create user if not exists 'sota_core'@'%' identified by 'sota_core';
grant all privileges on `sota_core%`.* to 'sota_core'@'%';

create database if not exists treehub;
create user if not exists 'treehub'@'%' identified by 'treehub';
grant all privileges on `treehub%`.* to 'treehub'@'%';

create database if not exists tuf_keyserver;
create user if not exists 'tuf_keyserver'@'%' identified by 'tuf_keyserver';
grant all privileges on `tuf_keyserver%`.* to 'tuf_keyserver'@'%';

create database if not exists tuf_reposerver;
create user if not exists 'tuf_reposerver'@'%' identified by 'tuf_reposerver';
grant all privileges on `tuf_reposerver%`.* to 'tuf_reposerver'@'%';

create database if not exists tuf_vault;
create user if not exists 'tuf_vault'@'%' identified by 'tuf_vault';
grant all privileges on `tuf_vault%`.* to 'tuf_vault'@'%';

flush privileges;
