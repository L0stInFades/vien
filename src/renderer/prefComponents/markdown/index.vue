<template>
  <div class="pref-markdown">
    <h4>Markdown</h4>
    <compound>
      <template #head>
        <h6 class="title">Lists:</h6>
      </template>
      <template #children>
        <bool
          description="Prefer loose list items"
          :isOn="preferLooseListItem"
          :onChange="value => onSelectChange('preferLooseListItem', value)"
          more="https://spec.commonmark.org/0.29/#loose"
        ></bool>
        <cur-select
          description="Preferred marker for bullet lists"
          :currentValue="bulletListMarker"
          :options="bulletListMarkerOptions"
          :onChange="value => onSelectChange('bulletListMarker', value)"
          more="https://spec.commonmark.org/0.29/#bullet-list-marker"
        ></cur-select>
        <cur-select
          description="Preferred marker for ordered lists"
          :currentValue="orderListDelimiter"
          :options="orderListDelimiterOptions"
          :onChange="value => onSelectChange('orderListDelimiter', value)"
          more="https://spec.commonmark.org/0.29/#ordered-list"
        ></cur-select>
        <cur-select
          description="Preferred list indentation"
          :currentValue="listIndentation"
          :options="listIndentationOptions"
          :onChange="value => onSelectChange('listIndentation', value)"
        ></cur-select>
      </template>
    </compound>

    <compound>
      <template #head>
        <h6 class="title">Markdown extensions:</h6>
      </template>
      <template #children>
        <cur-select
          description="Front matter format"
          :currentValue="frontmatterType"
          :options="frontmatterTypeOptions"
          :onChange="value => onSelectChange('frontmatterType', value)"
        ></cur-select>
        <bool
          description="Enable Pandoc-style superscript and subscript"
          :isOn="superSubScript"
          :onChange="value => onSelectChange('superSubScript', value)"
          more="https://pandoc.org/MANUAL.html#superscripts-and-subscripts"
        ></bool>
        <bool
          description="Enable Pandoc-style footnotes"
          notes="Requires restart."
          :isOn="footnote"
          :onChange="value => onSelectChange('footnote', value)"
          more="https://pandoc.org/MANUAL.html#footnotes"
        ></bool>
      </template>
    </compound>

    <compound>
      <template #head>
        <h6 class="title">Compatibility:</h6>
      </template>
      <template #children>
        <bool
          description="Enable HTML rendering"
          :isOn="isHtmlEnabled"
          :onChange="value => onSelectChange('isHtmlEnabled', value)"
        ></bool>
        <bool
          description="Enable GitLab compatibility mode"
          :isOn="isGitlabCompatibilityEnabled"
          :onChange="value => onSelectChange('isGitlabCompatibilityEnabled', value)"
        ></bool>
      </template>
    </compound>

    <compound>
      <template #head>
        <h6 class="title">Diagrams:</h6>
      </template>
      <template #children>
        <cur-select
          description="Sequence diagram theme"
          :currentValue="sequenceTheme"
          :options="sequenceThemeOptions"
          :onChange="value => onSelectChange('sequenceTheme', value)"
          more="https://bramp.github.io/js-sequence-diagrams/"
        ></cur-select>
      </template>
    </compound>

    <compound>
      <template #head>
        <h6 class="title">Misc:</h6>
      </template>
      <template #children>
        <cur-select
          description="Preferred heading style"
          :currentValue="preferHeadingStyle"
          :options="preferHeadingStyleOptions"
          :onChange="value => onSelectChange('preferHeadingStyle', value)"
          :disable="true"
        ></cur-select>
      </template>
    </compound>
  </div>
</template>

<script>
import Compound from '../common/compound'
import Separator from '../common/separator'
import Bool from '../common/bool'
import CurSelect from '../common/select'
import { usePreferencesStore } from '@/store/pinia/preferences'
import {
  bulletListMarkerOptions,
  orderListDelimiterOptions,
  preferHeadingStyleOptions,
  listIndentationOptions,
  frontmatterTypeOptions,
  sequenceThemeOptions,
} from './config'

export default {
  components: {
    Compound,
    Separator,
    Bool,
    CurSelect,
  },
  data() {
    this.bulletListMarkerOptions = bulletListMarkerOptions
    this.orderListDelimiterOptions = orderListDelimiterOptions
    this.preferHeadingStyleOptions = preferHeadingStyleOptions
    this.listIndentationOptions = listIndentationOptions
    this.frontmatterTypeOptions = frontmatterTypeOptions
    this.sequenceThemeOptions = sequenceThemeOptions
    return {}
  },
  computed: {
    preferencesStore() {
      return usePreferencesStore()
    },
    preferLooseListItem() {
      return this.preferencesStore.preferLooseListItem
    },
    bulletListMarker() {
      return this.preferencesStore.bulletListMarker
    },
    orderListDelimiter() {
      return this.preferencesStore.orderListDelimiter
    },
    preferHeadingStyle() {
      return this.preferencesStore.preferHeadingStyle
    },
    listIndentation() {
      return this.preferencesStore.listIndentation
    },
    frontmatterType() {
      return this.preferencesStore.frontmatterType
    },
    superSubScript() {
      return this.preferencesStore.superSubScript
    },
    footnote() {
      return this.preferencesStore.footnote
    },
    isHtmlEnabled() {
      return this.preferencesStore.isHtmlEnabled
    },
    isGitlabCompatibilityEnabled() {
      return this.preferencesStore.isGitlabCompatibilityEnabled
    },
    sequenceTheme() {
      return this.preferencesStore.sequenceTheme
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
  .pref-markdown {
  }
</style>
