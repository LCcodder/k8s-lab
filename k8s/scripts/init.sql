CREATE DATABASE IF NOT EXISTS basketball_aggregator;
USE basketball_aggregator;

CREATE TABLE IF NOT EXISTS teams (
  id bigint unsigned NOT NULL AUTO_INCREMENT,
  name varchar(32) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY id (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS players (
  id bigint unsigned NOT NULL AUTO_INCREMENT,
  first_name varchar(16) DEFAULT NULL,
  last_name varchar(28) DEFAULT NULL,
  number tinyint DEFAULT NULL,
  position varchar(2) DEFAULT NULL,
  team_id bigint unsigned DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY id (id),
  KEY team_id (team_id),
  CONSTRAINT players_ibfk_1 FOREIGN KEY (team_id) REFERENCES teams (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS games (
  id bigint unsigned NOT NULL AUTO_INCREMENT,
  team_home_score int DEFAULT NULL,
  team_away_score int DEFAULT NULL,
  team_home_id bigint unsigned DEFAULT NULL,
  team_away_id bigint unsigned DEFAULT NULL,
  is_ended tinyint(1) DEFAULT NULL,
  created_at datetime DEFAULT NULL,
  updated_at datetime DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY id (id),
  KEY team_one_id (team_home_id),
  CONSTRAINT games_ibfk_1 FOREIGN KEY (team_home_id) REFERENCES teams (id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS users (
  id varchar(16) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS users_subscriptions_games (
  id bigint unsigned NOT NULL AUTO_INCREMENT,
  user_id varchar(16) DEFAULT NULL,
  game_id bigint unsigned DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY id (id),
  KEY user_id (user_id),
  KEY game_id (game_id),
  CONSTRAINT users_subscriptions_games_ibfk_42 FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT users_subscriptions_games_ibfk_43 FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS users_subscriptions_teams (
  id bigint unsigned NOT NULL AUTO_INCREMENT,
  user_id varchar(16) DEFAULT NULL,
  team_id bigint unsigned DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY id (id),
  KEY team_id (team_id),
  KEY user_id (user_id),
  CONSTRAINT users_subscriptions_teams_ibfk_1 FOREIGN KEY (team_id) REFERENCES teams (id) ON DELETE CASCADE,
  CONSTRAINT users_subscriptions_teams_ibfk_2 FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;