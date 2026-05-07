package config

import (
	"log"
	"sync"

	"token_gate/internal/database"
	"token_gate/internal/model"
)

type ActiveConfigCache struct {
	mu      sync.RWMutex
	configs map[string]*model.TokenConfig // key = agent_type
	db      *database.DB
}

func NewCache(db *database.DB) *ActiveConfigCache {
	return &ActiveConfigCache{
		configs: make(map[string]*model.TokenConfig),
		db:      db,
	}
}

func (c *ActiveConfigCache) Load() error {
	log.Printf("[CACHE] Loading active configs from database")
	validConfigs, err := c.db.ListActiveConfigs()
	if err != nil {
		log.Printf("[CACHE] Load failed: %v", err)
		return err
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	c.configs = make(map[string]*model.TokenConfig)
	for _, vc := range validConfigs {
		tc, err := c.db.GetTokenConfig(vc.TokenID)
		if err != nil || tc == nil {
			log.Printf("[CACHE] Warning: could not load config for token_id=%s, agent_type=%s", vc.TokenID, vc.AgentType)
			continue
		}
		c.configs[vc.AgentType] = tc
		log.Printf("[CACHE] Loaded: agent_type=%s -> config_id=%s, config_name=%s", vc.AgentType, tc.ID, tc.Name)
	}
	log.Printf("[CACHE] Load complete: %d active configs", len(c.configs))
	return nil
}

func (c *ActiveConfigCache) Get(agentType string) *model.TokenConfig {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.configs[agentType]
}

func (c *ActiveConfigCache) Set(agentType string, config *model.TokenConfig) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.configs[agentType] = config
	log.Printf("[CACHE] Set: agent_type=%s -> config_id=%s, config_name=%s", agentType, config.ID, config.Name)
}

func (c *ActiveConfigCache) Remove(agentType string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, exists := c.configs[agentType]; exists {
		delete(c.configs, agentType)
		log.Printf("[CACHE] Removed: agent_type=%s", agentType)
	}
}
