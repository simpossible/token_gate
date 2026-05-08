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
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"gopkg.in/natefinch/lumberjack.v2"
	"token_gate/internal/agent"
	"token_gate/internal/api"
	"token_gate/internal/config"
	"token_gate/internal/database"
	"token_gate/internal/latency"
	"token_gate/internal/model"
	"token_gate/internal/proxy"
	"token_gate/internal/web"
)

const webURL = "http://127.0.0.1:12123"

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
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".token_gate")
}

func pidPath() string { return filepath.Join(dataDir(), "token_gate.pid") }
func logPath() string { return filepath.Join(dataDir(), "logs", "token_gate.log") }

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
	if err := proc.Signal(syscall.Signal(0)); err != nil {
		return 0, false
	}
	return pid, true
}

func portListening() bool {
	resp, err := http.Get(webURL)
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
		openBrowser(webURL)
		return
	}
	if portListening() {
		fmt.Println("Token Gate is already running (managed by brew services)")
		openBrowser(webURL)
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
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
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

	openBrowser(webURL)
	fmt.Printf("Web: %s\n", webURL)
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
	if err := proc.Signal(syscall.SIGTERM); err != nil {
		fmt.Fprintf(os.Stderr, "error stopping process: %v\n", err)
		os.Exit(1)
	}
	os.Remove(pidPath())

	fmt.Printf("Stopping Token Gate (pid %d)", pid)
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(200 * time.Millisecond)
		if err := proc.Signal(syscall.Signal(0)); err != nil {
			fmt.Println(" stopped")
			return
		}
		fmt.Print(".")
	}
	fmt.Printf("\nProcess %d did not exit within timeout\n", pid)
}

func cmdShow() {
	if portListening() {
		openBrowser(webURL)
		return
	}
	fmt.Println("Token Gate is not running, starting...")
	cmdStart()
}

func cmdStatus() {
	if pid, ok := readPID(); ok {
		fmt.Printf("running (pid %d)\n", pid)
		fmt.Printf("Web:  %s\n", webURL)
		fmt.Printf("Logs: %s\n", logPath())
		return
	}
	if portListening() {
		fmt.Println("running (managed by brew services)")
		fmt.Printf("Web: %s\n", webURL)
		return
	}
	fmt.Println("stopped")
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	default:
		return
	}
	_ = cmd.Start()
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
	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("get home dir: %v", err)
	}

	dir := filepath.Join(home, ".token_gate")
	webDir := filepath.Join(dir, "web")
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

	if err := os.MkdirAll(webDir, 0755); err != nil {
		log.Fatalf("create web dir: %v", err)
	}
	if err := web.ExtractWebFiles(webDir); err != nil {
		log.Printf("warning: extract web files: %v", err)
	}

	processors := []agent.AgentProcessor{
		agent.NewClaudeCodeProcessor(),
	}

	cache := config.NewCache(db)
	if err := cache.Load(); err != nil {
		log.Fatalf("load cache: %v", err)
	}

	isEmpty, err := db.IsEmpty()
	if err != nil {
		log.Fatalf("check db: %v", err)
	}
	if isEmpty {
		importExistingConfig(db, cache, processors)
	}

	latencyCache := latency.New()

	go func() {
		ticker := time.NewTicker(24 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			if err := db.CleanupOldUsage(30); err != nil {
				log.Printf("[MAIN] cleanup old usage failed: %v", err)
			}
		}
	}()

	proxyHandler := proxy.NewProxy(cache, db, latencyCache)
	apiHandler := api.NewAPI(db, cache, processors, latencyCache)

	proxyServer := &http.Server{Addr: "127.0.0.1:12121", Handler: proxyHandler}
	apiServer := &http.Server{Addr: "127.0.0.1:12122", Handler: apiHandler.Routes()}
	webServer := &http.Server{Addr: "127.0.0.1:12123", Handler: web.Handler()}

	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)
		<-sigChan
		log.Println("[MAIN] Shutdown signal received, cleaning up active configs...")
		cleanupAllConfigs(db, cache, processors)
		db.Close()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		proxyServer.Shutdown(ctx)
		apiServer.Shutdown(ctx)
		webServer.Shutdown(ctx)
		log.Println("[MAIN] Shutdown complete")
	}()

	go func() {
		log.Println("[SERVER] API Proxy on http://127.0.0.1:12121")
		if err := proxyServer.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("proxy server: %v", err)
		}
	}()

	go func() {
		log.Println("[SERVER] Config API on http://127.0.0.1:12122")
		if err := apiServer.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("api server: %v", err)
		}
	}()

	log.Println("[SERVER] Web GUI on http://127.0.0.1:12123")
	log.Println("=== Token Gate Ready ===")
	if err := webServer.ListenAndServe(); err != http.ErrServerClosed {
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

	baseURL := "https://open.bigmodel.cn/api/anthropic"
	if v, ok := env["ANTHROPIC_BASE_URL"].(string); ok && v != "" && v != "http://127.0.0.1:12121/claude_code" {
		baseURL = v
		log.Printf("[MAIN] Found custom base URL: %s", baseURL)
	} else if v == "http://127.0.0.1:12121/claude_code" {
		log.Printf("[MAIN] Base URL already points to token_gate proxy, using default")
	}

	modelStr := "claude-sonnet-4-6"
	if v, ok := env["ANTHROPIC_MODEL"].(string); ok && v != "" {
		modelStr = v
		log.Printf("[MAIN] Found custom model in env: %s", modelStr)
	} else if v, ok := settings["model"].(string); ok && v != "" {
		modelStr = v
		log.Printf("[MAIN] Found model in settings: %s", modelStr)
	}

	log.Printf("[MAIN] Importing config: name=default, url=%s, model=%s", baseURL, modelStr)
	if err := db.ImportExistingConfig("default", baseURL, apiKey, modelStr); err != nil {
		log.Printf("[MAIN] warning: import existing config: %v", err)
		return
	}

	cache.Load()

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

func cleanupAllConfigs(db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor) {
	validConfigs, err := db.ListActiveConfigs()
	if err != nil {
		log.Printf("[MAIN] cleanup: failed to list active configs: %v", err)
		return
	}

	if len(validConfigs) == 0 {
		log.Println("[MAIN] cleanup: no active configs to restore")
		return
	}

	log.Printf("[MAIN] cleanup: found %d active configs to restore", len(validConfigs))

	processorMap := make(map[string]agent.AgentProcessor)
	for _, p := range processors {
		processorMap[p.GetType()] = p
	}

	var wg sync.WaitGroup
	for _, vc := range validConfigs {
		wg.Add(1)
		go func(vc *model.ValidConfig) {
			defer wg.Done()
			log.Printf("[MAIN] cleanup: deactivating config for agent_type=%s", vc.AgentType)

			tc, err := db.GetTokenConfig(vc.TokenID)
			if err != nil {
				log.Printf("[MAIN] cleanup: failed to get token config %s: %v", vc.TokenID, err)
				return
			}
			if tc == nil {
				log.Printf("[MAIN] cleanup: token config %s not found", vc.TokenID)
				return
			}

			if processor, ok := processorMap[vc.AgentType]; ok {
				if err := processor.OnDeactivate(tc); err != nil {
					log.Printf("[MAIN] cleanup: OnDeactivate failed for agent_type=%s: %v", vc.AgentType, err)
				} else {
					log.Printf("[MAIN] cleanup: successfully restored settings for agent_type=%s", vc.AgentType)
				}
			}

			if err := db.DeactivateConfig(vc.AgentType); err != nil {
				log.Printf("[MAIN] cleanup: failed to deactivate config from DB for agent_type=%s: %v", vc.AgentType, err)
			}

			cache.Remove(vc.AgentType)
		}(vc)
	}
	wg.Wait()

	log.Println("[MAIN] cleanup: all configs deactivated and settings restored")
}
