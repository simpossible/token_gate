package company

import (
	_ "embed"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"time"

	"token_gate/internal/database"
)

//go:embed company.json
var defaultData []byte

const githubRawURL = "https://github.com/simpossible/token_gate/raw/refs/heads/master/server/internal/company/company.json"

type Company struct {
	Name   string   `json:"name"`
	URL    string   `json:"url"`
	Models []string `json:"models"`
}

type CompanyList struct {
	List []Company `json:"list"`
}

type Manager struct {
	mu      sync.RWMutex
	data    *CompanyList
	dataDir string
	db      *database.DB
}

func NewManager(dataDir string, db *database.DB) *Manager {
	m := &Manager{dataDir: dataDir, db: db}
	m.load()
	return m
}

func (m *Manager) diskPath() string {
	return filepath.Join(m.dataDir, "company.json")
}

func (m *Manager) load() {
	if b, err := os.ReadFile(m.diskPath()); err == nil {
		var cl CompanyList
		if err := json.Unmarshal(b, &cl); err == nil && len(cl.List) > 0 {
			m.mu.Lock()
			m.data = &cl
			m.mu.Unlock()
			log.Printf("[COMPANY] loaded from disk: %d companies", len(cl.List))
			return
		}
	}
	var cl CompanyList
	if err := json.Unmarshal(defaultData, &cl); err == nil {
		m.mu.Lock()
		m.data = &cl
		m.mu.Unlock()
		log.Printf("[COMPANY] loaded from embedded default: %d companies", len(cl.List))
	}
}

func (m *Manager) Get() *CompanyList {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.data
}

func (m *Manager) RefreshAsync() {
	go m.refresh()
}

func (m *Manager) refresh() {
	client := &http.Client{Timeout: 15 * time.Second}

	if m.db != nil {
		cfg, err := m.db.GetProxyConfig()
		if err == nil && cfg.Enabled && cfg.Host != "" && cfg.Port != "" {
			if proxyURL, err := url.Parse("http://" + cfg.Host + ":" + cfg.Port); err == nil {
				client.Transport = &http.Transport{Proxy: http.ProxyURL(proxyURL)}
			}
		}
	}

	resp, err := client.Get(githubRawURL)
	if err != nil {
		log.Printf("[COMPANY] refresh failed: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("[COMPANY] refresh failed: HTTP %d", resp.StatusCode)
		return
	}

	b, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("[COMPANY] refresh read failed: %v", err)
		return
	}

	var cl CompanyList
	if err := json.Unmarshal(b, &cl); err != nil {
		log.Printf("[COMPANY] refresh parse failed: %v", err)
		return
	}
	if len(cl.List) == 0 {
		log.Printf("[COMPANY] refresh skipped: empty list from remote")
		return
	}

	if err := os.WriteFile(m.diskPath(), b, 0644); err != nil {
		log.Printf("[COMPANY] refresh save to disk failed: %v", err)
	}

	m.mu.Lock()
	m.data = &cl
	m.mu.Unlock()
	log.Printf("[COMPANY] refresh success: %d companies", len(cl.List))
}
