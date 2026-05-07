<template>
  <div class="detail-container" v-loading="loading">
    <el-page-header @back="$emit('back')" title="Back" class="page-header">
      <template #content>
        <span class="header-title">{{ config?.name || 'Loading...' }}</span>
      </template>
    </el-page-header>

    <div v-if="config" class="detail-content">
      <el-card class="card" header="Config Info">
        <el-descriptions :column="1" border>
          <el-descriptions-item label="ID">{{ config.id }}</el-descriptions-item>
          <el-descriptions-item label="Name">{{ config.name }}</el-descriptions-item>
          <el-descriptions-item label="URL">{{ config.url }}</el-descriptions-item>
          <el-descriptions-item label="API Key">{{ config.api_key }}</el-descriptions-item>
          <el-descriptions-item label="Model">{{ config.model }}</el-descriptions-item>
          <el-descriptions-item label="Created">{{ formatDate(config.created_at) }}</el-descriptions-item>
        </el-descriptions>
        <div class="card-actions">
          <el-button type="primary" @click="openEdit">Edit</el-button>
          <el-button type="danger" @click="handleDelete">Delete</el-button>
        </div>
      </el-card>

      <el-card class="card" header="Active Agents">
        <div class="agent-list">
          <div v-for="agent in agents" :key="agent.type" class="agent-item">
            <div class="agent-info">
              <el-icon><Monitor /></el-icon>
              <span class="agent-name">{{ agent.label }}</span>
              <el-tag v-if="agent.active_config_id === configId" type="success" size="small">Active</el-tag>
              <el-tag v-else type="info" size="small">Inactive</el-tag>
            </div>
            <el-switch
              :model-value="agent.active_config_id === configId"
              @change="(val) => toggleAgent(agent, val)"
            />
          </div>
        </div>
      </el-card>

      <el-card class="card" header="Usage">
        <el-tabs v-model="activeAgentTab">
          <el-tab-pane
            v-for="agent in config._active_agents_list || []"
            :key="agent"
            :label="agentLabel(agent)"
            :name="agent"
          >
            <div v-if="usageData?.by_agent?.[agent]">
              <div class="usage-summary">
                <div class="summary-item">
                  <div class="summary-label">Requests</div>
                  <div class="summary-value">{{ usageData.by_agent[agent].requests }}</div>
                </div>
                <div class="summary-item">
                  <div class="summary-label">Input Tokens</div>
                  <div class="summary-value">{{ formatTokens(usageData.by_agent[agent].input_tokens) }}</div>
                </div>
                <div class="summary-item">
                  <div class="summary-label">Output Tokens</div>
                  <div class="summary-value">{{ formatTokens(usageData.by_agent[agent].output_tokens) }}</div>
                </div>
              </div>
              <div ref="chartRef" class="usage-chart"></div>
            </div>
            <el-empty v-else description="No usage data" />
          </el-tab-pane>
        </el-tabs>
      </el-card>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, nextTick } from 'vue'
import { ElMessageBox } from 'element-plus'
import { Monitor } from '@element-plus/icons-vue'
import { getConfig, deleteConfig, activateConfig, deactivateConfig, getUsage } from '../api/index.js'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { BarChart } from 'echarts/charts'
import { GridComponent, TooltipComponent } from 'echarts/components'
import VChart from 'vue-echarts'

use([CanvasRenderer, BarChart, GridComponent, TooltipComponent])

const props = defineProps(['configId', 'agents'])
defineEmits(['back', 'updated'])

const loading = ref(true)
const config = ref(null)
const activeAgentTab = ref('')
const usageData = ref(null)
const chartRef = ref(null)

async function loadConfig() {
  loading.value = true
  try {
    const [cfg, agentsList] = await Promise.all([
      getConfig(props.configId),
      getAgents()
    ])
    config.value = cfg
    config.value._active_agents_list = cfg.active_agents || []
    if (config.value._active_agents_list.length > 0) {
      activeAgentTab.value = config.value._active_agents_list[0]
    }
    await loadUsage()
  } finally {
    loading.value = false
  }
}

async function loadUsage() {
  try {
    usageData.value = await getUsage(props.configId)
    await nextTick()
    renderChart()
  } catch (e) {}
}

function renderChart() {
  if (!usageData.value?.daily_usage || !chartRef.value) return

  const agentData = usageData.value.daily_usage.filter(d => d.agent_type === activeAgentTab.value)
  const dates = agentData.map(d => d.date)
  const inputTokens = agentData.map(d => d.input_tokens)
  const outputTokens = agentData.map(d => d.output_tokens)

  const chart = chartRef.value
  if (chart) {
    chart.setOption({
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
      grid: { left: '3%', right: '4%', bottom: '3%', containLabel: true },
      xAxis: { type: 'category', data: dates },
      yAxis: { type: 'value' },
      series: [
        { name: 'Input', type: 'bar', data: inputTokens, itemStyle: { color: '#67c23a' } },
        { name: 'Output', type: 'bar', data: outputTokens, itemStyle: { color: '#409eff' } }
      ]
    })
  }
}

function agentLabel(type) {
  const found = props.agents.find(a => a.type === type)
  return found ? found.label : type
}

async function toggleAgent(agent, active) {
  try {
    if (active) {
      await activateConfig(props.configId, agent.type)
    } else {
      await deactivateConfig(props.configId, agent.type)
    }
    await loadConfig()
    $emit('updated')
  } catch (e) {
    ElMessageBox.alert(e.message || 'Failed to toggle agent', 'Error')
  }
}

function openEdit() {
  window.__openEdit(props.configId)
}

async function handleDelete() {
  try {
    await ElMessageBox.confirm('Delete this config? This cannot be undone.', 'Confirm Delete', {
      type: 'warning'
    })
    await deleteConfig(props.configId)
    $emit('updated')
    $emit('back')
  } catch (e) {
    if (e !== 'cancel') throw e
  }
}

function formatDate(date) {
  return new Date(date).toLocaleString()
}

function formatTokens(tokens) {
  if (!tokens) return '0'
  if (tokens >= 10000) return (tokens / 10000).toFixed(1) + '万'
  return tokens.toLocaleString()
}

onMounted(loadConfig)
</script>

<style scoped>
.detail-container { padding: 20px 0; }
.page-header { margin-bottom: 24px; }
.header-title { font-size: 18px; font-weight: 500; }
.card { margin-bottom: 16px; }
.card-actions { margin-top: 16px; display: flex; gap: 12px; }
.agent-list { display: flex; flex-direction: column; gap: 12px; }
.agent-item { display: flex; justify-content: space-between; align-items: center; padding: 8px 0; }
.agent-info { display: flex; align-items: center; gap: 8px; }
.agent-name { font-weight: 500; }
.usage-summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 20px; }
.summary-item { text-align: center; padding: 12px; background: #f5f7fa; border-radius: 8px; }
.summary-label { font-size: 12px; color: #909399; margin-bottom: 4px; }
.summary-value { font-size: 20px; font-weight: 600; color: #303133; }
.usage-chart { height: 300px; }
</style>
