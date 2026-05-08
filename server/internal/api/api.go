package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"token_gate/internal/agent"
	"token_gate/internal/config"
	"token_gate/internal/database"
	"token_gate/internal/latency"
	"token_gate/internal/model"
)

type API struct {
	db           *database.DB
	cache        *config.ActiveConfigCache
	processors   map[string]agent.AgentProcessor
	latencyCache *latency.Cache
}

func NewAPI(db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor, latencyCache *latency.Cache) *API {
	pm := make(map[string]agent.AgentProcessor)
	for _, p := range processors {
		pm[p.GetType()] = p
	}
	return &API{db: db, cache: cache, processors: pm, latencyCache: latencyCache}
}

func (a *API) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(corsMiddleware)
	r.Use(loggingMiddleware)
	r.Post("/api/configs", a.createConfig)
	r.Get("/api/configs", a.listConfigs)
	r.Get("/api/agents", a.listAgents)
	r.Route("/api/configs/{id}", func(r chi.Router) {
		r.Get("/", a.getConfig)
		r.Put("/", a.updateConfig)
		r.Delete("/", a.deleteConfig)
		r.Get("/usage", a.getUsage)
		r.Get("/usages", a.getUsages)
		r.Get("/usages/delta", a.getUsageDelta)
		r.Get("/latency/latest", a.getLatestLatency)
		r.Post("/activate", a.activateConfig)
		r.Post("/deactivate", a.deactivateConfig)
	})
	return r
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("[API] %s %s", r.Method, r.URL.Path)
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func (a *API) createConfig(w http.ResponseWriter, r *http.Request) {
	var req model.CreateConfigRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("[API] create config: invalid request body: %v", err)
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Name == "" || req.URL == "" || req.APIKey == "" || req.Model == "" {
		log.Printf("[API] create config: missing required fields")
		writeError(w, http.StatusBadRequest, "all fields are required")
		return
	}

	c, err := a.db.CreateTokenConfig(&req)
	if err != nil {
		log.Printf("[API] create config failed: %v", err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	log.Printf("[API] config created: id=%s, name=%s, url=%s, model=%s", c.ID, c.Name, c.URL, c.Model)
	writeJSON(w, http.StatusCreated, c)
}

func (a *API) listConfigs(w http.ResponseWriter, r *http.Request) {
	configs, err := a.db.ListTokenConfigs()
	if err != nil {
		log.Printf("[API] list configs failed: %v", err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	result := make([]*model.ConfigWithAgents, 0, len(configs))
	for _, c := range configs {
		agents, _ := a.db.GetActiveAgentsForConfig(c.ID)
		if agents == nil {
			agents = []string{}
		}
		result = append(result, &model.ConfigWithAgents{
			TokenConfig:  *c,
			ActiveAgents: agents,
		})
	}
	log.Printf("[API] listed %d configs", len(result))
	writeJSON(w, http.StatusOK, map[string]interface{}{"configs": result})
}

func (a *API) getConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	c, err := a.db.GetTokenConfig(id)
	if err != nil {
		log.Printf("[API] get config failed: id=%s, error=%v", id, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if c == nil {
		log.Printf("[API] config not found: id=%s", id)
		writeError(w, http.StatusNotFound, "config not found")
		return
	}
	log.Printf("[API] get config: id=%s, name=%s", c.ID, c.Name)
	writeJSON(w, http.StatusOK, c)
}

func (a *API) updateConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req model.UpdateConfigRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("[API] update config: invalid request body: %v", err)
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	c, err := a.db.UpdateTokenConfig(id, &req)
	if err != nil {
		log.Printf("[API] update config failed: id=%s, error=%v", id, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// If this config is active for any agent, update the cache
	agents, _ := a.db.GetActiveAgentsForConfig(id)
	for _, at := range agents {
		updated, _ := a.db.GetTokenConfig(id)
		if updated != nil {
			a.cache.Set(at, updated)
			log.Printf("[API] updated cache for agent: %s", at)
		}
	}

	log.Printf("[API] config updated: id=%s, name=%s", c.ID, c.Name)
	writeJSON(w, http.StatusOK, c)
}

func (a *API) deleteConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	// Deactivate from all agents first
	agents, _ := a.db.GetActiveAgentsForConfig(id)
	for _, at := range agents {
		if p, ok := a.processors[at]; ok {
			tc, _ := a.db.GetTokenConfig(id)
			if tc != nil {
				p.OnDeactivate(tc)
				log.Printf("[API] deactivated processor for agent: %s", at)
			}
		}
		a.cache.Remove(at)
		log.Printf("[API] removed cache for agent: %s", at)
	}

	if err := a.db.DeleteTokenConfig(id); err != nil {
		log.Printf("[API] delete config failed: id=%s, error=%v", id, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	log.Printf("[API] config deleted: id=%s", id)
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (a *API) getUsage(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	usage, err := a.db.GetUsage(id)
	if err != nil {
		log.Printf("[API] get usage failed: id=%s, error=%v", id, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if usage == nil {
		log.Printf("[API] usage not found: id=%s", id)
		writeError(w, http.StatusNotFound, "config not found")
		return
	}
	log.Printf("[API] get usage: id=%s, total_input=%d, total_output=%d, records=%d", id, usage.TotalInputTokens, usage.TotalOutputTokens, usage.RecordsCount)
	writeJSON(w, http.StatusOK, usage)
}

func (a *API) activateConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req model.ActivateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("[API] activate config: invalid request body: %v", err)
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	tc, err := a.db.GetTokenConfig(id)
	if err != nil {
		log.Printf("[API] activate config failed: id=%s, error=%v", id, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if tc == nil {
		log.Printf("[API] activate config: config not found: id=%s", id)
		writeError(w, http.StatusNotFound, "config not found")
		return
	}

	if _, ok := a.processors[req.AgentType]; !ok {
		log.Printf("[API] activate config: unknown agent type: %s", req.AgentType)
		writeError(w, http.StatusBadRequest, "unknown agent type: "+req.AgentType)
		return
	}

	if err := a.db.ActivateConfig(id, req.AgentType); err != nil {
		log.Printf("[API] activate config db failed: id=%s, agent=%s, error=%v", id, req.AgentType, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	a.cache.Set(req.AgentType, tc)

	if p, ok := a.processors[req.AgentType]; ok {
		if err := p.OnActivate(tc); err != nil {
			log.Printf("[API] processor OnActivate error: agent=%s, error=%v", req.AgentType, err)
		} else {
			log.Printf("[API] processor OnActivate success: agent=%s", req.AgentType)
		}
	}

	log.Printf("[API] config activated: config_id=%s, config_name=%s, agent=%s", id, tc.Name, req.AgentType)
	writeJSON(w, http.StatusOK, map[string]string{"status": "activated"})
}

func (a *API) deactivateConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req model.ActivateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("[API] deactivate config: invalid request body: %v", err)
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	tc, err := a.db.GetTokenConfig(id)
	if err != nil {
		log.Printf("[API] deactivate config failed: id=%s, error=%v", id, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if tc == nil {
		log.Printf("[API] deactivate config: config not found: id=%s", id)
		writeError(w, http.StatusNotFound, "config not found")
		return
	}

	if err := a.db.DeactivateConfig(req.AgentType); err != nil {
		log.Printf("[API] deactivate config db failed: agent=%s, error=%v", req.AgentType, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	a.cache.Remove(req.AgentType)

	if p, ok := a.processors[req.AgentType]; ok {
		p.OnDeactivate(tc)
		log.Printf("[API] processor OnDeactivate: agent=%s", req.AgentType)
	}

	log.Printf("[API] config deactivated: config_id=%s, config_name=%s, agent=%s", id, tc.Name, req.AgentType)
	writeJSON(w, http.StatusOK, map[string]string{"status": "deactivated"})
}

func (a *API) getUsages(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	days := 7
	if d := r.URL.Query().Get("days"); d != "" {
		if v, err := strconv.Atoi(d); err == nil && v > 0 {
			days = v
		}
	}
	usages, err := a.db.GetUsages(id, days)
	if err != nil {
		log.Printf("[API] get usages failed: id=%s, error=%v", id, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if usages == nil {
		usages = []*model.Usage{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"usages": usages})
}

func (a *API) getUsageDelta(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	afterStr := r.URL.Query().Get("after")
	if afterStr == "" {
		log.Printf("[API] get usage delta failed: missing 'after' parameter")
		writeError(w, http.StatusBadRequest, "missing 'after' parameter")
		return
	}

	after, err := time.Parse(time.RFC3339, afterStr)
	if err != nil {
		log.Printf("[API] get usage delta failed: invalid 'after' parameter: %v", err)
		writeError(w, http.StatusBadRequest, "invalid 'after' parameter format")
		return
	}

	usages, err := a.db.GetUsagesAfter(id, after)
	if err != nil {
		log.Printf("[API] get usage delta failed: id=%s, error=%v", id, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if usages == nil {
		usages = []*model.Usage{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"usages": usages})
}

func (a *API) getLatestLatency(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ms, ok := a.latencyCache.Get(id)
	writeJSON(w, http.StatusOK, model.LatestLatencyResponse{
		TokenID:         id,
		LatestLatencyMs: ms,
		HasData:         ok,
	})
}

func (a *API) listAgents(w http.ResponseWriter, r *http.Request) {
	agents := make([]model.AgentInfo, 0)
	for _, p := range a.processors {
		info := model.AgentInfo{
			Type:  p.GetType(),
			Label: p.GetLabel(),
		}
		vc, _ := a.db.GetActiveConfig(p.GetType())
		if vc != nil {
			tc, _ := a.db.GetTokenConfig(vc.TokenID)
			if tc != nil {
				info.ActiveConfigID = &tc.ID
				info.ActiveConfigName = &tc.Name
			}
		}
		agents = append(agents, info)
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"agents": agents})
}
