CREATE DATABASE treehub;

create user 'treehub' identified by 'treehub';

GRANT ALL PRIVILEGES ON `treehub%`.* TO 'treehub'@'%';

FLUSH PRIVILEGES;
