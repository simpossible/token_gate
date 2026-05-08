package latency

import "sync"

type Cache struct {
	mu   sync.RWMutex
	data map[string]int64
}

func New() *Cache {
	return &Cache{data: make(map[string]int64)}
}

func (c *Cache) Set(tokenID string, ms int64) {
	c.mu.Lock()
	c.data[tokenID] = ms
	c.mu.Unlock()
}

func (c *Cache) Get(tokenID string) (int64, bool) {
	c.mu.RLock()
	ms, ok := c.data[tokenID]
	c.mu.RUnlock()
	return ms, ok
}
