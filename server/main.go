package main

import (
	"encoding/json"
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
	log.Println("=== Token Gate Starting ===")

	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("get home dir: %v", err)
	}

	dataDir := filepath.Join(home, ".token_gate")
	webDir := filepath.Join(dataDir, "web")
	dbPath := filepath.Join(dataDir, "token_gate.db")

	log.Printf("[MAIN] Data directory: %s", dataDir)
	log.Printf("[MAIN] Database path: %s", dbPath)

	// 1. Create data directory
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Fatalf("create data dir: %v", err)
	}
	log.Println("[MAIN] Data directory ready")

	// 2. Initialize database
	log.Println("[MAIN] Opening database...")
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
	log.Println("[MAIN] Extracting web files...")
	if err := web.ExtractWebFiles(webDir); err != nil {
		log.Printf("[MAIN] warning: extract web files: %v", err)
	} else {
		log.Println("[MAIN] Web files extracted")
	}

	// 4. Register agent processors
	processors := []agent.AgentProcessor{
		agent.NewClaudeCodeProcessor(),
	}
	log.Printf("[MAIN] Registered %d agent processors", len(processors))

	// 5. Load memory cache
	log.Println("[MAIN] Loading active config cache...")
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
		log.Println("[MAIN] Database is empty, importing existing Claude Code config...")
		importExistingConfig(db, cache, processors)
	} else {
		log.Println("[MAIN] Database already populated, skipping auto-import")
	}

	// 7. Start servers
	log.Println("=== Starting Servers ===")
	proxyHandler := proxy.NewProxy(cache, db)
	apiHandler := api.NewAPI(db, cache, processors)

	go func() {
		log.Println("[SERVER] API Proxy starting on http://127.0.0.1:12121")
		if err := http.ListenAndServe("127.0.0.1:12121", proxyHandler); err != nil {
			log.Fatalf("proxy server: %v", err)
		}
	}()

	go func() {
		log.Println("[SERVER] Config API starting on http://127.0.0.1:12122")
		if err := http.ListenAndServe("127.0.0.1:12122", apiHandler.Routes()); err != nil {
			log.Fatalf("api server: %v", err)
		}
	}()

	log.Println("[SERVER] Web GUI starting on http://127.0.0.1:12123")
	log.Println("=== Token Gate Ready ===")
	if err := http.ListenAndServe("127.0.0.1:12123", web.Handler()); err != nil {
		log.Fatalf("web server: %v", err)
	}
}

func importExistingConfig(db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor) {
	home, _ := os.UserHomeDir()
	settingsPath := filepath.Join(home, ".claude", "settings.json")
	log.Printf("[MAIN] Checking for existing Claude Code config at: %s", settingsPath)

	data, err := os.ReadFile(settingsPath)
	if err != nil {
		log.Printf("[MAIN] No existing settings file found, skipping import")
		return
	}

	var settings map[string]interface{}
	if err := json.Unmarshal(data, &settings); err != nil {
		log.Printf("[MAIN] Failed to parse settings file: %v", err)
		return
	}

	env, ok := settings["env"].(map[string]interface{})
	if !ok {
		log.Printf("[MAIN] No env section in settings file")
		return
	}

	// ANTHROPIC_AUTH_TOKEN takes priority; skip "placeholder" written by token_gate itself
	apiKey := ""
	if v, ok := env["ANTHROPIC_AUTH_TOKEN"].(string); ok && v != "" && v != "placeholder" {
		apiKey = v
		log.Printf("[MAIN] Found ANTHROPIC_AUTH_TOKEN in settings")
	}
	if apiKey == "" {
		if v, ok := env["ANTHROPIC_API_KEY"].(string); ok && v != "" && v != "placeholder" {
			apiKey = v
			log.Printf("[MAIN] Found ANTHROPIC_API_KEY in settings")
		}
	}
	if apiKey == "" {
		log.Printf("[MAIN] No valid API key found in settings, skipping import")
		return
	}

	// Skip base URL if it's already the token_gate proxy (set by a previous OnActivate)
	baseURL := "https://api.anthropic.com"
	if v, ok := env["ANTHROPIC_BASE_URL"].(string); ok && v != "" && v != "http://127.0.0.1:12121/claude_code" {
		baseURL = v
		log.Printf("[MAIN] Found custom base URL: %s", baseURL)
	} else if v == "http://127.0.0.1:12121/claude_code" {
		log.Printf("[MAIN] Base URL already points to token_gate proxy, using default")
	}

	modelStr := "claude-sonnet-4-6"

	log.Printf("[MAIN] Importing config: name=default, url=%s, model=%s", baseURL, modelStr)
	if err := db.ImportExistingConfig("default", baseURL, apiKey, modelStr); err != nil {
		log.Printf("[MAIN] warning: import existing config: %v", err)
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

	log.Println("[MAIN] Successfully imported existing Claude Code configuration")
}
