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
		agent_type TEXT NOT NULL DEFAULT '',
		is_active INTEGER NOT NULL DEFAULT 0,
		created_at DATETIME NOT NULL,
		updated_at DATETIME NOT NULL
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

	// migrate old databases
	db.Exec("ALTER TABLE usage ADD COLUMN latency_ms INTEGER NOT NULL DEFAULT 0")
	db.Exec("ALTER TABLE usage ADD COLUMN created_at_ts INTEGER NOT NULL DEFAULT 0")
	db.Exec("UPDATE usage SET created_at_ts = CAST(strftime('%s', created_at) * 1000 AS INTEGER) WHERE created_at_ts = 0")

	// migrate from old schema: add agent_type and is_active columns
	db.Exec("ALTER TABLE token_config ADD COLUMN agent_type TEXT NOT NULL DEFAULT ''")
	db.Exec("ALTER TABLE token_config ADD COLUMN is_active INTEGER NOT NULL DEFAULT 0")

	// migrate data from valid_config if it exists (old schema)
	if err := db.migrateFromValidConfig(); err != nil {
		log.Printf("[DB] Warning: valid_config migration: %v", err)
	}

	log.Printf("[DB] Schema initialized successfully")
	return nil
}

func (db *DB) migrateFromValidConfig() error {
	var tableName string
	err := db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name='valid_config'").Scan(&tableName)
	if err != nil {
		// valid_config doesn't exist — fresh install, nothing to migrate
		return nil
	}

	log.Printf("[DB] Migrating data from valid_config table...")

	rows, err := db.Query("SELECT token_id, agent_type FROM valid_config")
	if err != nil {
		return fmt.Errorf("query valid_config: %w", err)
	}
	defer rows.Close()

	assigned := make(map[string]string) // token_id -> first agent_type assigned

	for rows.Next() {
		var tokenID, agentType string
		if err := rows.Scan(&tokenID, &agentType); err != nil {
			continue
		}

		if _, ok := assigned[tokenID]; ok {
			// This config already has an agent_type assigned; duplicate the row
			var id, name, url, apiKey, model string
			var createdAt, updatedAt time.Time
			err := db.QueryRow(
				"SELECT id, name, url, api_key, model, created_at, updated_at FROM token_config WHERE id = ?", tokenID,
			).Scan(&id, &name, &url, &apiKey, &model, &createdAt, &updatedAt)
			if err != nil {
				log.Printf("[DB] Migration: failed to read config %s: %v", tokenID, err)
				continue
			}

			newID := uuid.New().String()
			_, err = db.Exec(
				"INSERT INTO token_config (id, name, url, api_key, model, agent_type, is_active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)",
				newID, name+" ("+agentType+")", url, apiKey, model, agentType, createdAt, time.Now(),
			)
			if err == nil {
				db.Exec("UPDATE usage SET token_id = ? WHERE token_id = ? AND agent_type = ?", newID, tokenID, agentType)
				log.Printf("[DB] Migration: duplicated config %s -> %s for agent_type=%s", tokenID, newID, agentType)
			}
		} else {
			// First agent_type for this config; update in place
			db.Exec("UPDATE token_config SET agent_type = ?, is_active = 1 WHERE id = ?", agentType, tokenID)
			assigned[tokenID] = agentType
			log.Printf("[DB] Migration: set config %s agent_type=%s, is_active=1", tokenID, agentType)
		}
	}

	// Assign default agent_type to configs without one
	db.Exec("UPDATE token_config SET agent_type = 'claude_code' WHERE agent_type = ''")

	// Drop the old table
	db.Exec("DROP TABLE IF EXISTS valid_config")
	log.Printf("[DB] Migration from valid_config complete")
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
		AgentType: req.AgentType,
		IsActive:  false,
		CreatedAt: now,
		UpdatedAt: now,
	}
	log.Printf("[DB] Creating token config: id=%s, name=%s, agent_type=%s", c.ID, c.Name, c.AgentType)
	_, err := db.Exec(
		"INSERT INTO token_config (id, name, url, api_key, model, agent_type, is_active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
		c.ID, c.Name, c.URL, c.APIKey, c.Model, c.AgentType, boolToInt(c.IsActive), c.CreatedAt, c.UpdatedAt,
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
	var isActive int
	err := db.QueryRow(
		"SELECT id, name, url, api_key, model, agent_type, is_active, created_at, updated_at FROM token_config WHERE id = ?",
		id,
	).Scan(&c.ID, &c.Name, &c.URL, &c.APIKey, &c.Model, &c.AgentType, &isActive, &c.CreatedAt, &c.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	c.IsActive = isActive == 1
	return c, err
}

func (db *DB) ListTokenConfigs() ([]*model.TokenConfig, error) {
	rows, err := db.Query("SELECT id, name, url, api_key, model, agent_type, is_active, created_at, updated_at FROM token_config ORDER BY created_at")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanTokenConfigs(rows)
}

func (db *DB) ListTokenConfigsByAgentType(agentType string) ([]*model.TokenConfig, error) {
	rows, err := db.Query("SELECT id, name, url, api_key, model, agent_type, is_active, created_at, updated_at FROM token_config WHERE agent_type = ? ORDER BY created_at", agentType)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanTokenConfigs(rows)
}

func scanTokenConfigs(rows *sql.Rows) ([]*model.TokenConfig, error) {
	var configs []*model.TokenConfig
	for rows.Next() {
		c := &model.TokenConfig{}
		var isActive int
		if err := rows.Scan(&c.ID, &c.Name, &c.URL, &c.APIKey, &c.Model, &c.AgentType, &isActive, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		c.IsActive = isActive == 1
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

// --- Active config methods ---

func (db *DB) GetActiveTokenConfigByAgentType(agentType string) (*model.TokenConfig, error) {
	c := &model.TokenConfig{}
	var isActive int
	err := db.QueryRow(
		"SELECT id, name, url, api_key, model, agent_type, is_active, created_at, updated_at FROM token_config WHERE agent_type = ? AND is_active = 1",
		agentType,
	).Scan(&c.ID, &c.Name, &c.URL, &c.APIKey, &c.Model, &c.AgentType, &isActive, &c.CreatedAt, &c.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	c.IsActive = isActive == 1
	return c, err
}

func (db *DB) ListActiveTokenConfigs() ([]*model.TokenConfig, error) {
	rows, err := db.Query("SELECT id, name, url, api_key, model, agent_type, is_active, created_at, updated_at FROM token_config WHERE is_active = 1")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanTokenConfigs(rows)
}

func (db *DB) ActivateTokenConfig(tokenID string) (activated *model.TokenConfig, deactivated *model.TokenConfig, err error) {
	log.Printf("[DB] Activating token config: token_id=%s", tokenID)

	// Read the target config
	activated, err = db.GetTokenConfig(tokenID)
	if err != nil {
		return nil, nil, fmt.Errorf("get config: %w", err)
	}
	if activated == nil {
		return nil, nil, fmt.Errorf("config not found")
	}

	tx, err := db.Begin()
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback()

	// Find currently active config for the same agent_type
	var deactID, deactName, deactURL, deactAPIKey, deactModel, deactAgentType string
	var deactIsActive int
	var deactCreatedAt, deactUpdatedAt time.Time
	err = tx.QueryRow(
		"SELECT id, name, url, api_key, model, agent_type, is_active, created_at, updated_at FROM token_config WHERE agent_type = ? AND is_active = 1 AND id != ?",
		activated.AgentType, tokenID,
	).Scan(&deactID, &deactName, &deactURL, &deactAPIKey, &deactModel, &deactAgentType, &deactIsActive, &deactCreatedAt, &deactUpdatedAt)
	if err == nil {
		deactivated = &model.TokenConfig{
			ID:        deactID,
			Name:      deactName,
			URL:       deactURL,
			APIKey:    deactAPIKey,
			Model:     deactModel,
			AgentType: deactAgentType,
			IsActive:  deactIsActive == 1,
			CreatedAt: deactCreatedAt,
			UpdatedAt: deactUpdatedAt,
		}
		_, err = tx.Exec("UPDATE token_config SET is_active = 0 WHERE agent_type = ? AND is_active = 1 AND id != ?", activated.AgentType, tokenID)
		if err != nil {
			return nil, nil, fmt.Errorf("deactivate old: %w", err)
		}
	}

	// Activate the target
	_, err = tx.Exec("UPDATE token_config SET is_active = 1 WHERE id = ?", tokenID)
	if err != nil {
		return nil, nil, fmt.Errorf("activate target: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, nil, fmt.Errorf("commit: %w", err)
	}

	activated.IsActive = true
	log.Printf("[DB] Config activated: token_id=%s, agent_type=%s, deactivated_old=%v", tokenID, activated.AgentType, deactivated != nil)
	return activated, deactivated, nil
}

func (db *DB) DeactivateTokenConfig(tokenID string) (*model.TokenConfig, error) {
	log.Printf("[DB] Deactivating token config: token_id=%s", tokenID)

	c, err := db.GetTokenConfig(tokenID)
	if err != nil {
		return nil, err
	}
	if c == nil {
		return nil, fmt.Errorf("config not found")
	}

	_, err = db.Exec("UPDATE token_config SET is_active = 0 WHERE id = ?", tokenID)
	if err != nil {
		log.Printf("[DB] Deactivate config failed: %v", err)
		return nil, err
	}

	c.IsActive = false
	log.Printf("[DB] Config deactivated: token_id=%s, agent_type=%s", tokenID, c.AgentType)
	return c, nil
}

// --- Usage ---

func (db *DB) RecordUsage(tokenID, agentType string, latencyMs int64, inputTokens, outputTokens int) error {
	log.Printf("[DB] Recording usage: token_id=%s, agent=%s, latency=%dms, input=%d, output=%d",
		tokenID, agentType, latencyMs, inputTokens, outputTokens)
	_, err := db.Exec(
		"INSERT INTO usage (id, token_id, agent_type, input_tokens, output_tokens, latency_ms, model, request_path, created_at, created_at_ts) VALUES (?, ?, ?, ?, ?, ?, '', '', ?, ?)",
		uuid.New().String(), tokenID, agentType, inputTokens, outputTokens, latencyMs, time.Now(), time.Now().UnixMilli(),
	)
	if err != nil {
		log.Printf("[DB] Record usage failed: %v", err)
	}
	return err
}

func (db *DB) GetUsages(tokenID string, days int) ([]*model.Usage, error) {
	sinceMs := time.Now().AddDate(0, 0, -days).UnixMilli()
	rows, err := db.Query(
		"SELECT id, token_id, agent_type, input_tokens, output_tokens, latency_ms, model, request_path, created_at_ts FROM usage WHERE token_id = ? AND created_at_ts >= ? ORDER BY created_at_ts ASC",
		tokenID, sinceMs,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var usages []*model.Usage
	for rows.Next() {
		u := &model.Usage{}
		if err := rows.Scan(&u.ID, &u.TokenID, &u.AgentType, &u.InputTokens, &u.OutputTokens, &u.LatencyMs, &u.Model, &u.RequestPath, &u.CreatedAtTs); err != nil {
			return nil, err
		}
		usages = append(usages, u)
	}
	return usages, rows.Err()
}

func (db *DB) GetUsagesAfter(tokenID string, afterTs int64) ([]*model.Usage, error) {
	rows, err := db.Query(
		"SELECT id, token_id, agent_type, input_tokens, output_tokens, latency_ms, model, request_path, created_at_ts FROM usage WHERE token_id = ? AND created_at_ts > ? ORDER BY created_at_ts ASC",
		tokenID, afterTs,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var usages []*model.Usage
	for rows.Next() {
		u := &model.Usage{}
		if err := rows.Scan(&u.ID, &u.TokenID, &u.AgentType, &u.InputTokens, &u.OutputTokens, &u.LatencyMs, &u.Model, &u.RequestPath, &u.CreatedAtTs); err != nil {
			return nil, err
		}
		usages = append(usages, u)
	}
	return usages, rows.Err()
}

func (db *DB) CleanupOldUsage(retainDays int) error {
	cutoffMs := time.Now().AddDate(0, 0, -retainDays).UnixMilli()
	_, err := db.Exec("DELETE FROM usage WHERE created_at_ts < ?", cutoffMs)
	return err
}

func (db *DB) GetUsage(tokenID string) (*model.UsageResponse, error) {
	resp := &model.UsageResponse{
		TokenID: tokenID,
		ByAgent: make(map[string]*model.AgentUsage),
	}

	err := db.QueryRow(
		"SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COUNT(*), COALESCE(AVG(latency_ms),0) FROM usage WHERE token_id = ?",
		tokenID,
	).Scan(&resp.TotalInputTokens, &resp.TotalOutputTokens, &resp.RecordsCount, &resp.AvgLatencyMs)
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
		`SELECT COALESCE(DATE(datetime(created_at_ts/1000, 'unixepoch')), ''), agent_type, SUM(input_tokens), SUM(output_tokens), COUNT(*)
		 FROM usage WHERE token_id = ? GROUP BY DATE(datetime(created_at_ts/1000, 'unixepoch')), agent_type ORDER BY DATE(datetime(created_at_ts/1000, 'unixepoch')) DESC`,
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
	if err := dailyRows.Err(); err != nil {
		return nil, err
	}

	var latestTs int64
	err = db.QueryRow(
		"SELECT COALESCE(MAX(created_at_ts), 0) FROM usage WHERE token_id = ?",
		tokenID,
	).Scan(&latestTs)
	if err == nil && latestTs > 0 {
		resp.LatestCreatedAtTs = latestTs
	}

	return resp, nil
}

func (db *DB) GetUsageSummary(tokenID string) (inputTokens, outputTokens int, err error) {
	err = db.QueryRow(
		"SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0) FROM usage WHERE token_id = ?",
		tokenID,
	).Scan(&inputTokens, &outputTokens)
	return
}

// FindConfigByURLAndKey returns the config matching url+apiKey with the most recent usage, filtered by agent_type.
func (db *DB) FindConfigByURLAndKey(url, apiKey, agentType string) (*model.TokenConfig, error) {
	c := &model.TokenConfig{}
	var isActive int
	query := `
		SELECT tc.id, tc.name, tc.url, tc.api_key, tc.model, tc.agent_type, tc.is_active, tc.created_at, tc.updated_at
		FROM token_config tc
		LEFT JOIN (
			SELECT token_id, MAX(created_at_ts) AS last_used FROM usage GROUP BY token_id
		) u ON tc.id = u.token_id
		WHERE tc.url = ? AND tc.api_key = ?`
	args := []interface{}{url, apiKey}

	if agentType != "" {
		query += ` AND tc.agent_type = ?`
		args = append(args, agentType)
	}

	query += ` ORDER BY COALESCE(u.last_used, 0) DESC, tc.updated_at DESC LIMIT 1`

	err := db.QueryRow(query, args...).Scan(&c.ID, &c.Name, &c.URL, &c.APIKey, &c.Model, &c.AgentType, &isActive, &c.CreatedAt, &c.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	c.IsActive = isActive == 1
	return c, err
}

// FindMostRecentlyUsedConfig returns the config with the most recent usage, filtered by agent_type.
func (db *DB) FindMostRecentlyUsedConfig(agentType string) (*model.TokenConfig, error) {
	c := &model.TokenConfig{}
	var isActive int
	query := `
		SELECT tc.id, tc.name, tc.url, tc.api_key, tc.model, tc.agent_type, tc.is_active, tc.created_at, tc.updated_at
		FROM token_config tc
		LEFT JOIN (
			SELECT token_id, MAX(created_at_ts) AS last_used FROM usage GROUP BY token_id
		) u ON tc.id = u.token_id`
	args := []interface{}{}

	if agentType != "" {
		query += ` WHERE tc.agent_type = ?`
		args = append(args, agentType)
	}

	query += ` ORDER BY COALESCE(u.last_used, 0) DESC, tc.updated_at DESC LIMIT 1`

	err := db.QueryRow(query, args...).Scan(&c.ID, &c.Name, &c.URL, &c.APIKey, &c.Model, &c.AgentType, &isActive, &c.CreatedAt, &c.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	c.IsActive = isActive == 1
	return c, err
}

// ImportExistingConfig creates a config and activates it for claude_code.
func (db *DB) ImportExistingConfig(name, url, apiKey, modelStr string) error {
	log.Printf("[DB] Importing existing config: name=%s, url=%s", name, url)
	c, err := db.CreateTokenConfig(&model.CreateConfigRequest{
		Name:      name,
		URL:       url,
		APIKey:    apiKey,
		Model:     modelStr,
		AgentType: "claude_code",
	})
	if err != nil {
		log.Printf("[DB] Import existing config failed: %v", err)
		return err
	}
	if _, _, err := db.ActivateTokenConfig(c.ID); err != nil {
		log.Printf("[DB] Activate imported config failed: %v", err)
		return err
	}
	log.Printf("[DB] Import existing config success: id=%s", c.ID)
	return nil
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
