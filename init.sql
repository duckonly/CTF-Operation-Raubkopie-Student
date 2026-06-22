CREATE DATABASE IF NOT EXISTS filmfrei;
USE filmfrei;

CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50),
  password VARCHAR(255),
  role VARCHAR(20)
);
INSERT INTO users VALUES
(1, 'admin', 'sup3rs3cr3tP4ss!', 'admin'),
(2, 'moderator', 'mod2024!', 'moderator'),
(3, 'uploader42', 'upload_king', 'uploader');

CREATE TABLE uploaders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  real_name VARCHAR(100),
  email VARCHAR(100),
  ip_address VARCHAR(45),
  uploaded_files INT,
  profit_eur DECIMAL(10,2),
  flag VARCHAR(200)
);
INSERT INTO uploaders VALUES
(1, 'Janus Marsaleck', 'j.marsaleck@darkmail.to', '185.234.72.11', 342, 15420.50, ''),
(2, 'Lisa Schwarzkopf', 'l.schwarz@proton.me', '91.203.5.176', 187, 8930.00, ''),
(3, 'Mira Stahl', 'm.stahl@proton.me', '127.18.4.23', 61, 2110.00, ''),
(4, 'Dmitri Volkov', 'd.volkov@temp-mail.ru', '45.142.213.8', 523, 24100.75, ''),
(5, 'Anonym_1337', 'noname@onion.link', '10.0.0.1', 89, 3200.00, '');

CREATE TABLE payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uploader_id INT,
  amount DECIMAL(10,2),
  crypto_wallet VARCHAR(100),
  date DATE
);
INSERT INTO payments VALUES
(1, 1, 5000.00, 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh', '2024-01-15'),
(2, 4, 8000.00, 'bc1q9h5yjqka3mz2f3hp5xrv3vq3lq8s9xkn7y8z4', '2024-02-20'),
(3, 1, 10420.50, 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh', '2024-03-10');

CREATE TABLE teams (
  id INT AUTO_INCREMENT PRIMARY KEY,
  team_name VARCHAR(100) UNIQUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE stage_timers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  team_id INT,
  stage INT,
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP NULL DEFAULT NULL,
  elapsed_seconds INT NULL DEFAULT NULL,
  FOREIGN KEY (team_id) REFERENCES teams(id),
  UNIQUE KEY unique_team_stage_timer (team_id, stage)
);

CREATE TABLE challenge_state (
  state_key VARCHAR(50) PRIMARY KEY,
  state_json TEXT,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE submissions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  team_id INT,
  flag VARCHAR(200),
  stage INT,
  points INT,
  submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (team_id) REFERENCES teams(id),
  UNIQUE KEY unique_team_stage (team_id, stage)
);

CREATE TABLE hint_usage (
  id INT AUTO_INCREMENT PRIMARY KEY,
  team_id INT,
  stage INT,
  hint_level INT,
  penalty INT,
  used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (team_id) REFERENCES teams(id),
  UNIQUE KEY unique_team_hint (team_id, stage, hint_level)
);

CREATE TABLE goat_challenges (
  id INT AUTO_INCREMENT PRIMARY KEY,
  team_id INT,
  event_id VARCHAR(20) NOT NULL,
  operator_alias VARCHAR(80) NOT NULL,
  wallet_indicator VARCHAR(128) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (team_id) REFERENCES teams(id),
  UNIQUE KEY unique_goat_challenge_team (team_id)
);

CREATE TABLE goat_solves (
  id INT AUTO_INCREMENT PRIMARY KEY,
  team_id INT,
  flag VARCHAR(200) NOT NULL,
  event_id VARCHAR(20) NOT NULL,
  operator_alias VARCHAR(80) NOT NULL,
  proof VARCHAR(128) NOT NULL,
  answers_json TEXT,
  solved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (team_id) REFERENCES teams(id),
  UNIQUE KEY unique_goat_team (team_id)
);

GRANT ALL PRIVILEGES ON filmfrei.* TO 'filmfrei'@'%';
FLUSH PRIVILEGES;
