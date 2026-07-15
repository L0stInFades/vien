<template>
  <section class="pref-select-item" :class="{'ag-underdevelop': disable}">
    <div class="description" v-if="description">
      <span>{{description}}:</span>
      <i class="el-icon-info"
        v-if="more"
        @click="handleMoreClick"
      ></i>
    </div>
    <el-select
      v-model="localValue"
      @change="select"
      :disabled="disable"
    >
      <el-option
        v-for="item in options"
        :key="item.value"
        :label="item.label"
        :value="item.value">
      </el-option>
    </el-select>
    <div v-if="notes" class="notes">
      {{notes}}
    </div>
  </section>
</template>

<script>
export default {
  data() {
    return {
      localValue: this.currentValue,
    }
  },
  props: {
    description: String,
    notes: String,
    currentValue: String | Number,
    options: Array,
    onChange: Function,
    more: String,
    disable: {
      type: Boolean,
      default: false,
    },
  },
  watch: {
    '$props.currentValue': function (value, oldValue) {
      if (value !== oldValue) {
        this.localValue = value
      }
    },
  },
  methods: {
    handleMoreClick() {
      if (typeof this.more === 'string') {
        window.api.shell.openExternal(this.more)
      }
    },
    select(value) {
      this.onChange(value)
    },
  },
}
</script>

<style>
.pref-select-item {
  margin: 18px 0;
  padding: 14px 16px;
  font-size: 14px;
  color: var(--editorColor);
  border-radius: 18px;
  border: 1px solid var(--panelSubtleBorderColor);
  background: rgba(255, 255, 255, 0.52);
  & .notes {
    margin-top: 10px;
    font-size: 12px;
    line-height: 1.6;
    color: var(--panelMutedColor);
  }
  & .el-select {
    width: 100%;
  }
  & input.el-input__inner {
    height: 42px;
    background:
      linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(255, 255, 255, 0.66)),
      var(--controlBgColor);
    color: var(--editorColor);
    border-color: var(--controlBorderColor);
    border-radius: 14px;
  }
  & .el-input__icon,
  & .el-input__inner {
    line-height: 42px;
  }
}
.pref-select-item .description {
  margin-bottom: 12px;
  & i {
    cursor: pointer;
    opacity: .7;
    color: var(--iconColor);
  }
  & i:hover {
    color: var(--themeColor);
  }
}
li.el-select-dropdown__item {
  color: var(--editorColor);
  height: 36px;
  line-height: 36px;
}
li.el-select-dropdown__item.hover, li.el-select-dropdown__item:hover {
  background: var(--floatHoverColor);
}
div.el-select-dropdown {
  background: var(--floatBgColor);
  border-color: var(--floatBorderColor);
  border-radius: 16px;
  box-shadow: var(--floatShadow);
  & .popper__arrow {
    display: none;
  }
}
</style>
