create database if not exists auditor;
create user if not exists 'auditor'@'%' identified by '$AUDITOR_DB_PASS';
grant all privileges on `auditor%`.* to 'auditor'@'%';

create database if not exists campaigner;
create user if not exists 'campaigner'@'%' identified by '$CAMPAIGNER_DB_PASS';
grant all privileges on `campaigner%`.* to 'campaigner'@'%';

create database if not exists crypt_vault;
create user if not exists 'crypt_vault'@'%' identified by '$CRYPT_VAULT_DB_PASS';
grant all privileges on `crypt_vault%`.* to 'crypt_vault'@'%';

create database if not exists delta_builder;
create user if not exists 'delta_builder'@'%' identified by '$DELTA_BUILDER_DB_PASS';
grant all privileges on `delta_builder%`.* to 'delta_builder'@'%';

create database if not exists device_registry;
create user if not exists 'device_registry'@'%' identified by '$DEVICE_REGISTRY_DB_PASS';
grant all privileges on `device_registry%`.* to 'device_registry'@'%';

create database if not exists director;
create user if not exists 'director'@'%' identified by '$DIRECTOR_DB_PASS';
grant all privileges on `director%`.* to 'director'@'%';

create database if not exists sota_core;
create user if not exists 'sota_core'@'%' identified by '$SOTA_CORE_DB_PASS';
grant all privileges on `sota_core%`.* to 'sota_core'@'%';

create database if not exists treehub;
create user if not exists 'treehub'@'%' identified by '$TREEHUB_DB_PASS';
grant all privileges on `treehub%`.* to 'treehub'@'%';

create database if not exists tuf_keyserver;
create user if not exists 'tuf_keyserver'@'%' identified by '$TUF_KEYSERVER_DB_PASS';
grant all privileges on `tuf_keyserver%`.* to 'tuf_keyserver'@'%';

create database if not exists tuf_reposerver;
create user if not exists 'tuf_reposerver'@'%' identified by '$TUF_REPOSERVER_DB_PASS';
grant all privileges on `tuf_reposerver%`.* to 'tuf_reposerver'@'%';

create database if not exists user_profile;
create user if not exists 'user_profile'@'%' identified by '$USER_PROFILE_DB_PASS';
grant all privileges on `user_profile%`.* to 'user_profile'@'%';

flush privileges;
