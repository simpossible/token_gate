<template>
  <div class="app">
    <el-container>
      <el-header class="app-header">
        <h1 class="app-title" @click="currentPage = 'list'">Token Gate</h1>
        <div class="agent-tabs" v-if="agents.length > 0">
          <span
            v-for="agent in agents"
            :key="agent.type"
            :class="['agent-tab', { active: selectedAgentType === agent.type }]"
            @click="selectAgentType(agent.type)"
          >
            {{ agent.label }}
          </span>
        </div>
      </el-header>
      <el-main>
        <ConfigList
          v-if="currentPage === 'list'"
          :configs="configs"
          :agents="agents"
          :selected-agent-type="selectedAgentType"
          @open-detail="openDetail"
          @open-create="openCreate"
        />
        <ConfigDetail
          v-else-if="currentPage === 'detail'"
          :config-id="selectedConfigId"
          :agents="agents"
          @back="currentPage = 'list'"
          @updated="onDetailUpdated"
        />
        <ConfigForm
          v-else-if="currentPage === 'create'"
          :companies="companies"
          :agents="agents"
          :selected-agent-type="selectedAgentType"
          @back="currentPage = 'list'"
          @saved="onCreated"
        />
        <ConfigForm
          v-else-if="currentPage === 'edit'"
          :config-id="selectedConfigId"
          :edit-mode="true"
          :companies="companies"
          :agents="agents"
          :selected-agent-type="selectedAgentType"
          @back="openDetail(selectedConfigId)"
          @saved="onCreated"
        />
      </el-main>
    </el-container>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { getConfigs, getAgents, getCompanies } from './api/index.js'
import ConfigList from './views/ConfigList.vue'
import ConfigDetail from './views/ConfigDetail.vue'
import ConfigForm from './views/ConfigForm.vue'

const currentPage = ref('list')
const selectedConfigId = ref(null)
const configs = ref([])
const agents = ref([])
const companies = ref([])
const selectedAgentType = ref('')

async function loadConfigs() {
  configs.value = await getConfigs(selectedAgentType.value || undefined)
}

async function loadAgents() {
  agents.value = await getAgents()
  // Auto-select first agent type if none selected
  if (!selectedAgentType.value && agents.value.length > 0) {
    selectedAgentType.value = agents.value[0].type
    await loadConfigs()
  }
}

function selectAgentType(type) {
  selectedAgentType.value = type
  currentPage.value = 'list'
  loadConfigs()
}

function openDetail(id) {
  selectedConfigId.value = id
  currentPage.value = 'detail'
}

function openCreate() {
  selectedConfigId.value = null
  currentPage.value = 'create'
}

function openEdit(id) {
  selectedConfigId.value = id
  currentPage.value = 'edit'
}

async function onDetailUpdated() {
  await Promise.all([loadConfigs(), loadAgents()])
}

async function onCreated() {
  await loadConfigs()
  await loadAgents()
  if (selectedConfigId.value) {
    currentPage.value = 'detail'
  } else {
    currentPage.value = 'list'
  }
}

onMounted(async () => {
  const [, , companiesData] = await Promise.all([loadConfigs(), loadAgents(), getCompanies()])
  if (companiesData?.list) companies.value = companiesData.list
})

// expose openEdit for child components
window.__openEdit = openEdit
</script>

<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f7fa; }
.app { min-height: 100vh; }
.app-header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  display: flex;
  align-items: center;
  padding: 0 24px;
  height: 56px !important;
  gap: 24px;
}
.app-title {
  font-size: 20px;
  font-weight: 600;
  cursor: pointer;
  white-space: nowrap;
}
.agent-tabs {
  display: flex;
  gap: 4px;
  align-items: center;
}
.agent-tab {
  padding: 6px 16px;
  border-radius: 20px;
  font-size: 14px;
  cursor: pointer;
  transition: background 0.2s, color 0.2s;
  background: rgba(255,255,255,0.15);
  color: rgba(255,255,255,0.85);
}
.agent-tab:hover {
  background: rgba(255,255,255,0.25);
}
.agent-tab.active {
  background: rgba(255,255,255,0.95);
  color: #667eea;
  font-weight: 600;
}
.el-main { padding: 24px; }
</style>
