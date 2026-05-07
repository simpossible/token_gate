package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"token_gate/internal/agent"
	"token_gate/internal/config"
	"token_gate/internal/database"
	"token_gate/internal/model"
)

type API struct {
	db         *database.DB
	cache      *config.ActiveConfigCache
	processors map[string]agent.AgentProcessor
}

func NewAPI(db *database.DB, cache *config.ActiveConfigCache, processors []agent.AgentProcessor) *API {
	pm := make(map[string]agent.AgentProcessor)
	for _, p := range processors {
		pm[p.GetType()] = p
	}
	return &API{db: db, cache: cache, processors: pm}
}

func (a *API) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(corsMiddleware)
	r.Post("/api/configs", a.createConfig)
	r.Get("/api/configs", a.listConfigs)
	r.Get("/api/agents", a.listAgents)
	r.Route("/api/configs/{id}", func(r chi.Router) {
		r.Get("/", a.getConfig)
		r.Put("/", a.updateConfig)
		r.Delete("/", a.deleteConfig)
		r.Get("/usage", a.getUsage)
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
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Name == "" || req.URL == "" || req.APIKey == "" || req.Model == "" {
		writeError(w, http.StatusBadRequest, "all fields are required")
		return
	}

	c, err := a.db.CreateTokenConfig(&req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	c.APIKey = c.MaskedAPIKey()
	writeJSON(w, http.StatusCreated, c)
}

func (a *API) listConfigs(w http.ResponseWriter, r *http.Request) {
	configs, err := a.db.ListTokenConfigs()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	result := make([]*model.ConfigWithAgents, 0, len(configs))
	for _, c := range configs {
		agents, _ := a.db.GetActiveAgentsForConfig(c.ID)
		if agents == nil {
			agents = []string{}
		}
		cc := *c
		cc.APIKey = c.MaskedAPIKey()
		result = append(result, &model.ConfigWithAgents{
			TokenConfig:  cc,
			ActiveAgents: agents,
		})
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"configs": result})
}

func (a *API) getConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	c, err := a.db.GetTokenConfig(id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if c == nil {
		writeError(w, http.StatusNotFound, "config not found")
		return
	}
	c.APIKey = c.MaskedAPIKey()
	writeJSON(w, http.StatusOK, c)
}

func (a *API) updateConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req model.UpdateConfigRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	c, err := a.db.UpdateTokenConfig(id, &req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// If this config is active for any agent, update the cache
	agents, _ := a.db.GetActiveAgentsForConfig(id)
	for _, at := range agents {
		updated, _ := a.db.GetTokenConfig(id)
		if updated != nil {
			a.cache.Set(at, updated)
		}
	}

	c.APIKey = c.MaskedAPIKey()
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
			}
		}
		a.cache.Remove(at)
	}

	if err := a.db.DeleteTokenConfig(id); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (a *API) getUsage(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	usage, err := a.db.GetUsage(id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if usage == nil {
		writeError(w, http.StatusNotFound, "config not found")
		return
	}
	writeJSON(w, http.StatusOK, usage)
}

func (a *API) activateConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req model.ActivateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	tc, err := a.db.GetTokenConfig(id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if tc == nil {
		writeError(w, http.StatusNotFound, "config not found")
		return
	}

	if _, ok := a.processors[req.AgentType]; !ok {
		writeError(w, http.StatusBadRequest, "unknown agent type: "+req.AgentType)
		return
	}

	if err := a.db.ActivateConfig(id, req.AgentType); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	a.cache.Set(req.AgentType, tc)

	if p, ok := a.processors[req.AgentType]; ok {
		if err := p.OnActivate(tc); err != nil {
			// Log but don't fail
			_ = err
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "activated"})
}

func (a *API) deactivateConfig(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req model.ActivateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	tc, err := a.db.GetTokenConfig(id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if tc == nil {
		writeError(w, http.StatusNotFound, "config not found")
		return
	}

	if err := a.db.DeactivateConfig(req.AgentType); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	a.cache.Remove(req.AgentType)

	if p, ok := a.processors[req.AgentType]; ok {
		p.OnDeactivate(tc)
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deactivated"})
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
