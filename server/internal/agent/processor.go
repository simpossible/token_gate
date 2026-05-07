package agent

import "token_gate/internal/model"

type AgentProcessor interface {
	GetType() string
	GetLabel() string
	OnActivate(config *model.TokenConfig) error
	OnDeactivate(config *model.TokenConfig) error
}
