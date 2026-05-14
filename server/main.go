package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"gopkg.in/natefinch/lumberjack.v2"
	"token_gate/internal/agent"
	"token_gate/internal/api"
	"token_gate/internal/company"
	"token_gate/internal/config"
	"token_gate/internal/database"
	"token_gate/internal/event"
	"token_gate/internal/latency"
	"token_gate/internal/model"
	"token_gate/internal/proxy"
	"token_gate/internal/util"
)

var buildID = "dev"

func main() {
	cmd := "start"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}

	switch cmd {
	case "start":
		cmdStart()
	case "stop":
		cmdStop()
	case "show":
		cmdShow()
	case "status":
		cmdStatus()
	case "server":
		// foreground mode for brew services / launchd
		runForeground()
	case "debug":
		// debug mode: run in foreground with stdout logging
		setupLogger(true)
		log.Println("=== Token Gate Starting (debug mode) ===")
		startServers()
	case "--daemon":
		// internal: called by cmdStart, runs in background
		runDaemon()
	default:
		fmt.Fprintf(os.Stderr, "Usage: token_gate [start|stop|show|status|debug]\n")
		os.Exit(1)
	}
}

// --- path helpers ---

func dataDir() string {
	home := util.RealHomeDir
	return filepath.Join(home, ".token_gate")
}

func pidPath() string { return filepath.Join(dataDir(), "token_gate.pid") }
func logPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".token_gate", "logs", "token_gate.log")
}

// --- process helpers ---

func readPID() (int, bool) {
	data, err := os.ReadFile(pidPath())
	if err != nil {
		return 0, false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return 0, false
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return 0, false
	}
	if !isProcessAlive(proc) {
		return 0, false
	}
	return pid, true
}

func portListening() bool {
	resp, err := http.Get("http://127.0.0.1:12122/api/agents")
	if err != nil {
		return false
	}
	resp.Body.Close()
	return true
}

// --- commands ---

func cmdStart() {
	if pid, ok := readPID(); ok {
		fmt.Printf("Token Gate is already running (pid %d)\n", pid)
		return
	}
	if portListening() {
		fmt.Println("Token Gate is already running (managed by brew services)")
		return
	}

	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	cmd := exec.Command(exe, "--daemon")
	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil
	setDaemonProcess(cmd)
	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "failed to start: %v\n", err)
		os.Exit(1)
	}

	fmt.Print("Starting Token Gate")
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(500 * time.Millisecond)
		fmt.Print(".")
		if portListening() {
			fmt.Println(" ready!")
			break
		}
	}
	if !portListening() {
		fmt.Printf("\nTimed out. Check logs: %s\n", logPath())
		os.Exit(1)
	}

	fmt.Printf("Logs: %s\n", logPath())
}

func cmdStop() {
	pid, ok := readPID()
	if !ok {
		if portListening() {
			fmt.Println("Token Gate is running (managed by brew services).")
			fmt.Println("Use: brew services stop token_gate")
		} else {
			fmt.Println("Token Gate is not running")
		}
		return
	}

	proc, _ := os.FindProcess(pid)
	if err := terminateProcess(proc); err != nil {
		fmt.Fprintf(os.Stderr, "error stopping process: %v\n", err)
		os.Exit(1)
	}
	os.Remove(pidPath())

	fmt.Printf("Stopping Token Gate (pid %d)", pid)
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(200 * time.Millisecond)
		if !isProcessAlive(proc) {
			fmt.Println(" stopped")
			return
		}
		fmt.Print(".")
	}
	fmt.Printf("\nProcess %d did not exit within timeout\n", pid)
}

func cmdShow() {
	if portListening() {
		fmt.Println("Token Gate is running")
		return
	}
	fmt.Println("Token Gate is not running, starting...")
	cmdStart()
}

func cmdStatus() {
	if pid, ok := readPID(); ok {
		fmt.Printf("running (pid %d)\n", pid)
		fmt.Printf("API:  http://127.0.0.1:12122\n")
		fmt.Printf("Logs: %s\n", logPath())
		return
	}
	if portListening() {
		fmt.Println("running (managed by brew services)")
		fmt.Printf("API: http://127.0.0.1:12122\n")
		return
	}
	fmt.Println("stopped")
}

// --- server startup ---

func setupLogger(alsoStdout bool) {
	lp := logPath()
	if err := os.MkdirAll(filepath.Dir(lp), 0755); err != nil {
		log.Fatalf("create log dir: %v", err)
	}
	lj := &lumberjack.Logger{
		Filename:   lp,
		MaxSize:    10, // MB
		MaxBackups: 3,
	}
	if alsoStdout {
		log.SetOutput(io.MultiWriter(os.Stdout, lj))
	} else {
		log.SetOutput(lj)
	}
}

func runForeground() {
	setupLogger(true)
	log.Println("=== Token Gate Starting (foreground) ===")
	startServers()
}

func runDaemon() {
	// ensure data dir exists before writing PID
	if err := os.MkdirAll(dataDir(), 0755); err != nil {
		fmt.Fprintf(os.Stderr, "create data dir: %v\n", err)
		os.Exit(1)
	}
	setupLogger(false)

	pp := pidPath()
	if err := os.WriteFile(pp, []byte(strconv.Itoa(os.Getpid())), 0644); err != nil {
		log.Fatalf("write pid file: %v", err)
	}
	defer os.Remove(pp)

	log.Println("=== Token Gate Starting (daemon) ===")
	startServers()
}

func startServers() {
	home := util.RealHomeDir

	dir := filepath.Join(home, ".token_gate")
	dbPath := filepath.Join(dir, "token_gate.db")

	if err := os.MkdirAll(dir, 0755); err != nil {
		log.Fatalf("create data dir: %v", err)
	}

	db, err := database.Open(dbPath)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer db.Close()

	if err := db.InitSchema(); err != nil {
		log.Fatalf("init schema: %v", err)
	}

	processors := []agent.AgentProcessor{
		agent.NewClaudeCodeProcessor(),
		agent.NewCodexProcessor(),
	}

	cache := config.NewCache(db)
	if err := cache.Load(); err != nil {
		log.Fatalf("load cache: %v", err)
	}

	hasActive := false
	for _, p := range processors {
		if tc, _ := db.GetActiveTokenConfigByAgentType(p.GetType()); tc != nil {
			hasActive = true
			break
		}
	}
	if !hasActive {
		restoreOrImportConfig(db, cache, processors)
	}

	latencyCache := latency.New()

	companyMgr := company.NewManager(dir)

	go func() {
		ticker := time.NewTicker(24 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			if err := db.CleanupOldUsage(30); err != nil {
				log.Printf("[MAIN] cleanup old usage failed: %v", err)
			}
		}
	}()

	eventBus := event.NewEventBus()

	proxyHandler := proxy.NewProxy(cache, db, latencyCache, eventBus)
	apiHandler := api.NewAPI(db, cache, processors, latencyCache, companyMgr, eventBus, buildID)

	proxyServer := &http.Server{Addr: "127.0.0.1:12121", Handler: proxyHandler}
	apiServer := &http.Server{Addr: "127.0.0.1:12122", Handler: apiHandler.Routes()}

	go func() {
		sigChan := make(chan os.Signal, 1)
		registerShutdownSignals(sigChan)
		<-sigChan
		log.Println("[MAIN] Shutdown signal received, cleaning up active configs...")
		cleanupAllConfigs(db, cache, processors)
		db.Close()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		proxyServer.Shutdown(ctx)
		apiServer.Shutdown(ctx)
		log.Println("[MAIN] Shutdown complete")
	}()

	go func() {
		log.Println("[SERVER] API Proxy on http://127.0.0.1:12121")
		if err := proxyServer.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("proxy server: %v", err)
		}
	}()

	log.Println("[SERVER] Config API on http://127.0.0.1:12122")
	log.Println("=== Token Gate Ready ===")
	if err := apiServer.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("api server: %v", err)
	}
}

func readClaudeSettings() (apiKey, baseURL, modelStr string) {
	home := util.RealHomeDir
	data, err := os.ReadFile(filepath.Join(home, ".claude", "settings.json"))
	if err != nil {
		return
	}
	var settings map[string]interface{}
	if err := json.Unmarshal(data, &settings); err != nil {
		return
	}
	env, _ := settings["env"].(map[string]interface{})
	if v, ok := env["ANTHROPIC_AUTH_TOKEN"].(string); ok && v != "" && v != "placeholder" {
		apiKey = v
	}
	if apiKey == "" {
		if v, ok := env["ANTHROPIC_API_KEY"].(string); ok && v != "" && v != "placeholder" {
			apiKey = v
		}
	}
	if v, ok := env["ANTHROPIC_BASE_URL"].(string); ok && v != "" {
		baseURL = v
	}
	if v, ok := env["ANTHROPIC_MODEL"].(string); ok && v != "" {
		modelStr = v
	} else if v, ok := settings["model"].(string); ok && v != "" {
		modelStr = v
	}
	if modelStr == "" {
		modelStr = "claude-sonnet-4-6"
	}
	return
}

func activateConfigForProcessors(tc *model.TokenConfig, db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor) {
	// Find the processor matching this config's agent_type
	for _, p := range processors {
		if p.GetType() == tc.AgentType {
			_, _, err := db.ActivateTokenConfig(tc.ID)
			if err != nil {
				log.Printf("[MAIN] activate config failed: agent=%s, error=%v", p.GetType(), err)
				return
			}
			cache.Set(p.GetType(), tc)
			if err := p.OnActivate(tc); err != nil {
				log.Printf("[MAIN] OnActivate failed: agent=%s, error=%v", p.GetType(), err)
			}
			log.Printf("[MAIN] activated config: name=%s, id=%s, agent=%s", tc.Name, tc.ID, p.GetType())
			return
		}
	}
}

func restoreOrImportConfig(db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor) {
	apiKey, baseURL, _ := readClaudeSettings()

	// Detect if settings.json already points to our own proxy (written by token_gate itself)
	isProxyURL := strings.HasPrefix(baseURL, "http://127.0.0.1:12121/")
	hasRealSettings := apiKey != "" && baseURL != "" && !isProxyURL

	var target *model.TokenConfig

	if hasRealSettings {
		tc, err := db.FindConfigByURLAndKey(baseURL, apiKey, "claude_code")
		if err != nil {
			log.Printf("[MAIN] restore: find by url+key error: %v", err)
		}
		if tc != nil {
			log.Printf("[MAIN] restore: found matching config: name=%s, id=%s", tc.Name, tc.ID)
			target = tc
		}
	}

	if target == nil {
		tc, err := db.FindMostRecentlyUsedConfig("claude_code")
		if err != nil {
			log.Printf("[MAIN] restore: find most recent error: %v", err)
		}
		if tc != nil {
			log.Printf("[MAIN] restore: using most recently used config: name=%s, id=%s", tc.Name, tc.ID)
			target = tc
		}
	}

	if target == nil {
		if !hasRealSettings {
			log.Printf("[MAIN] restore: no configs in DB and no valid settings, skipping")
			return
		}
		log.Printf("[MAIN] restore: no existing config found, importing from settings")
		importExistingConfig(db, cache, processors)
		return
	}

	activateConfigForProcessors(target, db, cache, processors)
	cache.Load()
}

func importExistingConfig(db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor) {
	home := util.RealHomeDir
	settingsPath := filepath.Join(home, ".claude", "settings.json")
	log.Printf("[MAIN] Checking for existing Claude Code config at: %s", settingsPath)

	apiKey, baseURL, modelStr := readClaudeSettings()
	if apiKey == "" {
		log.Printf("[MAIN] No valid API key found in settings, skipping import")
		return
	}

	if baseURL == "" || strings.HasPrefix(baseURL, "http://127.0.0.1:12121/") {
		baseURL = "https://open.bigmodel.cn/api/anthropic"
		log.Printf("[MAIN] No valid base URL, using default: %s", baseURL)
	}

	log.Printf("[MAIN] Importing config: url=%s, model=%s", baseURL, modelStr)
	if err := db.ImportExistingConfig("default", baseURL, apiKey, modelStr); err != nil {
		log.Printf("[MAIN] warning: import existing config: %v", err)
		return
	}

	cache.Load()

	for _, p := range processors {
		if p.GetType() == "claude_code" {
			tc, _ := db.GetActiveTokenConfigByAgentType("claude_code")
			if tc != nil {
				p.OnActivate(tc)
			}
		}
	}

	log.Println("[MAIN] Successfully imported existing Claude Code configuration")
}

func cleanupAllConfigs(db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor) {
	activeConfigs, err := db.ListActiveTokenConfigs()
	if err != nil {
		log.Printf("[MAIN] cleanup: failed to list active configs: %v", err)
		return
	}

	if len(activeConfigs) == 0 {
		log.Println("[MAIN] cleanup: no active configs to restore")
		return
	}

	log.Printf("[MAIN] cleanup: found %d active configs to restore", len(activeConfigs))

	processorMap := make(map[string]agent.AgentProcessor)
	for _, p := range processors {
		processorMap[p.GetType()] = p
	}

	var wg sync.WaitGroup
	for _, tc := range activeConfigs {
		wg.Add(1)
		go func(tc *model.TokenConfig) {
			defer wg.Done()
			log.Printf("[MAIN] cleanup: deactivating config for agent_type=%s", tc.AgentType)

			if processor, ok := processorMap[tc.AgentType]; ok {
				if err := processor.OnDeactivate(tc); err != nil {
					log.Printf("[MAIN] cleanup: OnDeactivate failed for agent_type=%s: %v", tc.AgentType, err)
				} else {
					log.Printf("[MAIN] cleanup: successfully restored settings for agent_type=%s", tc.AgentType)
				}
			}

			if _, err := db.DeactivateTokenConfig(tc.ID); err != nil {
				log.Printf("[MAIN] cleanup: failed to deactivate config from DB for agent_type=%s: %v", tc.AgentType, err)
			}

			cache.Remove(tc.AgentType)
		}(tc)
	}
	wg.Wait()

	log.Println("[MAIN] cleanup: all configs deactivated and settings restored")
}
