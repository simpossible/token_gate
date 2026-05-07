package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"token_gate/internal/agent"
	"token_gate/internal/api"
	"token_gate/internal/config"
	"token_gate/internal/database"
	"token_gate/internal/proxy"
	"token_gate/internal/web"
)

func main() {
	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("get home dir: %v", err)
	}

	dataDir := filepath.Join(home, ".token_gate")
	webDir := filepath.Join(dataDir, "web")
	dbPath := filepath.Join(dataDir, "token_gate.db")

	// 1. Create data directory
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Fatalf("create data dir: %v", err)
	}

	// 2. Initialize database
	db, err := database.Open(dbPath)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer db.Close()

	if err := db.InitSchema(); err != nil {
		log.Fatalf("init schema: %v", err)
	}

	// 3. Extract web resources
	if err := os.MkdirAll(webDir, 0755); err != nil {
		log.Fatalf("create web dir: %v", err)
	}
	if err := web.ExtractWebFiles(webDir); err != nil {
		log.Printf("warning: extract web files: %v", err)
	}

	// 4. Register agent processors
	processors := []agent.AgentProcessor{
		agent.NewClaudeCodeProcessor(),
	}

	// 5. Load memory cache
	cache := config.NewCache(db)
	if err := cache.Load(); err != nil {
		log.Fatalf("load cache: %v", err)
	}

	// 6. Scan existing config on first run
	isEmpty, err := db.IsEmpty()
	if err != nil {
		log.Fatalf("check db: %v", err)
	}
	if isEmpty {
		importExistingConfig(db, cache, processors)
	}

	// 7. Start servers
	proxyHandler := proxy.NewProxy(cache, db)
	apiHandler := api.NewAPI(db, cache, processors)

	go func() {
		log.Println("API Proxy listening on http://127.0.0.1:12121")
		if err := http.ListenAndServe("127.0.0.1:12121", proxyHandler); err != nil {
			log.Fatalf("proxy server: %v", err)
		}
	}()

	go func() {
		log.Println("Config API listening on http://127.0.0.1:12122")
		if err := http.ListenAndServe("127.0.0.1:12122", apiHandler.Routes()); err != nil {
			log.Fatalf("api server: %v", err)
		}
	}()

	log.Println("Web GUI listening on http://127.0.0.1:12123")
	if err := http.ListenAndServe("127.0.0.1:12123", web.Handler()); err != nil {
		log.Fatalf("web server: %v", err)
	}
}

func importExistingConfig(db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor) {
	home, _ := os.UserHomeDir()
	settingsPath := filepath.Join(home, ".claude", "settings.json")
	data, err := os.ReadFile(settingsPath)
	if err != nil {
		return
	}

	var settings map[string]interface{}
	if err := json.Unmarshal(data, &settings); err != nil {
		return
	}

	env, ok := settings["env"].(map[string]interface{})
	if !ok {
		return
	}

	// ANTHROPIC_AUTH_TOKEN takes priority; skip "placeholder" written by token_gate itself
	apiKey := ""
	if v, ok := env["ANTHROPIC_AUTH_TOKEN"].(string); ok && v != "" && v != "placeholder" {
		apiKey = v
	}
	if apiKey == "" {
		if v, ok := env["ANTHROPIC_API_KEY"].(string); ok && v != "" && v != "placeholder" {
			apiKey = v
		}
	}
	if apiKey == "" {
		return
	}

	// Skip base URL if it's already the token_gate proxy (set by a previous OnActivate)
	baseURL := "https://api.anthropic.com"
	if v, ok := env["ANTHROPIC_BASE_URL"].(string); ok && v != "" && v != "http://127.0.0.1:12121/claude_code" {
		baseURL = v
	}

	modelStr := "claude-sonnet-4-6"

	if err := db.ImportExistingConfig("default", baseURL, apiKey, modelStr); err != nil {
		log.Printf("warning: import existing config: %v", err)
		return
	}

	// Reload cache after import
	cache.Load()

	// Trigger OnActivate for claude_code
	for _, p := range processors {
		if p.GetType() == "claude_code" {
			vc, _ := db.GetActiveConfig("claude_code")
			if vc != nil {
				tc, _ := db.GetTokenConfig(vc.TokenID)
				if tc != nil {
					p.OnActivate(tc)
				}
			}
		}
	}

	fmt.Println("Imported existing Claude Code configuration")
}
