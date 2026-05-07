<template>
  <div class="app">
    <el-container>
      <el-header class="app-header">
        <h1 class="app-title" @click="currentPage = 'list'">Token Gate</h1>
      </el-header>
      <el-main>
        <ConfigList
          v-if="currentPage === 'list'"
          :configs="configs"
          :agents="agents"
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
          @back="currentPage = 'list'"
          @saved="onCreated"
        />
        <ConfigForm
          v-else-if="currentPage === 'edit'"
          :config-id="selectedConfigId"
          :edit-mode="true"
          @back="openDetail(selectedConfigId)"
          @saved="onCreated"
        />
      </el-main>
    </el-container>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { getConfigs, getAgents } from './api/index.js'
import ConfigList from './views/ConfigList.vue'
import ConfigDetail from './views/ConfigDetail.vue'
import ConfigForm from './views/ConfigForm.vue'

const currentPage = ref('list')
const selectedConfigId = ref(null)
const configs = ref([])
const agents = ref([])

async function loadConfigs() {
  configs.value = await getConfigs()
}

async function loadAgents() {
  agents.value = await getAgents()
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
  await Promise.all([loadConfigs(), loadAgents()])
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
}
.app-title {
  font-size: 20px;
  font-weight: 600;
  cursor: pointer;
}
.el-main { padding: 24px; max-width: 1200px; margin: 0 auto; }
</style>
