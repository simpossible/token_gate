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

        <el-form-item label="API URL" prop="url">
          <el-input v-model="form.url" placeholder="https://api.anthropic.com" />
        </el-form-item>

        <el-form-item label="API Key" prop="api_key">
          <el-input
            v-model="form.api_key"
            type="password"
            placeholder="sk-ant-..."
            show-password
          />
        </el-form-item>

        <el-form-item label="Model" prop="model">
          <el-select v-model="form.model" style="width: 100%">
            <el-option value="claude-sonnet-4-6" label="Claude Sonnet 4.6" />
            <el-option value="claude-opus-4-7" label="Claude Opus 4.7" />
            <el-option value="claude-haiku-4-5-20251001" label="Claude Haiku 4.5" />
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
import { ref, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { createConfig, updateConfig, getConfig } from '../api/index.js'

const props = defineProps({
  configId: String,
  editMode: Boolean
})
const emit = defineEmits(['back', 'saved'])

const formRef = ref(null)
const submitting = ref(false)
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

async function loadConfig() {
  if (props.configId) {
    const cfg = await getConfig(props.configId)
    form.value = {
      name: cfg.name,
      url: cfg.url,
      api_key: '', // don't pre-fill key for security
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

onMounted(loadConfig)
</script>

<style scoped>
.form-container { padding: 20px 0; }
.page-header { margin-bottom: 24px; }
.header-title { font-size: 18px; font-weight: 500; }
.form-card { max-width: 600px; }
</style>
