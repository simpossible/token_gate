<template>
  <div>
    <div v-if="usages.length > 0">
      <div class="stats-row">
        <div class="stat-item">
          <div class="stat-label">Requests</div>
          <div class="stat-value">{{ usages.length }}</div>
        </div>
        <div class="stat-item">
          <div class="stat-label">Avg Latency</div>
          <div class="stat-value latency">{{ avgLatency }}ms</div>
        </div>
        <div class="stat-item">
          <div class="stat-label">Total Tokens</div>
          <div class="stat-value">{{ totalTokens }}</div>
        </div>
      </div>
      <div ref="latencyChartRef" class="chart"></div>
      <div ref="tokenChartRef" class="chart"></div>
    </div>
    <el-empty v-else description="No request data" />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
import { getUsages } from '../api/index.js'
import * as echarts from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { LineChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components'

echarts.use([CanvasRenderer, LineChart, GridComponent, TooltipComponent, LegendComponent])

const props = defineProps({ configId: String })

const usages = ref([])
const latencyChartRef = ref(null)
const tokenChartRef = ref(null)
let latencyChart = null
let tokenChart = null

const avgLatency = computed(() => {
  if (!usages.value.length) return 0
  const sum = usages.value.reduce((s, u) => s + u.latency_ms, 0)
  return Math.round(sum / usages.value.length)
})

const totalTokens = computed(() => {
  return usages.value.reduce((s, u) => s + u.input_tokens + u.output_tokens, 0)
})

function formatTime(dateStr) {
  const d = new Date(dateStr)
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  const hh = String(d.getHours()).padStart(2, '0')
  const min = String(d.getMinutes()).padStart(2, '0')
  return `${mm}-${dd} ${hh}:${min}`
}

function renderCharts() {
  if (!usages.value.length) return
  const xData = usages.value.map(u => formatTime(u.created_at_ts))

  if (latencyChartRef.value) {
    if (latencyChart) latencyChart.dispose()
    latencyChart = echarts.init(latencyChartRef.value)
    latencyChart.setOption({
      tooltip: { trigger: 'axis' },
      grid: { left: '3%', right: '4%', bottom: '3%', containLabel: true },
      xAxis: { type: 'category', data: xData, axisLabel: { rotate: 30 } },
      yAxis: { type: 'value', name: 'ms' },
      series: [{ name: 'Latency', type: 'line', data: usages.value.map(u => u.latency_ms), itemStyle: { color: '#f56c6c' }, lineStyle: { color: '#f56c6c' }, smooth: true }]
    })
  }

  if (tokenChartRef.value) {
    if (tokenChart) tokenChart.dispose()
    tokenChart = echarts.init(tokenChartRef.value)
    tokenChart.setOption({
      tooltip: { trigger: 'axis' },
      legend: { data: ['Input', 'Output'] },
      grid: { left: '3%', right: '4%', bottom: '3%', containLabel: true },
      xAxis: { type: 'category', data: xData, axisLabel: { rotate: 30 } },
      yAxis: { type: 'value' },
      series: [
        { name: 'Input', type: 'line', data: usages.value.map(u => u.input_tokens), itemStyle: { color: '#67c23a' }, lineStyle: { color: '#67c23a' }, smooth: true },
        { name: 'Output', type: 'line', data: usages.value.map(u => u.output_tokens), itemStyle: { color: '#409eff' }, lineStyle: { color: '#409eff' }, smooth: true }
      ]
    })
  }
}

onMounted(async () => {
  try {
    usages.value = await getUsages(props.configId, 7)
  } catch (_) {
    usages.value = []
  }
  // Wait for DOM to update before rendering charts
  await nextTick()
  renderCharts()
})

onUnmounted(() => {
  latencyChart?.dispose()
  tokenChart?.dispose()
})
</script>

<style scoped>
.stats-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 16px; }
.stat-item { text-align: center; padding: 12px; background: #f5f7fa; border-radius: 8px; }
.stat-label { font-size: 12px; color: #909399; margin-bottom: 4px; }
.stat-value { font-size: 20px; font-weight: 600; color: #303133; }
.stat-value.latency { color: #f56c6c; }
.chart { height: 240px; width: 100%; margin-top: 16px; }
</style>
