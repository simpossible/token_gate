package database

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	"token_gate/internal/model"

	_ "modernc.org/sqlite"
	"github.com/google/uuid"
)

type DB struct {
	*sql.DB
}

func Open(path string) (*DB, error) {
	log.Printf("[DB] Opening database: %s", path)
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping db: %w", err)
	}
	log.Printf("[DB] Database opened successfully")
	return &DB{db}, nil
}

func (db *DB) InitSchema() error {
	log.Printf("[DB] Initializing schema")
	schema := `
	CREATE TABLE IF NOT EXISTS token_config (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		url TEXT NOT NULL,
		api_key TEXT NOT NULL,
		model TEXT NOT NULL,
		created_at DATETIME NOT NULL,
		updated_at DATETIME NOT NULL
	);
	CREATE TABLE IF NOT EXISTS valid_config (
		id TEXT PRIMARY KEY,
		token_id TEXT NOT NULL REFERENCES token_config(id),
		agent_type TEXT NOT NULL UNIQUE,
		created_at DATETIME NOT NULL
	);
	CREATE TABLE IF NOT EXISTS usage (
		id TEXT PRIMARY KEY,
		token_id TEXT NOT NULL REFERENCES token_config(id),
		agent_type TEXT NOT NULL,
		input_tokens INTEGER NOT NULL DEFAULT 0,
		output_tokens INTEGER NOT NULL DEFAULT 0,
		latency_ms INTEGER NOT NULL DEFAULT 0,
		model TEXT NOT NULL DEFAULT '',
		request_path TEXT NOT NULL DEFAULT '',
		created_at DATETIME NOT NULL
	);
	`
	_, err := db.Exec(schema)
	if err != nil {
		log.Printf("[DB] Schema initialization failed: %v", err)
		return err
	}
	// migrate old databases that lack the latency_ms column
	db.Exec("ALTER TABLE usage ADD COLUMN latency_ms INTEGER NOT NULL DEFAULT 0")
	log.Printf("[DB] Schema initialized successfully")
	return nil
}

func (db *DB) IsEmpty() (bool, error) {
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM token_config").Scan(&count)
	return count == 0, err
}

// --- TokenConfig CRUD ---

func (db *DB) CreateTokenConfig(req *model.CreateConfigRequest) (*model.TokenConfig, error) {
	now := time.Now()
	c := &model.TokenConfig{
		ID:        uuid.New().String(),
		Name:      req.Name,
		URL:       req.URL,
		APIKey:    req.APIKey,
		Model:     req.Model,
		CreatedAt: now,
		UpdatedAt: now,
	}
	log.Printf("[DB] Creating token config: id=%s, name=%s", c.ID, c.Name)
	_, err := db.Exec(
		"INSERT INTO token_config (id, name, url, api_key, model, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
		c.ID, c.Name, c.URL, c.APIKey, c.Model, c.CreatedAt, c.UpdatedAt,
	)
	if err != nil {
		log.Printf("[DB] Create token config failed: %v", err)
		return nil, err
	}
	log.Printf("[DB] Token config created successfully: id=%s", c.ID)
	return c, nil
}

func (db *DB) GetTokenConfig(id string) (*model.TokenConfig, error) {
	c := &model.TokenConfig{}
	err := db.QueryRow(
		"SELECT id, name, url, api_key, model, created_at, updated_at FROM token_config WHERE id = ?",
		id,
	).Scan(&c.ID, &c.Name, &c.URL, &c.APIKey, &c.Model, &c.CreatedAt, &c.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return c, err
}

func (db *DB) ListTokenConfigs() ([]*model.TokenConfig, error) {
	rows, err := db.Query("SELECT id, name, url, api_key, model, created_at, updated_at FROM token_config ORDER BY created_at")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var configs []*model.TokenConfig
	for rows.Next() {
		c := &model.TokenConfig{}
		if err := rows.Scan(&c.ID, &c.Name, &c.URL, &c.APIKey, &c.Model, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		configs = append(configs, c)
	}
	return configs, rows.Err()
}

func (db *DB) UpdateTokenConfig(id string, req *model.UpdateConfigRequest) (*model.TokenConfig, error) {
	c, err := db.GetTokenConfig(id)
	if err != nil {
		return nil, err
	}
	if c == nil {
		return nil, fmt.Errorf("config not found")
	}

	log.Printf("[DB] Updating token config: id=%s", id)
	if req.Name != nil {
		c.Name = *req.Name
	}
	if req.URL != nil {
		c.URL = *req.URL
	}
	if req.APIKey != nil {
		c.APIKey = *req.APIKey
	}
	if req.Model != nil {
		c.Model = *req.Model
	}
	c.UpdatedAt = time.Now()

	_, err = db.Exec(
		"UPDATE token_config SET name=?, url=?, api_key=?, model=?, updated_at=? WHERE id=?",
		c.Name, c.URL, c.APIKey, c.Model, c.UpdatedAt, c.ID,
	)
	if err != nil {
		log.Printf("[DB] Update token config failed: %v", err)
		return nil, err
	}
	log.Printf("[DB] Token config updated successfully: id=%s, name=%s", c.ID, c.Name)
	return c, err
}

func (db *DB) DeleteTokenConfig(id string) error {
	log.Printf("[DB] Deleting token config: id=%s", id)
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec("DELETE FROM usage WHERE token_id = ?", id)
	if err != nil {
		log.Printf("[DB] Delete usage failed: %v", err)
		return err
	}
	_, err = tx.Exec("DELETE FROM valid_config WHERE token_id = ?", id)
	if err != nil {
		log.Printf("[DB] Delete valid_config failed: %v", err)
		return err
	}
	_, err = tx.Exec("DELETE FROM token_config WHERE id = ?", id)
	if err != nil {
		log.Printf("[DB] Delete token_config failed: %v", err)
		return err
	}
	if err := tx.Commit(); err != nil {
		log.Printf("[DB] Delete transaction commit failed: %v", err)
		return err
	}
	log.Printf("[DB] Token config deleted successfully: id=%s", id)
	return nil
}

// --- ValidConfig ---

func (db *DB) GetActiveConfig(agentType string) (*model.ValidConfig, error) {
	v := &model.ValidConfig{}
	err := db.QueryRow(
		"SELECT id, token_id, agent_type, created_at FROM valid_config WHERE agent_type = ?",
		agentType,
	).Scan(&v.ID, &v.TokenID, &v.AgentType, &v.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return v, err
}

func (db *DB) ListActiveConfigs() ([]*model.ValidConfig, error) {
	rows, err := db.Query("SELECT id, token_id, agent_type, created_at FROM valid_config")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var configs []*model.ValidConfig
	for rows.Next() {
		v := &model.ValidConfig{}
		if err := rows.Scan(&v.ID, &v.TokenID, &v.AgentType, &v.CreatedAt); err != nil {
			return nil, err
		}
		configs = append(configs, v)
	}
	return configs, rows.Err()
}

func (db *DB) ActivateConfig(tokenID, agentType string) error {
	log.Printf("[DB] Activating config: token_id=%s, agent_type=%s", tokenID, agentType)
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec("DELETE FROM valid_config WHERE agent_type = ?", agentType)
	if err != nil {
		log.Printf("[DB] Delete old valid_config failed: %v", err)
		return err
	}

	_, err = tx.Exec(
		"INSERT INTO valid_config (id, token_id, agent_type, created_at) VALUES (?, ?, ?, ?)",
		uuid.New().String(), tokenID, agentType, time.Now(),
	)
	if err != nil {
		log.Printf("[DB] Insert new valid_config failed: %v", err)
		return err
	}
	if err := tx.Commit(); err != nil {
		log.Printf("[DB] Activate transaction commit failed: %v", err)
		return err
	}
	log.Printf("[DB] Config activated successfully: token_id=%s, agent_type=%s", tokenID, agentType)
	return nil
}

func (db *DB) DeactivateConfig(agentType string) error {
	log.Printf("[DB] Deactivating config for agent_type: %s", agentType)
	_, err := db.Exec("DELETE FROM valid_config WHERE agent_type = ?", agentType)
	if err != nil {
		log.Printf("[DB] Deactivate config failed: %v", err)
		return err
	}
	log.Printf("[DB] Config deactivated successfully: agent_type=%s", agentType)
	return nil
}

func (db *DB) GetActiveAgentsForConfig(tokenID string) ([]string, error) {
	rows, err := db.Query("SELECT agent_type FROM valid_config WHERE token_id = ?", tokenID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var agents []string
	for rows.Next() {
		var a string
		if err := rows.Scan(&a); err != nil {
			return nil, err
		}
		agents = append(agents, a)
	}
	return agents, rows.Err()
}

// --- Usage ---

func (db *DB) RecordUsage(tokenID, agentType string, latencyMs int64, inputTokens, outputTokens int) error {
	log.Printf("[DB] Recording usage: token_id=%s, agent=%s, latency=%dms, input=%d, output=%d",
		tokenID, agentType, latencyMs, inputTokens, outputTokens)
	_, err := db.Exec(
		"INSERT INTO usage (id, token_id, agent_type, input_tokens, output_tokens, latency_ms, model, request_path, created_at) VALUES (?, ?, ?, ?, ?, ?, '', '', ?)",
		uuid.New().String(), tokenID, agentType, inputTokens, outputTokens, latencyMs, time.Now(),
	)
	if err != nil {
		log.Printf("[DB] Record usage failed: %v", err)
	}
	return err
}

func (db *DB) GetUsages(tokenID string, days int) ([]*model.Usage, error) {
	since := time.Now().AddDate(0, 0, -days)
	rows, err := db.Query(
		"SELECT id, token_id, agent_type, input_tokens, output_tokens, latency_ms, model, request_path, created_at FROM usage WHERE token_id = ? AND created_at >= ? ORDER BY created_at ASC",
		tokenID, since,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var usages []*model.Usage
	for rows.Next() {
		u := &model.Usage{}
		if err := rows.Scan(&u.ID, &u.TokenID, &u.AgentType, &u.InputTokens, &u.OutputTokens, &u.LatencyMs, &u.Model, &u.RequestPath, &u.CreatedAt); err != nil {
			return nil, err
		}
		usages = append(usages, u)
	}
	return usages, rows.Err()
}

func (db *DB) CleanupOldUsage(retainDays int) error {
	cutoff := time.Now().AddDate(0, 0, -retainDays)
	_, err := db.Exec("DELETE FROM usage WHERE created_at < ?", cutoff)
	return err
}

func (db *DB) GetUsage(tokenID string) (*model.UsageResponse, error) {
	resp := &model.UsageResponse{
		TokenID: tokenID,
		ByAgent: make(map[string]*model.AgentUsage),
	}

	err := db.QueryRow(
		"SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COUNT(*) FROM usage WHERE token_id = ?",
		tokenID,
	).Scan(&resp.TotalInputTokens, &resp.TotalOutputTokens, &resp.RecordsCount)
	if err != nil {
		return nil, err
	}

	rows, err := db.Query(
		"SELECT agent_type, SUM(input_tokens), SUM(output_tokens), COUNT(*) FROM usage WHERE token_id = ? GROUP BY agent_type",
		tokenID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		au := &model.AgentUsage{}
		var agentType string
		if err := rows.Scan(&agentType, &au.InputTokens, &au.OutputTokens, &au.Requests); err != nil {
			return nil, err
		}
		resp.ByAgent[agentType] = au
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	dailyRows, err := db.Query(
		`SELECT COALESCE(DATE(created_at), ''), agent_type, SUM(input_tokens), SUM(output_tokens), COUNT(*)
		 FROM usage WHERE token_id = ? GROUP BY DATE(created_at), agent_type ORDER BY DATE(created_at) DESC`,
		tokenID,
	)
	if err != nil {
		return nil, err
	}
	defer dailyRows.Close()

	for dailyRows.Next() {
		var du model.DailyUsage
		if err := dailyRows.Scan(&du.Date, &du.AgentType, &du.InputTokens, &du.OutputTokens, &du.Requests); err != nil {
			return nil, err
		}
		resp.DailyUsage = append(resp.DailyUsage, du)
	}
	return resp, dailyRows.Err()
}

func (db *DB) GetUsageSummary(tokenID string) (inputTokens, outputTokens int, err error) {
	err = db.QueryRow(
		"SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0) FROM usage WHERE token_id = ?",
		tokenID,
	).Scan(&inputTokens, &outputTokens)
	return
}

// Scan existing Claude Code settings for auto-import
func (db *DB) ImportExistingConfig(name, url, apiKey, modelStr string) error {
	log.Printf("[DB] Importing existing config: name=%s, url=%s", name, url)
	c, err := db.CreateTokenConfig(&model.CreateConfigRequest{
		Name:   name,
		URL:    url,
		APIKey: apiKey,
		Model:  modelStr,
	})
	if err != nil {
		log.Printf("[DB] Import existing config failed: %v", err)
		return err
	}
	if err := db.ActivateConfig(c.ID, "claude_code"); err != nil {
		log.Printf("[DB] Activate imported config failed: %v", err)
		return err
	}
	log.Printf("[DB] Import existing config success: id=%s", c.ID)
	return nil
}
