<template>
  <div class="pref-editor">
    <h4>Editor</h4>
    <compound>
      <template #head>
        <h6 class="title">Text editor settings:</h6>
      </template>
      <template #children>
        <range
          description="Font size"
          :currentValue="fontSize"
          :min="12"
          :max="32"
          unit="px"
          :step="1"
          :onChange="value => onSelectChange('fontSize', value)"
        ></range>
        <range
          description="Line height"
          :currentValue="lineHeight"
          :min="1.2"
          :max="2.0"
          :step="0.1"
          :onChange="value => onSelectChange('lineHeight', value)"
        ></range>
        <font-text-box
          description="Font family"
          :selectedFont="editorFontFamily"
          :onChange="value => onSelectChange('editorFontFamily', value)"
        ></font-text-box>
        <text-box
          description="Maximum width of text editor"
          notes="Leave empty for theme default, otherwise use number with unit suffix, which is one of 'ch' for characters, 'px' for pixels, or '%' for percentage."
          :textValue="editorLineWidth"
          :regexValidator="/^(?:$|[0-9]+(?:ch|px|%)$)/"
          :onChange="value => onSelectChange('editorLineWidth', value)"
        ></text-box>
      </template>
    </compound>

    <compound>
      <template #head>
        <h6 class="title">Code block settings:</h6>
      </template>
      <template #children>
        <range
          description="Font size"
          :currentValue="codeFontSize"
          :min="12"
          :max="28"
          unit="px"
          :step="1"
          :onChange="value => onSelectChange('codeFontSize', value)"
        ></range>
        <font-text-box
          description="Font family"
          :onlyMonospace="true"
          :selectedFont="codeFontFamily"
          :onChange="value => onSelectChange('codeFontFamily', value)"
        ></font-text-box>
        <!-- FIXME: Disabled due to #1648. -->
        <bool
          v-show="false"
          description="Show line numbers"
          :isOn="codeBlockLineNumbers"
          :onChange="value => onSelectChange('codeBlockLineNumbers', value)"
        ></bool>
        <bool
          description="Remove leading and trailing empty lines"
          :isOn="trimUnnecessaryCodeBlockEmptyLines"
          :onChange="value => onSelectChange('trimUnnecessaryCodeBlockEmptyLines', value)"
        ></bool>
      </template>
    </compound>

    <compound>
      <template #head>
        <h6 class="title">Writing behavior:</h6>
      </template>
      <template #children>
        <bool
          description="Automatically close brackets when writing"
          :isOn="autoPairBracket"
          :onChange="value => onSelectChange('autoPairBracket', value)"
        ></bool>
        <bool
          description="Automatically complete markdown syntax"
          :isOn="autoPairMarkdownSyntax"
          :onChange="value => onSelectChange('autoPairMarkdownSyntax', value)"
        ></bool>
        <bool
          description="Automatically close quotation marks"
          :isOn="autoPairQuote"
          :onChange="value => onSelectChange('autoPairQuote', value)"
        ></bool>
      </template>
    </compound>

    <compound>
      <template #head>
        <h6 class="title">File representation:</h6>
      </template>
      <template #children>
        <cur-select
          description="Preferred tab width"
          :currentValue="tabSize"
          :options="tabSizeOptions"
          :onChange="value => onSelectChange('tabSize', value)"
        ></cur-select>
        <cur-select
          description="Line separator type"
          :currentValue="endOfLine"
          :options="endOfLineOptions"
          :onChange="value => onSelectChange('endOfLine', value)"
        ></cur-select>
        <cur-select
          description="Default encoding"
          :currentValue="defaultEncoding"
          :options="defaultEncodingOptions"
          :onChange="value => onSelectChange('defaultEncoding', value)"
        ></cur-select>
        <bool
          description="Automatically detect file encoding"
          :isOn="autoGuessEncoding"
          :onChange="value => onSelectChange('autoGuessEncoding', value)"
        ></bool>
        <cur-select
          description="Handling of trailing newline characters"
          :currentValue="trimTrailingNewline"
          :options="trimTrailingNewlineOptions"
          :onChange="value => onSelectChange('trimTrailingNewline', value)"
        ></cur-select>
      </template>
    </compound>

    <compound>
      <template #head>
        <h6 class="title">Misc:</h6>
      </template>
      <template #children>
        <cur-select
          description="Text direction"
          :currentValue="textDirection"
          :options="textDirectionOptions"
          :onChange="value => onSelectChange('textDirection', value)"
        ></cur-select>
        <bool
          description="Hide hint for selecting type of new paragraph"
          :isOn="hideQuickInsertHint"
          :onChange="value => onSelectChange('hideQuickInsertHint', value)"
        ></bool>
        <bool
          description="Hide popup when cursor is over link"
          :isOn="hideLinkPopup"
          :onChange="value => onSelectChange('hideLinkPopup', value)"
        ></bool>
        <bool
          description="Whether to automatically check any related tasks"
          :isOn="autoCheck"
          :onChange="value => onSelectChange('autoCheck', value)"
        ></bool>
      </template>
    </compound>
  </div>
</template>

<script>
import Compound from '../common/compound'
import FontTextBox from '../common/fontTextBox'
import Range from '../common/range'
import CurSelect from '../common/select'
import Bool from '../common/bool'
import TextBox from '../common/textBox'
import { usePreferencesStore } from '@/store/pinia/preferences'
import {
  tabSizeOptions,
  endOfLineOptions,
  textDirectionOptions,
  trimTrailingNewlineOptions,
  getDefaultEncodingOptions,
} from './config'

export default {
  components: {
    Compound,
    FontTextBox,
    Range,
    CurSelect,
    Bool,
    TextBox,
  },
  data() {
    this.tabSizeOptions = tabSizeOptions
    this.endOfLineOptions = endOfLineOptions
    this.textDirectionOptions = textDirectionOptions
    this.trimTrailingNewlineOptions = trimTrailingNewlineOptions
    this.defaultEncodingOptions = getDefaultEncodingOptions()
    return {}
  },
  computed: {
    preferencesStore() {
      return usePreferencesStore()
    },
    fontSize() {
      return this.preferencesStore.fontSize
    },
    editorFontFamily() {
      return this.preferencesStore.editorFontFamily
    },
    lineHeight() {
      return this.preferencesStore.lineHeight
    },
    autoPairBracket() {
      return this.preferencesStore.autoPairBracket
    },
    autoPairMarkdownSyntax() {
      return this.preferencesStore.autoPairMarkdownSyntax
    },
    autoPairQuote() {
      return this.preferencesStore.autoPairQuote
    },
    tabSize() {
      return this.preferencesStore.tabSize
    },
    endOfLine() {
      return this.preferencesStore.endOfLine
    },
    textDirection() {
      return this.preferencesStore.textDirection
    },
    codeFontSize() {
      return this.preferencesStore.codeFontSize
    },
    codeFontFamily() {
      return this.preferencesStore.codeFontFamily
    },
    codeBlockLineNumbers() {
      return this.preferencesStore.codeBlockLineNumbers
    },
    trimUnnecessaryCodeBlockEmptyLines() {
      return this.preferencesStore.trimUnnecessaryCodeBlockEmptyLines
    },
    hideQuickInsertHint() {
      return this.preferencesStore.hideQuickInsertHint
    },
    hideLinkPopup() {
      return this.preferencesStore.hideLinkPopup
    },
    autoCheck() {
      return this.preferencesStore.autoCheck
    },
    editorLineWidth() {
      return this.preferencesStore.editorLineWidth
    },
    defaultEncoding() {
      return this.preferencesStore.defaultEncoding
    },
    autoGuessEncoding() {
      return this.preferencesStore.autoGuessEncoding
    },
    trimTrailingNewline() {
      return this.preferencesStore.trimTrailingNewline
    },
  },
  methods: {
    onSelectChange(type, value) {
      this.preferencesStore.setSinglePreference({ type, value })
    },
  },
}
</script>

<style scoped>
  .pref-editor {
    & .image-ctrl {
      font-size: 14px;
      user-select: none;
      margin: 20px 0;
      color: var(--editorColor);
      & label {
        display: block;
        margin: 20px 0;
      }
    }
  }
</style>
