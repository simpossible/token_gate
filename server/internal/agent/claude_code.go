package agent

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"

	"token_gate/internal/model"
	"token_gate/internal/util"
)

type ClaudeCodeProcessor struct {
	mu sync.Mutex
}

func NewClaudeCodeProcessor() *ClaudeCodeProcessor {
	return &ClaudeCodeProcessor{}
}

func (p *ClaudeCodeProcessor) GetType() string { return "claude_code" }
func (p *ClaudeCodeProcessor) GetLabel() string { return "Claude Code" }

func (p *ClaudeCodeProcessor) OnActivate(config *model.TokenConfig) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	log.Printf("[AGENT] ClaudeCode OnActivate: config_id=%s, config_name=%s", config.ID, config.Name)

	home := util.RealHomeDir
	settingsPath := filepath.Join(home, ".claude", "settings.json")
	if err := p.updateSettings(settingsPath, map[string]string{
		"ANTHROPIC_BASE_URL":   "http://127.0.0.1:12121/claude_code",
		"ANTHROPIC_API_KEY":    "placeholder",
		"ANTHROPIC_AUTH_TOKEN": config.APIKey,
	}); err != nil {
		log.Printf("[AGENT] ClaudeCode OnActivate error: %v", err)
		return err
	}

	log.Printf("[AGENT] ClaudeCode OnActivate success: settings updated")
	return nil
}

func (p *ClaudeCodeProcessor) OnDeactivate(config *model.TokenConfig) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	log.Printf("[AGENT] ClaudeCode OnDeactivate: config_id=%s, config_name=%s", config.ID, config.Name)

	home := util.RealHomeDir
	settingsPath := filepath.Join(home, ".claude", "settings.json")
	if err := p.restoreSettings(settingsPath, config); err != nil {
		log.Printf("[AGENT] ClaudeCode OnDeactivate error: %v", err)
		return err
	}

	log.Printf("[AGENT] ClaudeCode OnDeactivate success: settings restored")
	return nil
}

func (p *ClaudeCodeProcessor) restoreSettings(path string, config *model.TokenConfig) error {
	log.Printf("[AGENT] restoreSettings: reading %s", path)
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("read settings: %w", err)
	}

	settings := make(map[string]interface{})
	if data != nil {
		if err := json.Unmarshal(data, &settings); err != nil {
			return fmt.Errorf("parse settings: %w", err)
		}
	}

	env, ok := settings["env"].(map[string]interface{})
	if !ok {
		env = make(map[string]interface{})
	}
	env["ANTHROPIC_AUTH_TOKEN"] = config.APIKey
	env["ANTHROPIC_BASE_URL"] = config.URL
	delete(env, "ANTHROPIC_API_KEY")
	settings["env"] = env
	settings["model"] = config.Model

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("create dir: %w", err)
	}

	out, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal settings: %w", err)
	}

	if err := os.WriteFile(path, out, 0644); err != nil {
		return fmt.Errorf("write settings: %w", err)
	}

	log.Printf("[AGENT] restoreSettings: successfully wrote %s", path)
	return nil
}

func (p *ClaudeCodeProcessor) updateSettings(path string, envVars map[string]string) error {
	log.Printf("[AGENT] updateSettings: reading %s", path)
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("read settings: %w", err)
	}

	settings := make(map[string]interface{})
	if data != nil {
		if err := json.Unmarshal(data, &settings); err != nil {
			return fmt.Errorf("parse settings: %w", err)
		}
	}

	env, ok := settings["env"].(map[string]interface{})
	if !ok {
		env = make(map[string]interface{})
	}
	for k, v := range envVars {
		env[k] = v
		log.Printf("[AGENT] updateSettings: setting env[%s] = %s", k, v)
	}
	settings["env"] = env

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("create dir: %w", err)
	}

	out, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal settings: %w", err)
	}

	if err := os.WriteFile(path, out, 0644); err != nil {
		return fmt.Errorf("write settings: %w", err)
	}

	log.Printf("[AGENT] updateSettings: successfully wrote %s", path)
	return nil
}
