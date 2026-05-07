package database

import (
	"database/sql"
	"fmt"
	"time"

	"token_gate/internal/model"

	_ "modernc.org/sqlite"
	"github.com/google/uuid"
)

type DB struct {
	*sql.DB
}

func Open(path string) (*DB, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping db: %w", err)
	}
	return &DB{db}, nil
}

func (db *DB) InitSchema() error {
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
		model TEXT NOT NULL DEFAULT '',
		request_path TEXT NOT NULL DEFAULT '',
		created_at DATETIME NOT NULL
	);
	`
	_, err := db.Exec(schema)
	return err
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
	_, err := db.Exec(
		"INSERT INTO token_config (id, name, url, api_key, model, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
		c.ID, c.Name, c.URL, c.APIKey, c.Model, c.CreatedAt, c.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
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
	return c, err
}

func (db *DB) DeleteTokenConfig(id string) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec("DELETE FROM usage WHERE token_id = ?", id)
	if err != nil {
		return err
	}
	_, err = tx.Exec("DELETE FROM valid_config WHERE token_id = ?", id)
	if err != nil {
		return err
	}
	_, err = tx.Exec("DELETE FROM token_config WHERE id = ?", id)
	if err != nil {
		return err
	}
	return tx.Commit()
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
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec("DELETE FROM valid_config WHERE agent_type = ?", agentType)
	if err != nil {
		return err
	}

	_, err = tx.Exec(
		"INSERT INTO valid_config (id, token_id, agent_type, created_at) VALUES (?, ?, ?, ?)",
		uuid.New().String(), tokenID, agentType, time.Now(),
	)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (db *DB) DeactivateConfig(agentType string) error {
	_, err := db.Exec("DELETE FROM valid_config WHERE agent_type = ?", agentType)
	return err
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

func (db *DB) RecordUsage(tokenID, agentType string, inputTokens, outputTokens int, reqModel, requestPath string) error {
	_, err := db.Exec(
		"INSERT INTO usage (id, token_id, agent_type, input_tokens, output_tokens, model, request_path, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
		uuid.New().String(), tokenID, agentType, inputTokens, outputTokens, reqModel, requestPath, time.Now(),
	)
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
		`SELECT DATE(created_at) as date, agent_type, SUM(input_tokens), SUM(output_tokens), COUNT(*)
		 FROM usage WHERE token_id = ? GROUP BY DATE(created_at), agent_type ORDER BY date DESC`,
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
	c, err := db.CreateTokenConfig(&model.CreateConfigRequest{
		Name:   name,
		URL:    url,
		APIKey: apiKey,
		Model:  modelStr,
	})
	if err != nil {
		return err
	}
	return db.ActivateConfig(c.ID, "claude_code")
}
