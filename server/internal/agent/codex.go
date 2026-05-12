package agent

import (
	"log"

	"token_gate/internal/model"
)

type CodexProcessor struct{}

func NewCodexProcessor() *CodexProcessor {
	return &CodexProcessor{}
}

func (p *CodexProcessor) GetType() string  { return "codex" }
func (p *CodexProcessor) GetLabel() string { return "Codex" }

func (p *CodexProcessor) OnActivate(config *model.TokenConfig) error {
	log.Printf("[AGENT] Codex OnActivate: config_id=%s (not implemented)", config.ID)
	return nil
}

func (p *CodexProcessor) OnDeactivate(config *model.TokenConfig) error {
	log.Printf("[AGENT] Codex OnDeactivate: config_id=%s (not implemented)", config.ID)
	return nil
}
