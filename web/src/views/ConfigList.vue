<template>
  <div class="config-grid">
    <div
      v-for="config in configs"
      :key="config.id"
      class="config-card"
      @click="$emit('open-detail', config.id)"
    >
      <div class="card-header">
        <h3 class="card-name">{{ config.name }}</h3>
        <div class="card-tags">
          <el-tag
            v-for="agent in config.active_agents"
            :key="agent"
            :type="agentTagType(agent)"
            size="small"
          >
            {{ agentLabel(agent) }}
          </el-tag>
        </div>
      </div>
      <div class="card-info">
        <div class="info-row">
          <span class="info-label">URL</span>
          <span class="info-value">{{ config.url }}</span>
        </div>
        <div class="info-row">
          <span class="info-label">Model</span>
          <span class="info-value">{{ config.model }}</span>
        </div>
        <div class="info-row">
          <span class="info-label">Usage</span>
          <span class="info-value usage-value">
            {{ formatTokens(config._input_tokens) }} in / {{ formatTokens(config._output_tokens) }} out
          </span>
        </div>
      </div>
    </div>

    <div class="config-card add-card" @click="$emit('open-create')">
      <el-icon :size="48" color="#c0c4cc"><Plus /></el-icon>
      <span class="add-text">Add Config</span>
    </div>
  </div>
</template>

<script setup>
import { Plus } from '@element-plus/icons-vue'

const props = defineProps({
  configs: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] }
})

defineEmits(['open-detail', 'open-create'])

const agentColors = { claude_code: 'success', cursor: '' }

function agentTagType(agent) {
  return agentColors[agent] || ''
}

function agentLabel(agent) {
  const found = props.agents.find(a => a.type === agent)
  return found ? found.label : agent
}

function formatTokens(tokens) {
  if (!tokens) return '0'
  if (tokens >= 10000) return (tokens / 10000).toFixed(1) + '万'
  return tokens.toLocaleString()
}
</script>

<style scoped>
.config-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 16px;
}
.config-card {
  background: white;
  border-radius: 12px;
  padding: 20px;
  cursor: pointer;
  transition: box-shadow 0.2s, transform 0.15s;
  border: 1px solid #ebeef5;
}
.config-card:hover {
  box-shadow: 0 4px 16px rgba(0,0,0,0.1);
  transform: translateY(-2px);
}
.add-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 160px;
  border: 2px dashed #dcdfe6;
  background: transparent;
}
.add-text { margin-top: 8px; color: #909399; font-size: 14px; }
.card-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px; }
.card-name { font-size: 16px; font-weight: 600; color: #303133; margin: 0; }
.card-tags { display: flex; gap: 4px; }
.info-row { display: flex; gap: 8px; margin-bottom: 6px; font-size: 13px; }
.info-label { color: #909399; min-width: 48px; }
.info-value { color: #606266; word-break: break-all; }
.usage-value { font-family: monospace; }
</style>
