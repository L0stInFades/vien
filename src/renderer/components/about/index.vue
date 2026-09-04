<template>
  <div class="about-dialog">
    <el-dialog
      v-model="showAboutDialog"
      :show-close="false"
      :modal="true"
      custom-class="ag-dialog-table"
      width="420px"
    >
      <div class="about-hero" data-testid="about-dialog">
        <div class="logo-shell">
          <div class="logo-halo"></div>
          <img class="logo" :src="logo" alt="Vien logo" data-testid="about-logo" />
        </div>
        <div class="eyebrow">For Long Stretches Of Attention</div>
          <h3 class="title" data-testid="about-title">{{ name }}</h3>
          <div class="version" data-testid="about-version">Version {{ appVersion }}</div>
        <p class="subtitle">{{ subtitle }}</p>
        <div class="inspiration-card">
          <div class="inspiration-label">{{ inspirationLabel }}</div>
          <p class="inspiration-copy">{{ inspirationCopy }}</p>
        </div>
      </div>
      <el-row class="about-meta">
        <el-col :span="24">
          <div class="text">{{ inspirationCredit }}</div>
        </el-col>
        <el-col :span="24">
          <div class="text">{{ lineage }}</div>
        </el-col>
        <el-col :span="24">
          <div class="text">{{ copyright }}</div>
        </el-col>
      </el-row>
    </el-dialog>
  </div>
</template>

<script>
import { mapState } from 'vuex'
import bus from '../../bus'
import VienLogo from '../../assets/images/logo.png'

export default {
  data() {
    this.name = 'Vien'
    this.subtitle = 'A quiet desktop editor for writing, reading, and revision in one continuous surface.'
    this.inspirationLabel = 'After A Track On Is Peace Wild?'
    this.inspirationCopy =
      'The name comes from a record that keeps calm and tension in the same hand. Vien tries to keep that balance on the page.'
    this.inspirationCredit =
      'Ludwig Wandinger works across percussion, electronics, and visual form with unusual restraint. That sense of space matters here.'
    this.lineage = 'Built from an open Markdown lineage, then pared back into something quieter.'
    this.copyright = `Copyright © ${new Date().getFullYear()} L0stInFades`
    this.logo = VienLogo
    return {
      showAboutDialog: false,
    }
  },
  computed: {
    ...mapState({
      appVersion: (state) => state.appVersion,
    }),
  },
  created() {
    bus.on('aboutDialog', this.showDialog)
  },
  beforeUnmount() {
    bus.off('aboutDialog', this.showDialog)
  },
  methods: {
    showDialog() {
      this.showAboutDialog = true
      bus.emit('editor-blur')
    },
  },
}
</script>

<style>
  .about-dialog .el-row,
  .about-dialog .el-col {
    display: block;
  }

  .about-dialog .el-dialog {
    overflow: hidden;
  }

  .about-dialog .el-dialog__body {
    padding: 18px 26px 28px;
  }

  .about-dialog .about-hero {
    position: relative;
    padding: 8px 0 20px;
    text-align: center;
  }

  .about-dialog .logo-shell {
    position: relative;
    width: 104px;
    height: 104px;
    margin: 0 auto 18px;
    display: grid;
    place-items: center;
  }

  .about-dialog .logo-halo {
    display: none;
  }

  .about-dialog img.logo {
    width: 88px;
    height: 88px;
    border-radius: 26px;
    box-shadow: var(--floatShadow);
    position: relative;
    z-index: 1;
  }

  .about-dialog .eyebrow {
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--editorColor40);
  }

  .about-dialog .title,
  .about-dialog .text {
    text-align: center;
  }

  .about-dialog .title {
    margin: 10px 0 10px;
    min-height: auto;
    font-size: 20px;
    font-weight: 600;
    color: var(--sideBarTitleColor);
  }

  .about-dialog .version {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 7px 12px;
    border-radius: 999px;
    border: 1px solid var(--editorColor10);
    background: var(--itemBgColor);
    color: var(--editorColor80);
    font-size: 13px;
    font-weight: 600;
  }

  .about-dialog .subtitle {
    max-width: 280px;
    margin: 14px auto 0;
    font-size: 13px;
    line-height: 1.6;
    color: var(--editorColor60);
  }

  .about-dialog .inspiration-card {
    max-width: 320px;
    margin: 16px auto 0;
    padding: 12px 14px;
    border: 1px solid var(--editorColor10);
    border-radius: 10px;
    background: var(--itemBgColor);
    text-align: left;
  }

  .about-dialog .inspiration-label {
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--editorColor40);
  }

  .about-dialog .inspiration-copy {
    margin: 8px 0 0;
    font-size: 13px;
    line-height: 1.65;
    color: var(--editorColor60);
  }

  .about-dialog .about-meta {
    margin-top: 6px;
    padding-top: 16px;
    border-top: 1px solid var(--editorColor10);
  }

  .about-dialog .text {
    min-height: auto;
    font-size: 13px;
    line-height: 1.7;
    color: var(--editorColor40);
  }
</style>
