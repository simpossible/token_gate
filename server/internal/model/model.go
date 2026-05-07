package model

import "time"

type TokenConfig struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	URL       string    `json:"url"`
	APIKey    string    `json:"api_key"`
	Model     string    `json:"model"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (c *TokenConfig) MaskedAPIKey() string {
	k := c.APIKey
	if len(k) <= 8 {
		return "****"
	}
	return k[:4] + "***" + k[len(k)-4:]
}

type ValidConfig struct {
	ID        string    `json:"id"`
	TokenID   string    `json:"token_id"`
	AgentType string    `json:"agent_type"`
	CreatedAt time.Time `json:"created_at"`
}

type Usage struct {
	ID           string    `json:"id"`
	TokenID      string    `json:"token_id"`
	AgentType    string    `json:"agent_type"`
	InputTokens  int       `json:"input_tokens"`
	OutputTokens int       `json:"output_tokens"`
	Model        string    `json:"model"`
	RequestPath  string    `json:"request_path"`
	CreatedAt    time.Time `json:"created_at"`
}

type ConfigWithAgents struct {
	TokenConfig
	ActiveAgents []string `json:"active_agents"`
}

type AgentInfo struct {
	Type             string  `json:"type"`
	Label            string  `json:"label"`
	ActiveConfigID   *string `json:"active_config_id"`
	ActiveConfigName *string `json:"active_config_name"`
}

type CreateConfigRequest struct {
	Name   string `json:"name"`
	URL    string `json:"url"`
	APIKey string `json:"api_key"`
	Model  string `json:"model"`
}

type UpdateConfigRequest struct {
	Name   *string `json:"name"`
	URL    *string `json:"url"`
	APIKey *string `json:"api_key"`
	Model  *string `json:"model"`
}

type ActivateRequest struct {
	AgentType string `json:"agent_type"`
}

type UsageResponse struct {
	TokenID          string                    `json:"token_id"`
	TotalInputTokens int                       `json:"total_input_tokens"`
	TotalOutputTokens int                      `json:"total_output_tokens"`
	RecordsCount     int                       `json:"records_count"`
	ByAgent          map[string]*AgentUsage    `json:"by_agent"`
	DailyUsage       []DailyUsage              `json:"daily_usage"`
}

type AgentUsage struct {
	InputTokens  int `json:"input_tokens"`
	OutputTokens int `json:"output_tokens"`
	Requests     int `json:"requests"`
}

type DailyUsage struct {
	Date         string `json:"date"`
	InputTokens  int    `json:"input_tokens"`
	OutputTokens int    `json:"output_tokens"`
	Requests     int    `json:"requests"`
	AgentType    string `json:"agent_type"`
}
