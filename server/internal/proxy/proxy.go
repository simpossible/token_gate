package proxy

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"

	"token_gate/internal/config"
	"token_gate/internal/database"
	"token_gate/internal/event"
	"token_gate/internal/latency"
)

type Proxy struct {
	cache        *config.ActiveConfigCache
	db           *database.DB
	latencyCache *latency.Cache
	eventBus     *event.EventBus
	debug        *debugLogger
}

type debugKind string

const (
	debugRequestStart   debugKind = "request_start"
	debugRequestHeaders debugKind = "request_headers"
	debugRequestBody    debugKind = "request_body"
	debugResponseHeaders debugKind = "response_headers"
	debugResponseChunk  debugKind = "response_chunk"
	debugRequestEnd     debugKind = "request_end"
)

type gateDebugPayload struct {
	ReqID string    `json:"req_id"`
	Kind  debugKind `json:"kind"`
	TsMs  int64     `json:"ts_ms"`

	Method    string `json:"method,omitempty"`
	Path      string `json:"path,omitempty"`
	TargetURL string `json:"target_url,omitempty"`
	AgentType string `json:"agent_type,omitempty"`
	Model     string `json:"model,omitempty"`
	Status    int    `json:"status,omitempty"`

	RequestHeaders  map[string][]string `json:"request_headers,omitempty"`
	ResponseHeaders map[string][]string `json:"response_headers,omitempty"`

	Body  string `json:"body,omitempty"`
	Chunk string `json:"chunk,omitempty"`

	LatencyMs int64 `json:"latency_ms,omitempty"`
	TTFBMs    int64 `json:"ttfb_ms,omitempty"`
	Usage     *struct {
		InputTokens  int `json:"input_tokens"`
		OutputTokens int `json:"output_tokens"`
	} `json:"usage,omitempty"`
}

func (p *Proxy) publishDebug(configID string, payload gateDebugPayload) {
	if p.eventBus.HasSubscribers("log", configID) {
		p.eventBus.Publish(event.Event{
			ConnType: "log",
			Type:     "gate_debug",
			ConfigID: configID,
			Payload:  payload,
		})
	}
}

func NewProxy(cache *config.ActiveConfigCache, db *database.DB, latencyCache *latency.Cache, eventBus *event.EventBus) *Proxy {
	return &Proxy{cache: cache, db: db, latencyCache: latencyCache, eventBus: eventBus, debug: newDebugLogger()}
}

func (p *Proxy) publishLog(configID string, msg string) {
	if p.eventBus.HasSubscribers("log", configID) {
		p.eventBus.Publish(event.Event{
			ConnType: "log",
			Type:     "gate_log",
			ConfigID: configID,
			Payload:  map[string]string{"message": msg},
		})
	}
}

func headersToMap(h http.Header) map[string][]string {
	m := make(map[string][]string, len(h))
	for k, vs := range h {
		m[k] = append([]string(nil), vs...)
	}
	return m
}

func (p *Proxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	reqID := shortID()

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

	// Snapshot original headers before any modification (for debug log)
	origHeaders := r.Header.Clone()

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

	// Publish gate_debug: request start + headers
	p.publishDebug(tc.ID, gateDebugPayload{
		ReqID:     reqID,
		Kind:      debugRequestStart,
		TsMs:      time.Now().UnixMilli(),
		Method:    r.Method,
		Path:      realPath,
		TargetURL: targetURL,
		AgentType: agentType,
		Model:     tc.Model,
	})

	// Publish gate_log: request summary + body
	if p.eventBus.HasSubscribers("log", tc.ID) {
		msg := fmt.Sprintf("%s → %s %s model=%s (%d bytes)", time.Now().Format("15:04:05"), r.Method, realPath, tc.Model, len(bodyBytes))
		p.publishLog(tc.ID, msg)
	}

	// Publish gate_debug: request body
	if len(bodyBytes) > 0 {
		var pretty bytes.Buffer
		if json.Indent(&pretty, bodyBytes, "", "  ") == nil {
			if p.eventBus.HasSubscribers("log", tc.ID) {
				p.publishLog(tc.ID, pretty.String())
			}
			p.publishDebug(tc.ID, gateDebugPayload{
				ReqID: reqID,
				Kind:  debugRequestBody,
				TsMs:  time.Now().UnixMilli(),
				Body:  pretty.String(),
			})
		}
	}

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

	p.debug.logRequest(reqID, agentType, r.Method, targetURL, origHeaders, fwdReq.Header, bodyBytes)

	p.publishDebug(tc.ID, gateDebugPayload{
		ReqID:           reqID,
		Kind:            debugRequestHeaders,
		TsMs:            time.Now().UnixMilli(),
		RequestHeaders:  headersToMap(origHeaders),
		ResponseHeaders: headersToMap(fwdReq.Header),
	})

	client := p.newHTTPClient()
	resp, err := client.Do(fwdReq)
	if err != nil {
		log.Printf("[PROXY] forward request error: %v", err)
		http.Error(w, "forward request: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	log.Printf("[PROXY] response status: %d, content-type: %s", resp.StatusCode, resp.Header.Get("Content-Type"))
	p.debug.logResponse(reqID, resp.StatusCode, resp.Header)

	p.publishDebug(tc.ID, gateDebugPayload{
		ReqID:           reqID,
		Kind:            debugResponseHeaders,
		TsMs:            time.Now().UnixMilli(),
		Status:          resp.StatusCode,
		ResponseHeaders: headersToMap(resp.Header),
	})

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
		p.streamSSE(w, resp, tc.ID, agentType, reqID, start, realPath, targetURL, r.Method, tc.Model)
	} else {
		body, _ := io.ReadAll(resp.Body)
		w.Write(body)
		latencyMs := time.Since(start).Milliseconds()
		log.Printf("[PROXY] request complete: agent=%s, path=%s, duration=%dms, status=%d", agentType, realPath, latencyMs, resp.StatusCode)
		p.debug.logResponseBody(reqID, body)

		// Publish gate_log: non-SSE response body + summary
		if p.eventBus.HasSubscribers("log", tc.ID) {
			if len(body) > 0 {
				var pretty bytes.Buffer
				if json.Indent(&pretty, body, "", "  ") == nil {
					p.publishLog(tc.ID, pretty.String())
				}
			}
		}

		go p.recordUsage(body, tc.ID, agentType, latencyMs)
	}
}

func (p *Proxy) streamSSE(w http.ResponseWriter, resp *http.Response, tokenID, agentType, reqID string, start time.Time, path, targetURL, method, model string) {
	flusher, canFlush := w.(http.Flusher)
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	var lastUsageInput, lastUsageOutput int
	var ttfbMs int64
	firstLine := true
	hasLogSubscriber := p.eventBus.HasSubscribers("log", tokenID)

	for scanner.Scan() {
		line := scanner.Text()

		if firstLine && line != "" {
			ttfbMs = time.Since(start).Milliseconds()
			firstLine = false
		}

		fmt.Fprintln(w, line)
		if canFlush {
			flusher.Flush()
		}
		p.debug.logSSELine(line)

		// Publish gate_log: each SSE data line
		if hasLogSubscriber && strings.HasPrefix(line, "data: ") {
			data := strings.TrimPrefix(line, "data: ")
			if data != "[DONE]" {
				p.publishLog(tokenID, data)
					p.publishDebug(tokenID, gateDebugPayload{
						ReqID: reqID,
						Kind:  debugResponseChunk,
						TsMs:  time.Now().UnixMilli(),
						Chunk: data,
					})
			}
		}

		// Parse usage from SSE events
		if strings.HasPrefix(line, "data: ") {
			data := strings.TrimPrefix(line, "data: ")
			if data == "[DONE]" {
				continue
			}
			var evt map[string]interface{}
			if err := json.Unmarshal([]byte(data), &evt); err == nil {
				if usage, ok := evt["usage"].(map[string]interface{}); ok {
					if it, ok := usage["input_tokens"].(float64); ok {
						lastUsageInput = int(it)
					}
					if ot, ok := usage["output_tokens"].(float64); ok {
						lastUsageOutput = int(ot)
					}
				}
				if msg, ok := evt["message"].(map[string]interface{}); ok {
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
			log.Printf("[PROXY] recording SSE usage: agent=%s, latency=%dms, input=%d, output=%d", agentType, ttfbMs, lastUsageInput, lastUsageOutput)
			if err := p.db.RecordUsage(tokenID, agentType, ttfbMs, lastUsageInput, lastUsageOutput); err != nil {
				log.Printf("[PROXY] record usage error: %v", err)
			}
			p.latencyCache.Set(tokenID, ttfbMs)
			p.publishUsageEvents(tokenID, ttfbMs, lastUsageInput, lastUsageOutput, true)
		}()
	}

	// Publish gate_log: SSE response summary
	if hasLogSubscriber {
		msg := fmt.Sprintf("%s ← ↑%d ↓%d %dms streaming", time.Now().Format("15:04:05"), lastUsageInput, lastUsageOutput, ttfbMs)
		p.publishLog(tokenID, msg)
	}

		p.publishDebug(tokenID, gateDebugPayload{
			ReqID:     reqID,
			Kind:      debugRequestEnd,
			TsMs:      time.Now().UnixMilli(),
			Method:    method,
			Path:      path,
			TargetURL: targetURL,
			AgentType: agentType,
			Model:     model,
			TTFBMs:    ttfbMs,
			Usage: &struct {
				InputTokens  int `json:"input_tokens"`
				OutputTokens int `json:"output_tokens"`
			}{InputTokens: lastUsageInput, OutputTokens: lastUsageOutput},
		})

	log.Printf("[PROXY] SSE stream complete: agent=%s, ttfb=%dms, input=%d, output=%d", agentType, ttfbMs, lastUsageInput, lastUsageOutput)
	p.debug.logSSEEnd(reqID)
}

func (p *Proxy) recordUsage(body []byte, tokenID, agentType string, latencyMs int64) {
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
		log.Printf("[PROXY] recording non-SSE usage: agent=%s, latency=%dms, input=%d, output=%d", agentType, latencyMs, inputTokens, outputTokens)
		if err := p.db.RecordUsage(tokenID, agentType, latencyMs, inputTokens, outputTokens); err != nil {
			log.Printf("[PROXY] record usage error: %v", err)
		}
		p.latencyCache.Set(tokenID, latencyMs)
		p.publishUsageEvents(tokenID, latencyMs, inputTokens, outputTokens, false)

		// Publish gate_log: non-SSE response summary
		msg := fmt.Sprintf("%s ← ↑%d ↓%d %dms", time.Now().Format("15:04:05"), inputTokens, outputTokens, latencyMs)
		p.publishLog(tokenID, msg)
	}
}

func (p *Proxy) publishUsageEvents(tokenID string, latencyMs int64, inputTokens, outputTokens int, isStreaming bool) {
	if p.eventBus.HasSubscribers("event", tokenID) {
		p.eventBus.Publish(event.Event{
			ConnType: "event",
			Type:     "usage_new",
			ConfigID: tokenID,
			Payload: map[string]interface{}{
				"input_tokens":  inputTokens,
				"output_tokens": outputTokens,
				"latency_ms":    latencyMs,
			},
		})
	}

	if p.eventBus.HasSubscribers("event", "") {
		p.eventBus.Publish(event.Event{
			ConnType: "event",
			Type:     "total_token_change",
			Payload: map[string]interface{}{
				"added_in_tokens":  inputTokens,
				"added_out_tokens": outputTokens,
			},
		})
	}
}

func (p *Proxy) newHTTPClient() *http.Client {
	client := &http.Client{Timeout: 5 * time.Minute}
	cfg, err := p.db.GetProxyConfig()
	if err == nil && cfg.Enabled && cfg.Host != "" && cfg.Port != "" {
		proxyURL, err := url.Parse("http://" + cfg.Host + ":" + cfg.Port)
		if err == nil {
			client.Transport = &http.Transport{Proxy: http.ProxyURL(proxyURL)}
		}
	}
	return client
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
