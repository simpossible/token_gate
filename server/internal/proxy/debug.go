package proxy

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"gopkg.in/natefinch/lumberjack.v2"
)

type debugLogger struct {
	logger *log.Logger
}

func newDebugLogger() *debugLogger {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	logPath := filepath.Join(home, ".token_gate", "logs", "http_debug.log")
	if err := os.MkdirAll(filepath.Dir(logPath), 0755); err != nil {
		return nil
	}
	lj := &lumberjack.Logger{
		Filename:   logPath,
		MaxSize:    50,
		MaxBackups: 2,
	}
	return &debugLogger{logger: log.New(lj, "", 0)}
}

func (d *debugLogger) printf(format string, args ...interface{}) {
	if d == nil {
		return
	}
	d.logger.Printf(format, args...)
}

func maskSensitive(v string) string {
	// Strip "Bearer " prefix if present before masking
	prefix := ""
	raw := v
	if strings.HasPrefix(v, "Bearer ") {
		prefix = "Bearer "
		raw = v[len("Bearer "):]
	}
	if len(raw) <= 14 {
		return prefix + "***"
	}
	return prefix + raw[:10] + "..." + raw[len(raw)-4:]
}

func formatHeaders(headers http.Header) string {
	var sb strings.Builder
	keys := make([]string, 0, len(headers))
	for k := range headers {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		kl := strings.ToLower(k)
		for _, v := range headers[k] {
			display := v
			if kl == "authorization" || kl == "x-api-key" || kl == "anthropic-api-key" {
				display = maskSensitive(v)
			}
			fmt.Fprintf(&sb, "  %-35s %s\n", k+":", display)
		}
	}
	return sb.String()
}

func prettyJSON(data []byte) string {
	if len(data) == 0 {
		return "  (empty)"
	}
	var buf bytes.Buffer
	if err := json.Indent(&buf, data, "  ", "  "); err != nil {
		return "  " + string(data)
	}
	return "  " + buf.String()
}

func shortID() string {
	return fmt.Sprintf("%06x", time.Now().UnixNano()%0xFFFFFF)
}

func (d *debugLogger) logRequest(reqID, agentType, method, targetURL string, origHeaders, fwdHeaders http.Header, body []byte) {
	if d == nil {
		return
	}
	ts := time.Now().Format("2006-01-02 15:04:05.000")
	sep := strings.Repeat("═", 72)
	thin := strings.Repeat("─", 72)

	d.printf("\n%s", sep)
	d.printf("REQUEST  id=%-8s  %s", reqID, ts)
	d.printf("  %s %s  (agent: %s)", method, targetURL, agentType)
	d.printf("%s", thin)

	d.printf("Client Headers (original):")
	d.printf("%s", formatHeaders(origHeaders))

	d.printf("Forwarded Headers (after proxy rewrite):")
	d.printf("%s", formatHeaders(fwdHeaders))

	d.printf("Request Body:")
	d.printf("%s", prettyJSON(body))
}

func (d *debugLogger) logResponse(reqID string, status int, headers http.Header) {
	if d == nil {
		return
	}
	thin := strings.Repeat("─", 72)
	d.printf("%s", thin)
	d.printf("RESPONSE  id=%-8s  status=%d", reqID, status)
	d.printf("%s", formatHeaders(headers))
}

func (d *debugLogger) logResponseBody(reqID string, body []byte) {
	if d == nil {
		return
	}
	d.printf("Response Body:")
	d.printf("%s", prettyJSON(body))
	d.printf("%s\n", strings.Repeat("═", 72))
}

func (d *debugLogger) logSSELine(line string) {
	if d == nil {
		return
	}
	d.printf("  SSE> %s", line)
}

func (d *debugLogger) logSSEEnd(reqID string) {
	if d == nil {
		return
	}
	d.printf("SSE stream end  id=%s", reqID)
	d.printf("%s\n", strings.Repeat("═", 72))
}
