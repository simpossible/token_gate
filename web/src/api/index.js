import axios from 'axios'

const api = axios.create({
  baseURL: 'http://127.0.0.1:12122'
})

export function getConfigs() {
  return api.get('/api/configs').then(r => r.data.configs)
}

export function getConfig(id) {
  return api.get(`/api/configs/${id}`).then(r => r.data)
}

export function createConfig(data) {
  return api.post('/api/configs', data).then(r => r.data)
}

export function updateConfig(id, data) {
  return api.put(`/api/configs/${id}`, data).then(r => r.data)
}

export function deleteConfig(id) {
  return api.delete(`/api/configs/${id}`).then(r => r.data)
}

export function getUsage(id) {
  return api.get(`/api/configs/${id}/usage`).then(r => r.data)
}

export function activateConfig(id, agentType) {
  return api.post(`/api/configs/${id}/activate`, { agent_type: agentType }).then(r => r.data)
}

export function deactivateConfig(id, agentType) {
  return api.post(`/api/configs/${id}/deactivate`, { agent_type: agentType }).then(r => r.data)
}

export function getAgents() {
  return api.get('/api/agents').then(r => r.data.agents)
}
