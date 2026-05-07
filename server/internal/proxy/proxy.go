package proxy

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"token_gate/internal/config"
	"token_gate/internal/database"
)

type Proxy struct {
	cache *config.ActiveConfigCache
	db    *database.DB
}

func NewProxy(cache *config.ActiveConfigCache, db *database.DB) *Proxy {
	return &Proxy{cache: cache, db: db}
}

func (p *Proxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := time.Now()

	// Extract agent_type from path: /{agent_type}/...
	parts := strings.SplitN(strings.TrimPrefix(r.URL.Path, "/"), "/", 2)
	if len(parts) < 2 {
		log.Printf("[PROXY] invalid path: %s", r.URL.Path)
		http.Error(w, "invalid path, expected /{agent_type}/...", http.StatusBadRequest)
		return
	}
	agentType := parts[0]
	realPath := "/" + parts[1]

	tc := p.cache.Get(agentType)
	if tc == nil {
		log.Printf("[PROXY] no active config for agent_type: %s, path: %s", agentType, realPath)
		http.Error(w, fmt.Sprintf("no active config for agent type: %s", agentType), http.StatusServiceUnavailable)
		return
	}

	log.Printf("[PROXY] request start: agent=%s, path=%s, method=%s, config=%s", agentType, realPath, r.Method, tc.Name)

	// Read and modify request body
	var bodyBytes []byte
	if r.Body != nil {
		var err error
		bodyBytes, err = io.ReadAll(r.Body)
		if err != nil {
			log.Printf("[PROXY] read body error: %v", err)
			http.Error(w, "read body: "+err.Error(), http.StatusInternalServerError)
			return
		}
		r.Body.Close()
	}

	// Replace model in request body
	originalModel := ""
	if len(bodyBytes) > 0 {
		var req map[string]interface{}
		if err := json.Unmarshal(bodyBytes, &req); err == nil {
			if m, ok := req["model"].(string); ok {
				originalModel = m
			}
		}
		bodyBytes = replaceModel(bodyBytes, tc.Model)
		if originalModel != "" && originalModel != tc.Model {
			log.Printf("[PROXY] model override: %s -> %s", originalModel, tc.Model)
		}
	}

	// Build target URL
	targetURL := strings.TrimSuffix(tc.URL, "/") + realPath
	if r.URL.RawQuery != "" {
		targetURL += "?" + r.URL.RawQuery
	}

	log.Printf("[PROXY] forwarding to: %s", targetURL)

	// Create forwarded request
	var bodyReader io.Reader
	if len(bodyBytes) > 0 {
		bodyReader = bytes.NewReader(bodyBytes)
	}
	fwdReq, err := http.NewRequest(r.Method, targetURL, bodyReader)
	if err != nil {
		log.Printf("[PROXY] create request error: %v", err)
		http.Error(w, "create request: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Copy headers, replace Authorization
	for k, vs := range r.Header {
		for _, v := range vs {
			fwdReq.Header.Add(k, v)
		}
	}
	fwdReq.Header.Set("Authorization", "Bearer "+tc.APIKey)
	if len(bodyBytes) > 0 {
		fwdReq.Header.Set("Content-Type", "application/json")
	}

	client := &http.Client{Timeout: 5 * time.Minute}
	resp, err := client.Do(fwdReq)
	if err != nil {
		log.Printf("[PROXY] forward request error: %v", err)
		http.Error(w, "forward request: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	log.Printf("[PROXY] response status: %d, content-type: %s", resp.StatusCode, resp.Header.Get("Content-Type"))

	// Copy response headers
	for k, vs := range resp.Header {
		for _, v := range vs {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)

	// Check if SSE response
	isSSE := strings.Contains(resp.Header.Get("Content-Type"), "text/event-stream")
	if isSSE {
		log.Printf("[PROXY] streaming SSE response")
		p.streamSSE(w, resp, tc.ID, agentType, realPath, start)
	} else {
		// Non-streaming: capture body for usage extraction, then write
		body, _ := io.ReadAll(resp.Body)
		w.Write(body)
		log.Printf("[PROXY] request complete: agent=%s, path=%s, duration=%v, status=%d", agentType, realPath, time.Since(start), resp.StatusCode)
		go p.extractAndRecordUsage(body, tc.ID, agentType, realPath)
	}
}

func (p *Proxy) streamSSE(w http.ResponseWriter, resp *http.Response, tokenID, agentType, requestPath string, start time.Time) {
	flusher, canFlush := w.(http.Flusher)
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	var lastUsageInput, lastUsageOutput int

	for scanner.Scan() {
		line := scanner.Text()
		fmt.Fprintln(w, line)
		if canFlush {
			flusher.Flush()
		}

		// Parse usage from message_delta events
		if strings.HasPrefix(line, "data: ") {
			data := strings.TrimPrefix(line, "data: ")
			if data == "[DONE]" {
				continue
			}
			var event map[string]interface{}
			if err := json.Unmarshal([]byte(data), &event); err == nil {
				if usage, ok := event["usage"].(map[string]interface{}); ok {
					if it, ok := usage["input_tokens"].(float64); ok {
						lastUsageInput = int(it)
					}
					if ot, ok := usage["output_tokens"].(float64); ok {
						lastUsageOutput = int(ot)
					}
				}
				// Also check message_start for input tokens
				if msg, ok := event["message"].(map[string]interface{}); ok {
					if usage, ok := msg["usage"].(map[string]interface{}); ok {
						if it, ok := usage["input_tokens"].(float64); ok {
							lastUsageInput = int(it)
						}
						if ot, ok := usage["output_tokens"].(float64); ok {
							lastUsageOutput = int(ot)
						}
					}
				}
			}
		}
	}

	if lastUsageInput > 0 || lastUsageOutput > 0 {
		go func() {
			log.Printf("[PROXY] recording usage: agent=%s, input=%d, output=%d", agentType, lastUsageInput, lastUsageOutput)
			if err := p.db.RecordUsage(tokenID, agentType, lastUsageInput, lastUsageOutput, "", requestPath); err != nil {
				log.Printf("[PROXY] record usage error: %v", err)
			}
		}()
	}

	log.Printf("[PROXY] SSE stream complete: agent=%s, path=%s, duration=%v, input_tokens=%d, output_tokens=%d", agentType, requestPath, time.Since(start), lastUsageInput, lastUsageOutput)
}

func (p *Proxy) extractAndRecordUsage(body []byte, tokenID, agentType, requestPath string) {
	var resp map[string]interface{}
	if err := json.Unmarshal(body, &resp); err != nil {
		return
	}

	usage, ok := resp["usage"].(map[string]interface{})
	if !ok {
		return
	}

	var inputTokens, outputTokens int
	if it, ok := usage["input_tokens"].(float64); ok {
		inputTokens = int(it)
	}
	if ot, ok := usage["output_tokens"].(float64); ok {
		outputTokens = int(ot)
	}

	if inputTokens > 0 || outputTokens > 0 {
		modelName := ""
		if m, ok := resp["model"].(string); ok {
			modelName = m
		}
		log.Printf("[PROXY] extracting usage from non-streaming response: agent=%s, input=%d, output=%d, model=%s", agentType, inputTokens, outputTokens, modelName)
		if err := p.db.RecordUsage(tokenID, agentType, inputTokens, outputTokens, modelName, requestPath); err != nil {
			log.Printf("[PROXY] record usage error: %v", err)
		}
	}
}

func replaceModel(body []byte, model string) []byte {
	var req map[string]interface{}
	if err := json.Unmarshal(body, &req); err != nil {
		return body
	}
	if _, ok := req["model"]; ok {
		req["model"] = model
	}
	newBody, err := json.Marshal(req)
	if err != nil {
		return body
	}
	return newBody
}
