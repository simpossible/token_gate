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
              <el-tag v-if="isActiveForAgent(agent)" type="success" size="small">Active</el-tag>
              <el-tag v-else type="info" size="small">Inactive</el-tag>
            </div>
            <el-switch
              :model-value="isActiveForAgent(agent)"
              @change="(val) => toggleAgent(agent, val)"
            />
          </div>
        </div>
      </el-card>

      <el-card class="card" header="Usage">
        <div v-if="usageTabs.length > 0">
          <el-tabs v-model="activeAgentTab" @tab-change="onTabChange">
            <el-tab-pane
              v-for="agentType in usageTabs"
              :key="agentType"
              :label="agentLabel(agentType)"
              :name="agentType"
            >
              <div class="usage-summary" v-if="usageData?.by_agent?.[agentType]">
                <div class="summary-item">
                  <div class="summary-label">Requests</div>
                  <div class="summary-value">{{ usageData.by_agent[agentType].requests }}</div>
                </div>
                <div class="summary-item">
                  <div class="summary-label">Input Tokens</div>
                  <div class="summary-value">{{ formatTokens(usageData.by_agent[agentType].input_tokens) }}</div>
                </div>
                <div class="summary-item">
                  <div class="summary-label">Output Tokens</div>
                  <div class="summary-value">{{ formatTokens(usageData.by_agent[agentType].output_tokens) }}</div>
                </div>
              </div>
              <el-empty v-else description="No usage data" />
            </el-tab-pane>
          </el-tabs>
          <div
            v-if="usageData?.by_agent?.[activeAgentTab]"
            ref="chartRef"
            class="usage-chart"
          ></div>
        </div>
        <el-empty v-else description="No usage data" />
      </el-card>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
import { ElMessageBox } from 'element-plus'
import { Monitor } from '@element-plus/icons-vue'
import { getConfig, deleteConfig, activateConfig, deactivateConfig, getUsage } from '../api/index.js'
import * as echarts from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { BarChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components'

echarts.use([CanvasRenderer, BarChart, GridComponent, TooltipComponent, LegendComponent])

const props = defineProps(['configId', 'agents'])
const emit = defineEmits(['back', 'updated'])

const loading = ref(true)
const config = ref(null)
const activeAgentTab = ref('')
const usageData = ref(null)
const chartRef = ref(null)
let chartInstance = null

function isActiveForAgent(agent) {
  return agent.active_config_id === props.configId
}

const usageTabs = computed(() => {
  if (!usageData.value?.by_agent) return []
  return Object.keys(usageData.value.by_agent)
})

async function loadConfig() {
  loading.value = true
  try {
    config.value = await getConfig(props.configId)
    await loadUsage()
  } finally {
    loading.value = false
  }
}

async function loadUsage() {
  try {
    usageData.value = await getUsage(props.configId)
    const tabs = Object.keys(usageData.value?.by_agent || {})
    if (tabs.length > 0 && !activeAgentTab.value) {
      activeAgentTab.value = tabs[0]
    }
    await nextTick()
    renderChart()
  } catch (_) {
    // no usage yet
  }
}

function renderChart() {
  if (!usageData.value?.daily_usage || !chartRef.value) return

  const agentData = usageData.value.daily_usage.filter(d => d.agent_type === activeAgentTab.value)
  if (agentData.length === 0) return

  if (chartInstance) {
    chartInstance.dispose()
    chartInstance = null
  }
  chartInstance = echarts.init(chartRef.value)
  chartInstance.setOption({
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
    legend: { data: ['Input', 'Output'] },
    grid: { left: '3%', right: '4%', bottom: '3%', containLabel: true },
    xAxis: { type: 'category', data: agentData.map(d => d.date) },
    yAxis: { type: 'value' },
    series: [
      { name: 'Input', type: 'bar', data: agentData.map(d => d.input_tokens), itemStyle: { color: '#67c23a' } },
      { name: 'Output', type: 'bar', data: agentData.map(d => d.output_tokens), itemStyle: { color: '#409eff' } }
    ]
  })
}

async function onTabChange() {
  await nextTick()
  renderChart()
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
    emit('updated')
  } catch (e) {
    ElMessageBox.alert(e?.response?.data?.error || e.message || 'Failed to toggle agent', 'Error')
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
    emit('updated')
    emit('back')
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

onUnmounted(() => {
  if (chartInstance) {
    chartInstance.dispose()
    chartInstance = null
  }
})
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
.usage-chart { height: 300px; margin-top: 16px; }
</style>
