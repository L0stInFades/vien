<template>
  <div class="print-settings-dialog" data-testid="export-dialog-shell">
    <el-dialog
      v-model="showExportSettingsDialog"
      :show-close="false"
      :modal="true"
      custom-class="ag-dialog-table"
      width="500px"
    >
      <h3 data-testid="export-dialog-title">Export</h3>
      <el-tabs v-model="activeName">
        <el-tab-pane label="Overview" name="info">
          <span class="text">Set the page, then let it leave in one piece.</span>
        </el-tab-pane>
        <el-tab-pane label="Page" name="page">
          <!-- HTML -->
          <div v-if="!isPrintable">
            <text-box
              description="The page title:"
              :textValue="htmlTitle"
              :emitTime="0"
              :onChange="value => onSelectChange('htmlTitle', value)"
            ></text-box>
          </div>

          <!-- PDF/Print -->
          <div v-if="isPrintable">
            <div v-if="exportType === 'pdf'">
              <cur-select
                class="page-size-select"
                description="Page size:"
                :currentValue="pageSize"
                :options="pageSizeList"
                :onChange="value => onSelectChange('pageSize', value)"
              ></cur-select>
              <div v-if="pageSize === 'custom'" class="row">
                <div>Width/Height in mm:</div>
                <el-input-number v-model="pageSizeWidth" size="mini" controls-position="right" :min="100"></el-input-number>
                <el-input-number v-model="pageSizeHeight" size="mini" controls-position="right" :min="100"></el-input-number>
              </div>

              <bool
                description="Landscape orientation:"
                :isOn="isLandscape"
                :onChange="value => onSelectChange('isLandscape', value)"
              ></bool>
            </div>

            <div class="row">
              <div class="description">Page margin in mm:</div>
              <div>
                <div class="label">Top/Bottom:</div>
                <el-input-number v-model="pageMarginTop" size="mini" controls-position="right" :min="0" :max="100"></el-input-number>
                <el-input-number v-model="pageMarginBottom" size="mini" controls-position="right" :min="0" :max="100"></el-input-number>
              </div>
              <div>
                <div class="label">Left/Right:</div>
                <el-input-number v-model="pageMarginLeft" size="mini" controls-position="right" :min="0" :max="100"></el-input-number>
                <el-input-number v-model="pageMarginRight" size="mini" controls-position="right" :min="0" :max="100"></el-input-number>
              </div>
            </div>
          </div>
        </el-tab-pane>
        <el-tab-pane label="Style" name="style">
          <bool
            description="Overwrite theme font settings:"
            :isOn="fontSettingsOverwrite"
            :onChange="value => onSelectChange('fontSettingsOverwrite', value)"
          ></bool>
          <div v-if="fontSettingsOverwrite">
            <font-text-box
              description="Font family:"
              :selectedFont="fontFamily"
              :onChange="value => onSelectChange('fontFamily', value)"
            ></font-text-box>
            <range
              description="Font size"
              :currentValue="fontSize"
              :min="8"
              :max="32"
              unit="px"
              :step="1"
              :onChange="value => onSelectChange('fontSize', value)"
            ></range>
            <range
              description="Line height"
              :currentValue="lineHeight"
              :min="1.0"
              :max="2.0"
              :step="0.1"
              :onChange="value => onSelectChange('lineHeight', value)"
            ></range>
          </div>
          <bool
            description="Auto numbering headings:"
            :isOn="autoNumberingHeadings"
            :onChange="value => onSelectChange('autoNumberingHeadings', value)"
          ></bool>
          <bool
            description="Show front matter:"
            :isOn="showFrontMatter"
            :onChange="value => onSelectChange('showFrontMatter', value)"
          ></bool>
        </el-tab-pane>
        <el-tab-pane label="Theme" name="theme">
          <div class="text">Choose a theme for the exported page, or bring in one you made yourself.</div>
          <cur-select
            description="Theme:"
            more="https://github.com/L0stInFades/vien/blob/develop/docs/EXPORT_THEMES.md"
            :currentValue="theme"
            :options="themeList"
            :onChange="value => onSelectChange('theme', value)"
          ></cur-select>
        </el-tab-pane>
        <el-tab-pane v-if="isPrintable" label="Header & Footer" name="header">
          <div class="text">Headers and footers repeat across every page once they are defined.</div>
          <cur-select
            description="Header type:"
            :currentValue="headerType"
            :options="headerFooterTypes"
            :onChange="value => onSelectChange('headerType', value)"
          ></cur-select>
          <text-box
            v-if="headerType === 2"
            description="The left header text:"
            :textValue="headerTextLeft"
            :emitTime="0"
            :onChange="value => onSelectChange('headerTextLeft', value)"
          ></text-box>
          <text-box
            v-if="headerType !== 0"
            description="The main header text:"
            :textValue="headerTextCenter"
            :emitTime="0"
            :onChange="value => onSelectChange('headerTextCenter', value)"
          ></text-box>
          <text-box
            v-if="headerType === 2"
            description="The right header text:"
            :textValue="headerTextRight"
            :emitTime="0"
            :onChange="value => onSelectChange('headerTextRight', value)"
          ></text-box>

          <cur-select
            description="Footer type:"
            :currentValue="footerType"
            :options="headerFooterTypes"
            :onChange="value => onSelectChange('footerType', value)"
          ></cur-select>
          <text-box
            v-if="footerType === 2"
            description="The left footer text:"
            :textValue="footerTextLeft"
            :emitTime="0"
            :onChange="value => onSelectChange('footerTextLeft', value)"
          ></text-box>
          <text-box
            v-if="footerType !== 0"
            description="The main footer text:"
            :textValue="footerTextCenter"
            :emitTime="0"
            :onChange="value => onSelectChange('footerTextCenter', value)"
          ></text-box>
          <text-box
            v-if="footerType === 2"
            description="The right footer text:"
            :textValue="footerTextRight"
            :emitTime="0"
            :onChange="value => onSelectChange('footerTextRight', value)"
          ></text-box>

          <bool
            description="Customize style:"
            :isOn="headerFooterCustomize"
            :onChange="value => onSelectChange('headerFooterCustomize', value)"
          ></bool>

          <div v-if="headerFooterCustomize">
            <bool
              description="Allow styled header and footer:"
              :isOn="headerFooterStyled"
              :onChange="value => onSelectChange('headerFooterStyled', value)"
            ></bool>
            <range
              description="Header and footer font size"
              :currentValue="headerFooterFontSize"
              :min="8"
              :max="20"
              unit="px"
              :step="1"
              :onChange="value => onSelectChange('headerFooterFontSize', value)"
            ></range>
          </div>
        </el-tab-pane>

        <el-tab-pane label="Table of Contents" name="toc">
          <bool
            description="Include top heading:"
            detailedDescription="Includes the first heading level too."
            :isOn="tocIncludeTopHeading"
            :onChange="value => onSelectChange('tocIncludeTopHeading', value)"
          ></bool>
          <text-box
            description="Title:"
            :textValue="tocTitle"
            :emitTime="0"
            :onChange="value => onSelectChange('tocTitle', value)"
          ></text-box>
         </el-tab-pane>
      </el-tabs>
      <div class="button-controlls">
        <button class="button-primary" data-testid="export-confirm" @click="handleClicked">
          Export...
        </button>
      </div>
    </el-dialog>
  </div>
</template>

<script>
import { mapState } from 'vuex'
import bus from '../../bus'
import { unwrapCapability } from '@/services/capability'
import Bool from '@/prefComponents/common/bool'
import CurSelect from '@/prefComponents/common/select'
import FontTextBox from '@/prefComponents/common/fontTextBox'
import Range from '@/prefComponents/common/range'
import TextBox from '@/prefComponents/common/textBox'
import { pageSizeList, headerFooterTypes, headerFooterStyles, exportThemeList } from './exportOptions'

export default {
  components: {
    Bool,
    CurSelect,
    FontTextBox,
    Range,
    TextBox,
  },
  data() {
    this.exportType = ''
    this.themesLoaded = false
    this.pageSizeList = pageSizeList
    this.headerFooterTypes = headerFooterTypes
    this.headerFooterStyles = headerFooterStyles
    return {
      isPrintable: true,
      showExportSettingsDialog: false,
      activeName: 'info',
      htmlTitle: '',
      pageSize: 'A4',
      pageSizeWidth: 210,
      pageSizeHeight: 297,
      isLandscape: false,
      pageMarginTop: 20,
      pageMarginRight: 15,
      pageMarginBottom: 20,
      pageMarginLeft: 15,
      fontSettingsOverwrite: false,
      fontFamily: 'Default',
      fontSize: 14,
      lineHeight: 1.5,
      autoNumberingHeadings: false,
      showFrontMatter: false,
      theme: 'default',
      themeList: exportThemeList,
      headerType: 0,
      headerTextLeft: '',
      headerTextCenter: '',
      headerTextRight: '',
      footerType: 0,
      footerTextLeft: '',
      footerTextCenter: '',
      footerTextRight: '',
      headerFooterCustomize: false,
      headerFooterStyled: true,
      headerFooterFontSize: 12,
      tocTitle: '',
      tocIncludeTopHeading: true,
    }
  },
  computed: {
    ...mapState({}),
  },
  created() {
    bus.on('showExportDialog', this.showDialog)
  },
  beforeUnmount() {
    bus.off('showExportDialog', this.showDialog)
  },
  methods: {
    showDialog(type) {
      this.exportType = type
      this.isPrintable = type !== 'styledHtml'
      if (!this.isPrintable && (this.activeName === 'header' || this.activeName === 'page')) {
        this.activeName = 'info'
      }

      this.showExportSettingsDialog = true
      bus.emit('editor-blur')

      if (!this.themesLoaded) {
        this.themesLoaded = true
        this.loadThemesFromDisk()
      }
    },
    handleClicked() {
      const {
        exportType,
        isPrintable,
        htmlTitle,
        pageSize,
        pageSizeWidth,
        pageSizeHeight,
        isLandscape,
        pageMarginTop,
        pageMarginRight,
        pageMarginBottom,
        pageMarginLeft,
        fontSettingsOverwrite,
        fontFamily,
        fontSize,
        lineHeight,
        autoNumberingHeadings,
        showFrontMatter,
        theme,
        headerType,
        headerTextLeft,
        headerTextCenter,
        headerTextRight,
        footerType,
        footerTextLeft,
        footerTextCenter,
        footerTextRight,
        headerFooterCustomize,
        headerFooterStyled,
        headerFooterFontSize,
        tocTitle,
        tocIncludeTopHeading,
      } = this
      const options = {
        type: exportType,
        pageSize,
        pageSizeWidth,
        pageSizeHeight,
        isLandscape,
        pageMarginTop,
        pageMarginRight,
        pageMarginBottom,
        pageMarginLeft,
        autoNumberingHeadings,
        showFrontMatter,
        theme: theme === 'default' ? null : theme,
        tocTitle,
        tocIncludeTopHeading,
      }

      if (!isPrintable) {
        options.htmlTitle = htmlTitle
      }

      if (fontSettingsOverwrite) {
        Object.assign(options, {
          fontSize,
          lineHeight,
          fontFamily: fontFamily === 'Default' ? null : fontFamily,
        })
      }

      if (headerType !== 0) {
        Object.assign(options, {
          header: {
            type: headerType,
            left: headerTextLeft,
            center: headerTextCenter,
            right: headerTextRight,
          },
        })
      }

      if (footerType !== 0) {
        Object.assign(options, {
          footer: {
            type: footerType,
            left: footerTextLeft,
            center: footerTextCenter,
            right: footerTextRight,
          },
        })
      }

      if (headerFooterCustomize) {
        Object.assign(options, {
          headerFooterStyled,
          headerFooterFontSize,
        })
      }

      this.showExportSettingsDialog = false
      bus.emit('export', options)
    },
    onSelectChange(key, value) {
      this[key] = value
    },
    async loadThemesFromDisk() {
      try {
        const { themes } = await unwrapCapability(window.api.exportThemes.list())
        for (const { name, label } of themes) {
          this.themeList.push({
            value: name,
            label,
          })
        }
      } catch (e) {
        console.error('loadThemesFromDisk failed:', e)
      }
    },
  },
}
</script>

<style scoped>
  .print-settings-dialog {
    user-select: none;
  }
  .row {
    margin-bottom: 8px;
  }
  .description {
    margin-bottom: 10px;
    white-space: pre-wrap;
    word-break: break-word;
  }
  .label {
    margin-bottom: 5px;
  }
  .label ~ div {
    margin-right: 20px;
  }
  .text {
    white-space: pre-wrap;
    word-break: break-word;
  }

  .button-controlls {
    margin-top: 8px;
    text-align: right;
  }

  .button-controlls .button-primary {
    font-size: 14px;
  }

  .el-tab-pane section:first-child {
    margin-top: 0;
  }
</style>
<style>
  .print-settings-dialog #pane-header .pref-text-box-item .el-input {
    width: 90% !important;
  }

  .print-settings-dialog .el-dialog__body {
    padding: 0 20px 20px 20px;
  }
  .print-settings-dialog .pref-select-item .el-select {
    width: 240px;
  }
  .print-settings-dialog .el-tabs__content {
    max-height: 350px;
    overflow-x: hidden;
    overflow-y: auto;
  }

  .print-settings-dialog .el-tabs__content::-webkit-scrollbar:vertical {
    width: 5px;
  }
</style>
