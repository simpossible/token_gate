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
	// Extract agent_type from path: /{agent_type}/...
	parts := strings.SplitN(strings.TrimPrefix(r.URL.Path, "/"), "/", 2)
	if len(parts) < 2 {
		http.Error(w, "invalid path, expected /{agent_type}/...", http.StatusBadRequest)
		return
	}
	agentType := parts[0]
	realPath := "/" + parts[1]

	tc := p.cache.Get(agentType)
	if tc == nil {
		http.Error(w, fmt.Sprintf("no active config for agent type: %s", agentType), http.StatusServiceUnavailable)
		return
	}

	// Read and modify request body
	var bodyBytes []byte
	if r.Body != nil {
		var err error
		bodyBytes, err = io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "read body: "+err.Error(), http.StatusInternalServerError)
			return
		}
		r.Body.Close()
	}

	// Replace model in request body
	if len(bodyBytes) > 0 {
		bodyBytes = replaceModel(bodyBytes, tc.Model)
	}

	// Build target URL
	targetURL := strings.TrimSuffix(tc.URL, "/") + realPath
	if r.URL.RawQuery != "" {
		targetURL += "?" + r.URL.RawQuery
	}

	// Create forwarded request
	var bodyReader io.Reader
	if len(bodyBytes) > 0 {
		bodyReader = bytes.NewReader(bodyBytes)
	}
	fwdReq, err := http.NewRequest(r.Method, targetURL, bodyReader)
	if err != nil {
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
		http.Error(w, "forward request: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

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
		p.streamSSE(w, resp, tc.ID, agentType, realPath)
	} else {
		// Non-streaming: capture body for usage extraction, then write
		body, _ := io.ReadAll(resp.Body)
		w.Write(body)
		go p.extractAndRecordUsage(body, tc.ID, agentType, realPath)
	}
}

func (p *Proxy) streamSSE(w http.ResponseWriter, resp *http.Response, tokenID, agentType, requestPath string) {
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
			if err := p.db.RecordUsage(tokenID, agentType, lastUsageInput, lastUsageOutput, "", requestPath); err != nil {
				log.Printf("record usage error: %v", err)
			}
		}()
	}
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
		if err := p.db.RecordUsage(tokenID, agentType, inputTokens, outputTokens, modelName, requestPath); err != nil {
			log.Printf("record usage error: %v", err)
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
