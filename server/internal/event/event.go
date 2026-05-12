package event

import (
	"encoding/json"
	"log"
	"sync"
)

type Event struct {
	ConnType string      // "event" or "log" — routing key for subscribers
	Type     string      // "usage_new", "gate_log", "total_token_change"
	ConfigID string      // empty for global events
	Payload  interface{}
}

func (e Event) ToJSON() []byte {
	data, _ := json.Marshal(map[string]interface{}{
		"event_type": e.Type,
		"config_id":  e.ConfigID,
		"payload":    e.Payload,
	})
	return data
}

type Subscriber struct {
	connType string
	configID string // empty = all
	ch       chan Event
}

type EventBus struct {
	mu          sync.RWMutex
	subscribers map[string][]*Subscriber // key = connType
}

func NewEventBus() *EventBus {
	return &EventBus{
		subscribers: make(map[string][]*Subscriber),
	}
}

func (b *EventBus) Subscribe(connType, configID string) *Subscriber {
	sub := &Subscriber{
		connType: connType,
		configID: configID,
		ch:       make(chan Event, 64),
	}
	b.mu.Lock()
	b.subscribers[connType] = append(b.subscribers[connType], sub)
	count := len(b.subscribers[connType])
	b.mu.Unlock()
	log.Printf("[EVENT] Subscribe: connType=%s, configID=%s, total_subscribers=%d", connType, configID, count)
	return sub
}

func (b *EventBus) Unsubscribe(sub *Subscriber) {
	b.mu.Lock()
	defer b.mu.Unlock()

	subs := b.subscribers[sub.connType]
	for i, s := range subs {
		if s == sub {
			b.subscribers[sub.connType] = append(subs[:i], subs[i+1:]...)
			close(sub.ch)
			log.Printf("[EVENT] Unsubscribe: connType=%s, configID=%s, remaining=%d", sub.connType, sub.configID, len(b.subscribers[sub.connType]))
			return
		}
	}
}

func (b *EventBus) HasSubscribers(connType, configID string) bool {
	b.mu.RLock()
	defer b.mu.RUnlock()

	for _, s := range b.subscribers[connType] {
		if s.configID == "" || s.configID == configID || configID == "" {
			return true
		}
	}
	return false
}

func (b *EventBus) Publish(event Event) {
	b.mu.RLock()
	subs := b.subscribers[event.ConnType]
	matched := 0
	for _, sub := range subs {
		if sub.configID != "" && sub.configID != event.ConfigID && event.ConfigID != "" {
			continue
		}
		matched++
		select {
		case sub.ch <- event:
		default:
			log.Printf("[EVENT] Publish DROPPED: connType=%s, eventType=%s, configID=%s (channel full)", event.ConnType, event.Type, event.ConfigID)
		}
	}
	b.mu.RUnlock()
	log.Printf("[EVENT] Publish: type=%s, connType=%s, configID=%s, matched=%d/%d", event.Type, event.ConnType, event.ConfigID, matched, len(subs))
}

func (s *Subscriber) Channel() <-chan Event {
	return s.ch
}
