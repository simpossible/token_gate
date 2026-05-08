<template>
  <div class="form-container">
    <el-page-header @back="$emit('back')" title="Back" class="page-header">
      <template #content>
        <span class="header-title">{{ editMode ? 'Edit Config' : 'New Config' }}</span>
      </template>
    </el-page-header>

    <el-card class="form-card">
      <el-form :model="form" label-width="100px" :rules="rules" ref="formRef">
        <el-form-item label="Name" prop="name">
          <el-input v-model="form.name" placeholder="Config display name" />
        </el-form-item>

        <el-form-item label="厂商 / URL" prop="url">
          <el-select
            v-model="form.url"
            filterable
            allow-create
            default-first-option
            style="width: 100%"
            placeholder="选择厂商或直接输入 API URL"
            @change="onUrlChange"
          >
            <el-option
              v-for="c in companies"
              :key="c.url"
              :value="c.url"
              :label="`${c.name} — ${c.url}`"
            />
          </el-select>
        </el-form-item>

        <el-form-item label="API Key" prop="api_key">
          <el-input v-model="form.api_key" type="password" placeholder="sk-ant-..." show-password />
        </el-form-item>

        <el-form-item label="Model" prop="model">
          <el-select
            v-model="form.model"
            filterable
            allow-create
            default-first-option
            style="width: 100%"
            placeholder="选择或输入 model 名称"
          >
            <el-option
              v-for="m in currentModels"
              :key="m"
              :value="m"
              :label="m"
            />
          </el-select>
        </el-form-item>

        <el-form-item>
          <el-button type="primary" @click="submit" :loading="submitting">Save</el-button>
          <el-button @click="$emit('back')">Cancel</el-button>
        </el-form-item>
      </el-form>
    </el-card>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { createConfig, updateConfig, getConfig, getCompanies } from '../api/index.js'

const props = defineProps({
  configId: String,
  editMode: Boolean
})
const emit = defineEmits(['back', 'saved'])

const formRef = ref(null)
const submitting = ref(false)
const companies = ref([])
const form = ref({
  name: '',
  url: 'https://api.anthropic.com',
  api_key: '',
  model: 'claude-sonnet-4-6'
})
const rules = {
  name: [{ required: true, message: 'Name is required', trigger: 'blur' }],
  url: [{ required: true, message: 'URL is required', trigger: 'blur' }],
  api_key: [{ required: true, message: 'API Key is required', trigger: 'blur' }],
  model: [{ required: true, message: 'Model is required', trigger: 'change' }]
}

const currentModels = computed(() => {
  const found = companies.value.find(c => c.url === form.value.url)
  return found ? found.models : []
})

function onUrlChange(val) {
  const found = companies.value.find(c => c.url === val)
  if (found && found.models.length > 0) {
    form.value.model = found.models[0]
  }
}

async function loadCompanies() {
  try {
    const data = await getCompanies()
    if (data && Array.isArray(data.list)) {
      companies.value = data.list
    }
  } catch (e) {
    // non-critical: fall back to empty list (user can still type custom URL/model)
  }
}

async function loadConfig() {
  if (props.configId) {
    const cfg = await getConfig(props.configId)
    form.value = {
      name: cfg.name,
      url: cfg.url,
      api_key: '',
      model: cfg.model
    }
  }
}

async function submit() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) return

  submitting.value = true
  try {
    if (props.configId) {
      await updateConfig(props.configId, form.value)
      ElMessage.success('Config updated')
    } else {
      await createConfig(form.value)
      ElMessage.success('Config created')
    }
    emit('saved')
  } catch (e) {
    ElMessage.error(e.message || 'Failed to save config')
  } finally {
    submitting.value = false
  }
}

onMounted(async () => {
  await loadCompanies()
  await loadConfig()
})
</script>

<style scoped>
.form-container {
  padding: 20px 0;
}

.page-header {
  margin-bottom: 24px;
}

.header-title {
  font-size: 18px;
  font-weight: 500;
}

.form-card {
  max-width: 600px;
}
</style>
