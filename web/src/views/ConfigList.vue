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

</script>

<style scoped>
.config-grid {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-start;
  align-items: flex-start;
  gap: 16px;
  width: 100%;
}
.config-card {
  background: white;
  border-radius: 12px;
  padding: 20px;
  cursor: pointer;
  transition: box-shadow 0.2s, transform 0.15s;
  border: 1px solid #ebeef5;
  width: 300px;
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
  min-height: 120px;
  border: 2px dashed #dcdfe6;
  background: transparent;
}
.add-text { margin-top: 8px; color: #909399; font-size: 14px; }
.card-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px; }
.card-name { font-size: 16px; font-weight: 600; color: #303133; margin: 0; }
.card-tags { display: flex; gap: 4px; flex-wrap: wrap; justify-content: flex-end; }
.info-row { display: flex; gap: 8px; margin-bottom: 6px; font-size: 13px; }
.info-label { color: #909399; min-width: 48px; }
.info-value { color: #606266; word-break: break-all; }
</style>
