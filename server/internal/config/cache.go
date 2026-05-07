package config

import (
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
	validConfigs, err := c.db.ListActiveConfigs()
	if err != nil {
		return err
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	c.configs = make(map[string]*model.TokenConfig)
	for _, vc := range validConfigs {
		tc, err := c.db.GetTokenConfig(vc.TokenID)
		if err != nil || tc == nil {
			continue
		}
		c.configs[vc.AgentType] = tc
	}
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
}

func (c *ActiveConfigCache) Remove(agentType string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.configs, agentType)
}
